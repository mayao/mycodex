import Foundation

public struct AppServerConfiguration: Sendable, Equatable {
    public var baseURL: URL
    public var sessionToken: String?
    public var aiRequestConfiguration: AIRequestConfiguration?

    public init(
        baseURL: URL,
        sessionToken: String? = nil,
        aiRequestConfiguration: AIRequestConfiguration? = nil
    ) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.aiRequestConfiguration = aiRequestConfiguration
    }
}

public enum PortfolioWorkbenchAPIClientError: LocalizedError, Sendable {
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

private struct APIErrorEnvelope: Decodable {
    struct APIErrorPayload: Decodable {
        let id: String?
        let message: String
    }

    enum APIError: Decodable {
        case message(String)
        case payload(APIErrorPayload)

        init(from decoder: Decoder) throws {
            let singleValueContainer = try decoder.singleValueContainer()
            if let message = try? singleValueContainer.decode(String.self) {
                self = .message(message)
                return
            }

            let payload = try singleValueContainer.decode(APIErrorPayload.self)
            self = .payload(payload)
        }

        var message: String {
            switch self {
            case let .message(message):
                return message
            case let .payload(payload):
                return payload.message
            }
        }
    }

    let error: APIError
}

private let aiConfigHeaderName = "X-MyInvAI-AI-Config"

public final class PortfolioWorkbenchAPIClient: @unchecked Sendable {
    public struct AIChatMessage: Encodable, Sendable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public enum AIChatContext: Sendable, Equatable {
        case dashboard
        case holding(symbol: String)
    }

    private let configuration: AppServerConfiguration
    private let session: URLSessioning
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        configuration: AppServerConfiguration,
        session: URLSessioning = URLSession.shared
    ) {
        self.configuration = configuration
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
        self.encoder = JSONEncoder()
    }

    public func fetchDashboard(refresh: Bool = false, fast: Bool = false) async throws -> MobileDashboardPayload {
        var query: [URLQueryItem] = []
        if refresh {
            query.append(URLQueryItem(name: "refresh", value: "1"))
        }
        if fast {
            query.append(URLQueryItem(name: "fast", value: "1"))
        }
        return try await send(path: "api/mobile/dashboard", query: query)
    }

    public func fetchDashboardAI(refresh: Bool = false) async throws -> MobileDashboardAIRefreshPayload {
        var query: [URLQueryItem] = []
        if refresh {
            query.append(URLQueryItem(name: "refresh", value: "1"))
        }
        return try await send(path: "api/mobile/dashboard-ai", query: query)
    }

    public func fetchAIServiceStatus() async throws -> AIServiceStatusPayload {
        try await send(path: "api/mobile/ai-service-status")
    }

    public func fetchHoldingDetail(symbol: String, refresh: Bool = false) async throws -> HoldingDetailPayload {
        var query = [URLQueryItem(name: "symbol", value: symbol)]
        if refresh {
            query.append(URLQueryItem(name: "refresh", value: "1"))
        }
        return try await send(path: "api/mobile/stock-detail", query: query)
    }

    public func fetchHoldingDetailAI(symbol: String, refresh: Bool = false) async throws -> HoldingDetailAIPayload {
        var query = [URLQueryItem(name: "symbol", value: symbol)]
        if refresh {
            query.append(URLQueryItem(name: "refresh", value: "1"))
        }
        return try await send(path: "api/mobile/stock-detail-ai", query: query)
    }

