import Foundation

public struct AppServerConfiguration: Sendable, Equatable {
    public var baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }
}

public enum HealthAPIClientError: LocalizedError, Sendable {
    case invalidResponse
    case server(statusCode: Int, message: String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务响应格式无效。"
        case let .server(_, message):
            return message
        case let .transport(message):
            return message
        }
    }
}

public protocol URLSessioning: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessioning {}

struct APIErrorEnvelope: Decodable {
    struct APIErrorPayload: Decodable {
        let id: String?
        let message: String
    }

    let error: APIErrorPayload
}

public final class HealthAPIClient: @unchecked Sendable {
    private let configuration: AppServerConfiguration
    private let session: URLSessioning
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenLock = NSLock()
    private var _token: String?
    public var token: String? {
        get { tokenLock.lock(); defer { tokenLock.unlock() }; return _token }
        set { tokenLock.lock(); defer { tokenLock.unlock() }; _token = newValue }
    }

    public init(
        configuration: AppServerConfiguration,
        session: URLSessioning = URLSession.shared,
        token: String? = nil
    ) {
        self.configuration = configuration
        self.session = session
        self._token = token

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    // MARK: - Auth APIs

    public func requestVerificationCode(_ input: PhoneCodeRequest) async throws -> PhoneCodeResponse {
        try await sendJSON(path: "api/auth/request-code", body: input)
    }

    public func verifyCode(_ input: VerifyCodeRequest) async throws -> VerifyCodeResponse {
        try await sendJSON(path: "api/auth/verify", body: input)
    }

    public func fetchCurrentUser() async throws -> UserMeResponse {
        try await send(path: "api/auth/me")
    }

    public func deviceLogin(_ input: DeviceLoginRequest) async throws -> DeviceLoginResponse {
        try await sendJSON(path: "api/auth/device-login", body: input)
    }

    public func signInWithApple(_ input: AppleSignInRequest) async throws -> AppleSignInResponse {
        try await sendJSON(path: "api/auth/apple/sign-in", body: input)
    }

    public func linkAppleIdentity(_ input: AppleLinkRequest) async throws -> AppleLinkResponse {
        try await sendJSON(path: "api/auth/apple/link", body: input)
    }

    public func logoutSession() async throws {
        let _: [String: Bool] = try await sendJSON(path: "api/auth/logout", body: [String: String]())
    }

    public func fetchUsers() async throws -> UserListResponse {
        try await send(path: "api/auth/users")
    }

    public func switchUser(_ input: SwitchUserRequest) async throws -> SwitchUserResponse {
        try await sendJSON(path: "api/auth/switch-user", body: input)
    }

    public func fetchDashboard() async throws -> HealthHomePageData {
        try await send(path: "api/dashboard")
    }

    public func fetchReports() async throws -> ReportsIndexData {
        try await send(path: "api/reports")
    }

    public func fetchReportDetail(snapshotId: String) async throws -> HealthReportSnapshotRecord {
        try await send(path: "api/reports/\(encodePathSegment(snapshotId))")
    }

    public func fetchImportTasks() async throws -> ImportTaskListResponse {
        try await send(path: "api/imports")
    }

    public func fetchImportTask(taskID: String) async throws -> ImportTaskResponse {
        try await send(path: "api/imports/\(encodePathSegment(taskID))")
    }

    public func importData(
        importerKey: ImporterKey,
        fileName: String,
        mimeType: String,
        fileData: Data,
        extractedText: String? = nil
    ) async throws -> ImportAcceptedResponse {
        var body = MultipartFormDataBody()
        body.appendField(name: "importerKey", value: importerKey.rawValue)
        if let extractedText, extractedText.isEmpty == false {
            body.appendField(name: "extractedText", value: extractedText)
        }
        body.appendFile(name: "file", fileName: fileName, mimeType: mimeType, fileData: fileData)
        body.finalize()

        var request = makeRequest(path: "api/imports", method: "POST")
        request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data

        return try await send(request: request)
    }

    public func syncHealthKit(_ input: HealthKitSyncRequest) async throws -> HealthKitSyncEnvelope {
        try await sendJSON(path: "api/healthkit/sync", body: input)
    }

    public func fetchDocumentInsights(type: String) async throws -> DocumentInsightResponse {
        var components = URLComponents(url: configuration.baseURL.appending(path: "api/ai/insights"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "type", value: type)]
        var request = makeRequest(url: components.url!, method: "GET")
        request.timeoutInterval = 90  // AI analysis can take up to 3×18s fallback chain
        return try await send(request: request)
    }

    public func chatWithAI(_ input: AIChatRequest) async throws -> AIChatResponse {
        try await sendJSON(path: "api/ai/chat", body: input)
    }

    /// Stream AI chat response via SSE. Yields content chunks as they arrive.
    public func streamChatWithAI(_ input: AIChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = makeRequest(path: "api/ai/chat/stream", method: "POST")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 120
                    request.httpBody = try encoder.encode(input)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        continuation.finish(throwing: HealthAPIClientError.server(
                            statusCode: httpResponse.statusCode,
                            message: "AI 对话流式响应失败（\(httpResponse.statusCode)）"
                        ))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))
                            if data == "[DONE]" {
                                break
                            }
                            // Parse OpenAI-compatible SSE chunk
                            if let jsonData = data.data(using: .utf8),
                               let chunk = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let choices = chunk["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func authorizeDevice(_ input: DeviceAuthorizeRequest) async throws -> DeviceAuthorizeResponse {
        try await sendJSON(path: "api/devices/authorize", body: input, additionalAcceptedStatusCodes: [501])
    }

