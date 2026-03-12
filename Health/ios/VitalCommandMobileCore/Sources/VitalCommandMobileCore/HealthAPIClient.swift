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
    public var token: String?

    public init(
        configuration: AppServerConfiguration,
        session: URLSessioning = URLSession.shared,
        token: String? = nil
    ) {
        self.configuration = configuration
        self.session = session
        self.token = token

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

    public func logoutSession() async throws {
        let _: [String: Bool] = try await sendJSON(path: "api/auth/logout", body: [String: String]())
    }

    public func fetchDashboard() async throws -> HealthHomePageData {
        try await send(path: "api/dashboard")
    }

    public func fetchReports() async throws -> ReportsIndexData {
        try await send(path: "api/reports")
    }

    public func fetchReportDetail(snapshotId: String) async throws -> HealthReportSnapshotRecord {
        try await send(path: "api/reports/\(snapshotId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? snapshotId)")
    }

    public func fetchImportTasks() async throws -> ImportTaskListResponse {
        try await send(path: "api/imports")
    }

    public func fetchImportTask(taskID: String) async throws -> ImportTaskResponse {
        try await send(path: "api/imports/\(taskID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskID)")
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

    public func chatWithAI(_ input: AIChatRequest) async throws -> AIChatResponse {
        try await sendJSON(path: "api/ai/chat", body: input)
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

    public func triggerSync() async throws -> SyncTriggerResponse {
        try await sendEmpty(path: "api/sync/trigger")
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
        } catch {
            throw HealthAPIClientError.transport("数据解析失败: \(error.localizedDescription)")
        }
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        let url = configuration.baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.timeoutInterval = 30
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

public struct ImportEnvelope: Codable, Sendable {
    public let result: ImportExecutionResult
}