    public func sendAIChat(
        context: AIChatContext,
        messages: [AIChatMessage]
    ) async throws -> MobileAIChatReplyPayload {
        struct RequestBody: Encodable {
            let contextType: String
            let symbol: String?
            let messages: [AIChatMessage]

            enum CodingKeys: String, CodingKey {
                case contextType = "context_type"
                case symbol
                case messages
            }
        }

        let body: RequestBody
        switch context {
        case .dashboard:
            body = RequestBody(contextType: "dashboard", symbol: nil, messages: messages)
        case let .holding(symbol):
            body = RequestBody(contextType: "holding", symbol: symbol, messages: messages)
        }

        var request = makeRequest(path: "api/mobile/ai-chat", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await send(request: request)
    }

    public func uploadStatement(
        accountID: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        broker: String? = nil,
        statementType: String? = nil
    ) async throws -> StatementUploadEnvelope {
        var body = MultipartFormDataBody()
        if !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body.appendField(name: "account_id", value: accountID)
        }
        if let broker, !broker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body.appendField(name: "broker", value: broker)
        }
        if let statementType, !statementType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body.appendField(name: "statement_type", value: statementType)
        }
        body.appendFile(name: "statement_file", fileName: fileName, mimeType: mimeType, fileData: fileData)
        body.finalize()

        var request = makeRequest(path: "api/mobile/upload-statement", method: "POST")
        request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data

        return try await send(request: request)
    }

    public func bootstrapDeviceAccount(
        deviceID: String,
        deviceName: String
    ) async throws -> MobileSessionPayload {
        struct RequestBody: Encodable {
            let deviceID: String
            let deviceName: String

            enum CodingKeys: String, CodingKey {
                case deviceID = "device_id"
                case deviceName = "device_name"
            }
        }

        var request = makeRequest(path: "api/mobile/auth/device/bootstrap", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RequestBody(deviceID: deviceID, deviceName: deviceName))
        return try await send(request: request)
    }

    public func requestPhoneCode(phoneNumber: String) async throws -> PhoneCodeRequestPayload {
        struct RequestBody: Encodable {
            let phoneNumber: String

            enum CodingKeys: String, CodingKey {
                case phoneNumber = "phone_number"
            }
        }

        var request = makeRequest(path: "api/mobile/auth/phone/request-code", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RequestBody(phoneNumber: phoneNumber))
        return try await send(request: request)
    }

    public func loginWithPhone(phoneNumber: String, code: String) async throws -> MobileSessionPayload {
        struct RequestBody: Encodable {
            let phoneNumber: String
            let code: String

            enum CodingKeys: String, CodingKey {
                case phoneNumber = "phone_number"
                case code
            }
        }

        var request = makeRequest(path: "api/mobile/auth/phone/verify", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RequestBody(phoneNumber: phoneNumber, code: code))
        return try await send(request: request)
    }

    public func loginWithWeChat(displayName: String? = nil) async throws -> MobileSessionPayload {
        struct RequestBody: Encodable {
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        var request = makeRequest(path: "api/mobile/auth/wechat/login", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RequestBody(displayName: displayName))
        return try await send(request: request)
    }

    public func loginAsLocalOwner() async throws -> MobileSessionPayload {
        var request = makeRequest(path: "api/mobile/auth/dev/owner", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return try await send(request: request)
    }

    public func fetchCurrentSession() async throws -> MobileUserEnvelope {
        try await send(path: "api/mobile/auth/session")
    }

    public func fetchImportCenter() async throws -> ImportCenterPayload {
        try await send(path: "api/mobile/import-center")
    }

    public func logout() async throws -> BasicMessagePayload {
        var request = makeRequest(path: "api/mobile/auth/logout", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return try await send(request: request)
    }

    private func send<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(request: makeRequest(path: path, method: "GET", query: query))
    }

    private func send<T: Decodable>(request: URLRequest) async throws -> T {
        let payload: Data
        let response: URLResponse

        do {
            (payload, response) = try await session.data(for: request)
        } catch {
            throw PortfolioWorkbenchAPIClientError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PortfolioWorkbenchAPIClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: payload) {
                throw PortfolioWorkbenchAPIClientError.server(statusCode: httpResponse.statusCode, message: envelope.error.message)
            }

            throw PortfolioWorkbenchAPIClientError.server(
                statusCode: httpResponse.statusCode,
                message: "请求失败，状态码 \(httpResponse.statusCode)。"
            )
        }

        do {
            return try decoder.decode(T.self, from: payload)
        } catch {
            throw PortfolioWorkbenchAPIClientError.transport("数据解析失败: \(error.localizedDescription)")
        }
    }

    private func makeRequest(path: String, method: String, query: [URLQueryItem] = []) -> URLRequest {
        let url = makeURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = configuration.sessionToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let encodedAIConfiguration = encodeAIRequestConfiguration(configuration.aiRequestConfiguration) {
            request.setValue(encodedAIConfiguration, forHTTPHeaderField: aiConfigHeaderName)
        }
        request.timeoutInterval = 45
        return request
    }

    private func encodeAIRequestConfiguration(_ value: AIRequestConfiguration?) -> String? {
        guard let value, let data = try? encoder.encode(value) else {
            return nil
        }
        return data.base64EncodedString()
    }

    private func makeURL(path: String, query: [URLQueryItem]) -> URL {
        let baseURL = configuration.baseURL.appending(path: path)
        guard !query.isEmpty else {
            return baseURL
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = query
        return components?.url ?? baseURL
    }
}