    public func fetchDeviceStatus() async throws -> DeviceStatusResponse {
        try await send(path: "api/devices/status")
    }

    public func disconnectDevice(_ input: DeviceDisconnectRequest) async throws -> PrivacyPlaceholderResponse {
        var request = makeRequest(path: "api/devices/status", method: "DELETE")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(input)
        return try await send(request: request, additionalAcceptedStatusCodes: [501])
    }

    // MARK: - Health Plans

    public func fetchHealthPlan() async throws -> HealthPlanDashboard {
        try await send(path: "api/health-plans")
    }

    public func generateSuggestions() async throws -> GenerateSuggestionsResponse {
        try await sendEmpty(path: "api/health-plans/generate")
    }

    public func acceptSuggestion(_ input: AcceptSuggestionRequest) async throws -> AcceptSuggestionResponse {
        try await sendJSON(path: "api/health-plans", body: input)
    }

    public func manualCheckIn(_ input: ManualCheckInRequest) async throws -> ManualCheckInResponse {
        try await sendJSON(path: "api/health-plans", body: input)
    }

    public func updatePlanStatus(_ input: UpdatePlanStatusRequest) async throws -> UpdatePlanStatusResponse {
        try await sendJSON(path: "api/health-plans", body: input)
    }

    public func updatePlanItem(_ input: UpdatePlanItemRequest) async throws -> UpdatePlanItemResponse {
        try await sendJSON(path: "api/health-plans", body: input)
    }

    public func triggerPlanCheck() async throws -> PlanCompletionCheckResponse {
        try await sendEmpty(path: "api/health-plans/check")
    }

    // MARK: - Sync

    public func fetchSyncStatus() async throws -> SyncStatusResponse {
        try await send(path: "api/sync/status")
    }

    public func triggerSync(peerURLs: [String] = []) async throws -> SyncTriggerResponse {
        try await sendJSON(path: "api/sync/trigger", body: SyncTriggerRequest(peerUrls: peerURLs))
    }

    // MARK: - Privacy

    public func requestPrivacyExport(_ input: PrivacyExportRequest) async throws -> PrivacyPlaceholderResponse {
        try await sendJSON(path: "api/privacy/export", body: input, additionalAcceptedStatusCodes: [501])
    }

    public func requestPrivacyDelete(_ input: PrivacyDeleteRequest) async throws -> PrivacyPlaceholderResponse {
        try await sendJSON(path: "api/privacy/delete", body: input, additionalAcceptedStatusCodes: [501])
    }

    private func sendJSON<T: Decodable, Body: Encodable>(
        path: String,
        body: Body,
        additionalAcceptedStatusCodes: Set<Int> = []
    ) async throws -> T {
        var request = makeRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await send(request: request, additionalAcceptedStatusCodes: additionalAcceptedStatusCodes)
    }

    private func send<T: Decodable>(path: String) async throws -> T {
        try await send(request: makeRequest(path: path, method: "GET"))
    }

    private func sendEmpty<T: Decodable>(path: String) async throws -> T {
        try await send(request: makeRequest(path: path, method: "POST"))
    }

    private func send<T: Decodable>(
        request: URLRequest,
        additionalAcceptedStatusCodes: Set<Int> = []
    ) async throws -> T {
        let payload: Data
        let response: URLResponse

        do {
            (payload, response) = try await session.data(for: request)
        } catch {
            throw HealthAPIClientError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HealthAPIClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) || additionalAcceptedStatusCodes.contains(httpResponse.statusCode) else {
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: payload) {
                throw HealthAPIClientError.server(statusCode: httpResponse.statusCode, message: envelope.error.message)
            }

            throw HealthAPIClientError.server(statusCode: httpResponse.statusCode, message: "请求失败，状态码 \(httpResponse.statusCode)。")
        }

        do {
            return try decoder.decode(T.self, from: payload)
        } catch let decodingError as DecodingError {
            let detail: String
            switch decodingError {
            case let .keyNotFound(key, context):
                detail = "字段缺失: \(key.stringValue) 路径: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case let .typeMismatch(type, context):
                detail = "类型不匹配: 期望 \(type) 路径: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case let .valueNotFound(type, context):
                detail = "值为空: 期望 \(type) 路径: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case let .dataCorrupted(context):
                detail = "数据损坏: \(context.debugDescription) 路径: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            @unknown default:
                detail = decodingError.localizedDescription
            }
            throw HealthAPIClientError.transport("数据解析失败[\(String(describing: T.self))]: \(detail)")
        } catch {
            throw HealthAPIClientError.transport("数据解析失败: \(error.localizedDescription)")
        }
    }

    public func fetchModelStatus() async throws -> AIModelStatusResponse {
        try await send(path: "api/ai/model-status")
    }

    private func encodePathSegment(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    public func setPreferredProvider(_ provider: String) async throws -> AIModelStatusResponse {
        try await sendJSON(path: "api/ai/model-status", body: SetPreferredProviderRequest(provider: provider))
    }

    public func fetchSuggestedQuestions() async throws -> SuggestedQuestionsResponse {
        try await send(path: "api/ai/suggested-questions")
    }

    public func fetchPlanProgress() async throws -> PlanProgressReport {
        try await send(path: "api/health/plan-progress")
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        makeRequest(url: configuration.baseURL.appending(path: path), method: method)
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.timeoutInterval = 60
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

public struct ImportEnvelope: Codable, Sendable {
    public let result: ImportExecutionResult
}
