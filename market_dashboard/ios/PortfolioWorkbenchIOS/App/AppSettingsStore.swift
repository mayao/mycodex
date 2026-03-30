import Foundation
import LocalAuthentication
import PortfolioWorkbenchMobileCore
import UIKit

enum DeviceBiometryType: String, Codable {
    case none
    case faceID
    case touchID
    case opticID

    init(_ biometryType: LABiometryType) {
        switch biometryType {
        case .faceID:
            self = .faceID
        case .touchID:
            self = .touchID
        case .opticID:
            self = .opticID
        default:
            self = .none
        }
    }

    var displayName: String {
        switch self {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "本机验证"
        }
    }
}

enum AppSecurityError: LocalizedError {
    case biometricUnavailable(String)
    case biometricAuthenticationFailed

    var errorDescription: String? {
        switch self {
        case let .biometricUnavailable(message):
            return message
        case .biometricAuthenticationFailed:
            return "本机验证未通过，请重试。"
        }
    }
}

struct SavedServerEndpoint: Identifiable, Codable, Equatable {
    var id: String { url }
    let name: String
    let url: String
}

private struct ScopedServerSession: Codable {
    let sessionToken: String
    let currentUser: MobileUser
    let isUsingLocalMockSession: Bool
}

enum LongbridgeSessionState: String, Codable {
    case unauthorized
    case authorizing
    case authorized
    case tokenExpired
    case error
}

@MainActor
final class AppSettingsStore: ObservableObject {
    static let defaultServerURLString = "http://127.0.0.1:8008/"
    static let remoteDefaultServerURLString = "http://10.8.144.16:8008/"
    static let defaultServerURLInfoKey = "PORTFOLIO_WORKBENCH_DEFAULT_SERVER_URL"
    static let autoMockLoginInfoKey = "PORTFOLIO_WORKBENCH_AUTO_MOCK_LOGIN"
    static let autoOwnerLoginInfoKey = "PORTFOLIO_WORKBENCH_AUTO_OWNER_LOGIN"
    static let resetStateOnLaunchInfoKey = "PORTFOLIO_WORKBENCH_RESET_STATE_ON_LAUNCH"
    static let serverURLKey = "portfolio-workbench-ios.server-url"
    static let scopedSessionsKey = "portfolio-workbench-ios.scoped-sessions"
    static let localScopedSessionKey = "portfolio-workbench-ios.local-scoped-session"
    static let savedServersKey = "portfolio-workbench-ios.saved-servers"
    static let hideSensitiveAmountsKey = "portfolio-workbench-ios.hide-sensitive-amounts"
    static let aiSettingsKey = "portfolio-workbench-ios.ai-settings"
    static let standaloneAIEntryEnabledKey = "portfolio-workbench-ios.standalone-ai-entry-enabled"
    static let sessionTokenKey = "portfolio-workbench-ios.session-token"
    static let currentUserKey = "portfolio-workbench-ios.current-user"
    static let localMockSessionKey = "portfolio-workbench-ios.local-mock-session"
    static let biometricUnlockEnabledKey = "portfolio-workbench-ios.biometric-unlock-enabled"
    static let automaticDeviceRestoreSuppressedKey = "portfolio-workbench-ios.device-restore-suppressed"
    static let longbridgeClientIDKey = "portfolio-workbench-ios.longbridge-client-id"
    static let longbridgePKCEContextKey = "portfolio-workbench-ios.longbridge-pkce-context"
    static let longbridgeSessionStateKey = "portfolio-workbench-ios.longbridge-session-state"
    static let longbridgeAuthErrorMessageKey = "portfolio-workbench-ios.longbridge-auth-error-message"
    static let longbridgeEndpointBaseURLKey = "portfolio-workbench-ios.longbridge-endpoint-base-url"
    static let longbridgeRedirectURI = "myinvai://longbridge/oauth/callback"
    private static let sessionValidationInterval: TimeInterval = 90

    private let identityStore: DeviceAccountIdentityStore
    private let aiCredentialStore: AIProviderCredentialStore
    private let longbridgeAuthService: LongbridgeAuthService
    private let bundledDefaultServerURLString: String?
    private var scopedSessions: [String: ScopedServerSession]
    private var lastSessionValidationAt: Date?
    private var lastValidatedServerURLString: String?
    private var automaticRestoreAttemptServerURLString: String?
    private var pendingLongbridgePKCEContext: LongbridgePKCEContext?
    private var lastLongbridgeRefreshFailureAt: Date?
    private static let longbridgeRefreshCooldownSeconds: TimeInterval = 60
    private var automaticDeviceRestoreSuppressed: Bool {
        didSet {
            UserDefaults.standard.set(automaticDeviceRestoreSuppressed, forKey: Self.automaticDeviceRestoreSuppressedKey)
        }
    }

    @Published var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey)
            lastSessionValidationAt = nil
            lastValidatedServerURLString = nil
            automaticRestoreAttemptServerURLString = nil
            restoreScopedSessionForCurrentServer()
        }
    }
    @Published private(set) var savedServers: [SavedServerEndpoint] {
        didSet {
            if let data = try? JSONEncoder().encode(savedServers) {
                UserDefaults.standard.set(data, forKey: Self.savedServersKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.savedServersKey)
            }
        }
    }
    @Published var hideSensitiveAmounts: Bool {
        didSet {
            UserDefaults.standard.set(hideSensitiveAmounts, forKey: Self.hideSensitiveAmountsKey)
        }
    }
    @Published private(set) var aiSettingsProfile: AppAISettingsProfile {
        didSet {
            if let data = try? JSONEncoder().encode(aiSettingsProfile) {
                UserDefaults.standard.set(data, forKey: Self.aiSettingsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.aiSettingsKey)
            }
        }
    }
    @Published var sessionToken: String? {
        didSet {
            if let sessionToken, !sessionToken.isEmpty {
                UserDefaults.standard.set(sessionToken, forKey: Self.sessionTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.sessionTokenKey)
            }
            persistCurrentScopedSession()
        }
    }
    @Published private(set) var isUsingLocalMockSession: Bool {
        didSet {
            UserDefaults.standard.set(isUsingLocalMockSession, forKey: Self.localMockSessionKey)
            persistCurrentScopedSession()
        }
    }
    @Published private(set) var currentUser: MobileUser? {
        didSet {
            if let currentUser, let data = try? JSONEncoder().encode(currentUser) {
                UserDefaults.standard.set(data, forKey: Self.currentUserKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentUserKey)
            }
            persistCurrentScopedSession()
        }
    }
    @Published private(set) var deviceAccountProfile: DeviceAccountProfile {
        didSet {
            identityStore.persist(deviceAccountProfile)
        }
    }
    @Published var biometricUnlockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(biometricUnlockEnabled, forKey: Self.biometricUnlockEnabledKey)
        }
    }
    @Published private(set) var requiresBiometricUnlock: Bool
    @Published private(set) var biometryType: DeviceBiometryType
    @Published private(set) var isRestoringDeviceSession: Bool
    @Published private(set) var connectionStatusMessage: String?
    @Published private(set) var longbridgeSessionState: LongbridgeSessionState {
        didSet {
            UserDefaults.standard.set(longbridgeSessionState.rawValue, forKey: Self.longbridgeSessionStateKey)
        }
    }
    @Published private(set) var longbridgeClientID: String? {
        didSet {
            if let longbridgeClientID, !longbridgeClientID.isEmpty {
                UserDefaults.standard.set(longbridgeClientID, forKey: Self.longbridgeClientIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.longbridgeClientIDKey)
            }
        }
    }
    @Published private(set) var longbridgeAuthErrorMessage: String? {
        didSet {
            if let longbridgeAuthErrorMessage, !longbridgeAuthErrorMessage.isEmpty {
                UserDefaults.standard.set(longbridgeAuthErrorMessage, forKey: Self.longbridgeAuthErrorMessageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.longbridgeAuthErrorMessageKey)
            }
        }
    }
    @Published private(set) var longbridgeEndpointBaseURL: String? {
        didSet {
            if let longbridgeEndpointBaseURL, !longbridgeEndpointBaseURL.isEmpty {
                UserDefaults.standard.set(longbridgeEndpointBaseURL, forKey: Self.longbridgeEndpointBaseURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.longbridgeEndpointBaseURLKey)
            }
        }
    }
    @Published private(set) var longbridgeTokenExpiresAt: Date?
    @Published private(set) var standaloneAIEntryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(standaloneAIEntryEnabled, forKey: Self.standaloneAIEntryEnabledKey)
        }
    }

    init(
        identityStore: DeviceAccountIdentityStore = .shared,
        aiCredentialStore: AIProviderCredentialStore = .shared,
        longbridgeAuthService: LongbridgeAuthService = LongbridgeAuthService()
    ) {
        self.identityStore = identityStore
        self.aiCredentialStore = aiCredentialStore
        self.longbridgeAuthService = longbridgeAuthService

        let bundledDefaultURL =
            (Bundle.main.object(forInfoDictionaryKey: Self.defaultServerURLInfoKey) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBundledDefaultURL = Self.normalizeServerURLString(bundledDefaultURL)
        self.bundledDefaultServerURLString = normalizedBundledDefaultURL
        let initialServerURL =
            Self.normalizeServerURLString(UserDefaults.standard.string(forKey: Self.serverURLKey))
            ?? normalizedBundledDefaultURL
            ?? Self.defaultServerURLString
        self.serverURLString = initialServerURL
        if let data = UserDefaults.standard.data(forKey: Self.scopedSessionsKey),
           let decoded = try? JSONDecoder().decode([String: ScopedServerSession].self, from: data) {
            self.scopedSessions = decoded
        } else {
            self.scopedSessions = [:]
        }
        if let data = UserDefaults.standard.data(forKey: Self.savedServersKey),
           let decoded = try? JSONDecoder().decode([SavedServerEndpoint].self, from: data) {
            self.savedServers = decoded
        } else {
            self.savedServers = []
        }
        self.hideSensitiveAmounts = UserDefaults.standard.bool(forKey: Self.hideSensitiveAmountsKey)
        if let data = UserDefaults.standard.data(forKey: Self.aiSettingsKey),
           let decoded = try? JSONDecoder().decode(AppAISettingsProfile.self, from: data) {
            self.aiSettingsProfile = Self.migrateLegacyDefaultAIProfileIfNeeded(decoded, credentialStore: aiCredentialStore)
        } else {
            self.aiSettingsProfile = .default
        }
        let legacySessionToken = UserDefaults.standard.string(forKey: Self.sessionTokenKey)
        let legacyIsUsingLocalMockSession = UserDefaults.standard.bool(forKey: Self.localMockSessionKey)
        let legacyCurrentUser: MobileUser? =
            if let data = UserDefaults.standard.data(forKey: Self.currentUserKey),
               let decoded = try? JSONDecoder().decode(MobileUser.self, from: data) {
                decoded
            } else {
                nil
            }
        if let initialScopedSession = self.scopedSessions[initialServerURL] ?? self.scopedSessions[Self.localScopedSessionKey] {
            self.sessionToken = initialScopedSession.sessionToken
            self.currentUser = initialScopedSession.currentUser
            self.isUsingLocalMockSession = initialScopedSession.isUsingLocalMockSession
        } else {
            self.sessionToken = legacySessionToken
            self.currentUser = legacyCurrentUser
            self.isUsingLocalMockSession = legacyIsUsingLocalMockSession
        }
        self.deviceAccountProfile = identityStore.resolveProfile(defaultDeviceLabel: Self.currentDeviceLabel)
        self.biometricUnlockEnabled = UserDefaults.standard.object(forKey: Self.biometricUnlockEnabledKey) as? Bool ?? false
        self.requiresBiometricUnlock = false
        self.biometryType = .none
        self.automaticRestoreAttemptServerURLString = nil
        self.automaticDeviceRestoreSuppressed = UserDefaults.standard.bool(forKey: Self.automaticDeviceRestoreSuppressedKey)
        self.isRestoringDeviceSession = false
        self.connectionStatusMessage = nil
        self.standaloneAIEntryEnabled = UserDefaults.standard.bool(forKey: Self.standaloneAIEntryEnabledKey)
        self.longbridgeSessionState =
            LongbridgeSessionState(rawValue: UserDefaults.standard.string(forKey: Self.longbridgeSessionStateKey) ?? "")
            ?? .unauthorized
        self.longbridgeClientID = UserDefaults.standard.string(forKey: Self.longbridgeClientIDKey)
        self.longbridgeAuthErrorMessage = UserDefaults.standard.string(forKey: Self.longbridgeAuthErrorMessageKey)
        self.longbridgeEndpointBaseURL = UserDefaults.standard.string(forKey: Self.longbridgeEndpointBaseURLKey)
        self.longbridgeTokenExpiresAt = nil
        self.pendingLongbridgePKCEContext =
            if let data = UserDefaults.standard.data(forKey: Self.longbridgePKCEContextKey) {
                try? JSONDecoder().decode(LongbridgePKCEContext.self, from: data)
            } else {
                nil
            }

        if Self.isLoopbackServerURLString(self.serverURLString),
           let bundledDefaultURL = self.bundledDefaultServerURLString,
           !Self.isLoopbackServerURLString(bundledDefaultURL) {
            self.serverURLString = bundledDefaultURL
        }

        let environment = ProcessInfo.processInfo.environment
        let autoMockLogin = environment[Self.autoMockLoginInfoKey]?.lowercased()
        let shouldResetState =
            environment[Self.resetStateOnLaunchInfoKey] == "1"
            || environment[Self.resetStateOnLaunchInfoKey]?.lowercased() == "true"
        if shouldResetState {
            self.sessionToken = nil
            self.currentUser = nil
            self.isUsingLocalMockSession = false
            self.automaticDeviceRestoreSuppressed = false
        }

        let hasPersistedMockSession =
            self.isUsingLocalMockSession
            || (self.sessionToken?.hasPrefix("local-mock") == true)
            || (self.currentUser?.userId.hasPrefix("mock-user-") == true)
        if hasPersistedMockSession && autoMockLogin == nil {
            self.sessionToken = nil
            self.currentUser = nil
            self.isUsingLocalMockSession = false
        }

        if let autoMockLogin {
            switch autoMockLogin {
            case "phone":
                activateLocalMockPhoneSession()
            case "wechat":
                activateLocalMockWeChatSession()
            default:
                break
            }
        }

        refreshBiometryAvailability()
        syncDeviceAccountLabel()
        persistCurrentScopedSession()
        syncLongbridgeTokenState()
        if biometricUnlockEnabled && isAuthenticated {
            requiresBiometricUnlock = true
        }

        #if DEBUG
        debugPrintStartupState()
        #endif
    }

    static var currentDeviceLabel: String {
        let label = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "MyInvAI iPhone" : label
    }

    var trimmedServerURLString: String {
        serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentServerPort: Int {
        URL(string: trimmedServerURLString)?.port ?? 8008
    }

    var cacheNamespace: String {
        let serverPart = Self.cacheSafeIdentifier(for: normalizedCurrentServerURL ?? trimmedServerURLString)
        let userPart = Self.cacheSafeIdentifier(for: effectiveDataIdentity)
        return serverPart + "." + userPart
    }

    var suggestedBuildServerURLString: String? {
        bundledDefaultServerURLString
    }

    var effectiveCurrentUser: MobileUser? {
        currentUser ?? persistedCurrentUser
    }

    var isAuthenticated: Bool {
        effectiveCurrentUser != nil && !(effectiveSessionToken ?? "").isEmpty
    }

    var isLocalOnlySession: Bool {
        guard let currentUser = effectiveCurrentUser else {
            return false
        }
        return currentUser.authProvider == "apple-local"
            || currentUser.authProvider == "device-local"
            || (sessionToken?.hasPrefix("local-apple-") == true)
            || (sessionToken?.hasPrefix("local-device-") == true)
    }

    var canAccessRemoteData: Bool {
        isAuthenticated && !isLocalOnlySession
    }

    var canAttemptAutomaticDeviceLogin: Bool {
        !automaticDeviceRestoreSuppressed
    }

    var supportsBiometricUnlock: Bool {
        biometryType != .none
    }

    var hasProvisionedDeviceAccount: Bool {
        (deviceAccountProfile.assignedUserID?.isEmpty == false)
            || (deviceAccountProfile.defaultPassword?.isEmpty == false)
    }

    var aiPrimaryProvider: AppAIProvider {
        aiSettingsProfile.primaryProvider
    }

    var aiFallbacksEnabled: Bool {
        aiSettingsProfile.enableFallbacks
    }

    func aiModelIdentifier(for provider: AppAIProvider) -> String {
        aiSettingsProfile.profile(for: provider).modelIdentifier
    }

    func aiAPIKey(for provider: AppAIProvider) -> String {
        aiCredentialStore.loadAPIKey(for: provider) ?? ""
    }

    func hasAIAPIKey(for provider: AppAIProvider) -> Bool {
        aiCredentialStore.loadAPIKey(for: provider) != nil
    }

    func setAIPrimaryProvider(_ provider: AppAIProvider) {
        aiSettingsProfile.primaryProvider = provider
    }

    func setAIFallbacksEnabled(_ isEnabled: Bool) {
        aiSettingsProfile.enableFallbacks = isEnabled
    }

    func setAIModelIdentifier(_ value: String, for provider: AppAIProvider) {
        aiSettingsProfile = aiSettingsProfile.updatingModel(value, for: provider)
    }

    func setAIAPIKey(_ value: String, for provider: AppAIProvider) {
        aiCredentialStore.persistAPIKey(value, for: provider)
        objectWillChange.send()
    }

    func aiFallbackProviderSummary() -> String {
        let configuredProviders = AppAIProvider.allCases.filter { provider in
            provider != aiSettingsProfile.primaryProvider && hasAIAPIKey(for: provider)
        }
        return configuredProviders.map(\.displayName).joined(separator: " -> ")
    }

    var isLongbridgeAuthorized: Bool {
        longbridgeSessionState == .authorized
    }

    var canUseLongbridgeSession: Bool {
        longbridgeSessionState == .authorized || longbridgeSessionState == .tokenExpired
    }

    var longbridgeEndpointLabel: String {
        guard let longbridgeEndpointBaseURL, let url = URL(string: longbridgeEndpointBaseURL), let host = url.host else {
            return "中国大陆优先"
        }
        if host.contains("longportapp.cn") {
            return "中国大陆"
        }
        if host.contains("longportapp.com") || host.contains("longbridge.com") {
            return "全球"
        }
        return host
    }

    var supportsStandaloneAIEntry: Bool {
        standaloneAIEntryEnabled || canUseLongbridgeSession
    }

    var shouldPreferAITabOnLaunch: Bool {
        !isAuthenticated && supportsStandaloneAIEntry
    }

    var longbridgeRedirectURI: String {
        Self.longbridgeRedirectURI
    }

    func beginLongbridgeAuthorization() async -> URL? {
        longbridgeSessionState = .authorizing
        longbridgeAuthErrorMessage = nil

        do {
            let candidates = longbridgeAuthService.authorizationCandidates()
            var selectedEndpoint: LongbridgeEndpoint?
            var clientID: String?

            for endpoint in candidates {
                do {
                    let registeredClientID: String
                    if let existing = longbridgeClientID, !existing.isEmpty, longbridgeEndpointBaseURL == endpoint.apiBaseURL.absoluteString {
                        registeredClientID = existing
                    } else {
                        registeredClientID = try await longbridgeAuthService.registerClient(
                            redirectURI: Self.longbridgeRedirectURI,
                            clientName: "MyInvAI iOS",
                            baseURL: endpoint.apiBaseURL
                        )
                    }
                    selectedEndpoint = endpoint
                    clientID = registeredClientID
                    break
                } catch {
                    continue
                }
            }

            guard let selectedEndpoint, let clientID else {
                throw LongbridgeAuthError.service("Longbridge 当前区域暂不可用，请稍后再试。")
            }

            let endpointAwarePKCE = longbridgeAuthService.buildPKCEContext(endpointBaseURL: selectedEndpoint.apiBaseURL)
            pendingLongbridgePKCEContext = endpointAwarePKCE
            persistLongbridgePKCEContext(endpointAwarePKCE)
            longbridgeClientID = clientID
            longbridgeEndpointBaseURL = selectedEndpoint.apiBaseURL.absoluteString
            return try longbridgeAuthService.authorizationURL(
                baseURL: selectedEndpoint.apiBaseURL,
                clientID: clientID,
                redirectURI: Self.longbridgeRedirectURI,
                pkce: endpointAwarePKCE
            )
        } catch {
            longbridgeSessionState = .error
            longbridgeAuthErrorMessage = error.localizedDescription
            return nil
        }
    }

    func handleLongbridgeOAuthCallback(url: URL) async {
        guard isLongbridgeOAuthCallback(url) else {
            return
        }
        longbridgeSessionState = .authorizing

        do {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw LongbridgeAuthError.invalidCallback
            }
            let queryItems = components.queryItems ?? []
            if let oauthError = queryItems.first(where: { $0.name == "error" })?.value {
                throw LongbridgeAuthError.service("Longbridge 授权失败：\(oauthError)")
            }
            guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                throw LongbridgeAuthError.missingAuthorizationCode
            }
            guard let state = queryItems.first(where: { $0.name == "state" })?.value, !state.isEmpty else {
                throw LongbridgeAuthError.stateMismatch
            }
            guard let pkce = pendingLongbridgePKCEContext, pkce.state == state else {
                throw LongbridgeAuthError.stateMismatch
            }
            guard let clientID = longbridgeClientID, !clientID.isEmpty else {
                throw LongbridgeAuthError.invalidResponse
            }
            guard let endpointBaseURL = URL(string: pkce.endpointBaseURL) else {
                throw LongbridgeAuthError.invalidResponse
            }
            let token = try await longbridgeAuthService.exchangeCode(
                baseURL: endpointBaseURL,
                clientID: clientID,
                code: code,
                redirectURI: Self.longbridgeRedirectURI,
                codeVerifier: pkce.codeVerifier
            )
            pendingLongbridgePKCEContext = nil
            persistLongbridgePKCEContext(nil)
            longbridgeTokenExpiresAt = token.expiresAt
            longbridgeEndpointBaseURL = token.endpointBaseURL
            longbridgeSessionState = .authorized
            longbridgeAuthErrorMessage = nil
        } catch {
            longbridgeSessionState = .error
            longbridgeAuthErrorMessage = error.localizedDescription
        }
    }

    func clearLongbridgeAuthorization() {
        longbridgeAuthService.clearStoredToken()
        pendingLongbridgePKCEContext = nil
        persistLongbridgePKCEContext(nil)
        longbridgeTokenExpiresAt = nil
        longbridgeEndpointBaseURL = nil
        longbridgeSessionState = .unauthorized
        longbridgeAuthErrorMessage = nil
    }

    func enableStandaloneAIEntry() {
        standaloneAIEntryEnabled = true
        connectionStatusMessage = "已进入 AI 独立模式。"
    }

    func disableStandaloneAIEntry() {
        standaloneAIEntryEnabled = false
    }

    func loginWithAppleAccount(
        userIdentifier: String,
        displayName: String?,
        emailAddress: String?
    ) async throws -> MobileSessionPayload {
        let normalizedIdentifier = userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            throw PortfolioWorkbenchAPIClientError.transport("Apple 登录缺少有效身份标识。")
        }

        connectionStatusMessage = "正在连接 Apple 账户…"
        do {
            let client = try makeNetworkClient(allowLocalOnly: false)
            let payload = try await client.loginWithApple(
                userIdentifier: normalizedIdentifier,
                displayName: displayName,
                emailAddress: emailAddress
            )
            updateAuthenticatedSession(payload)
            connectionStatusMessage = "Apple 登录已连接到服务器。"
            return payload
        } catch {
            activateLocalAppleSession(
                userIdentifier: normalizedIdentifier,
                displayName: displayName,
                emailAddress: emailAddress
            )
            connectionStatusMessage = "已进入本机 Apple 身份，服务器可用时会自动同步。"
            return MobileSessionPayload(
                sessionToken: sessionToken,
                user: currentUser ?? MobileUser(
                    userId: "apple-\(normalizedIdentifier)",
                    displayName:
                        displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? displayName!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : "Apple 用户",
                    phoneNumberMasked: nil,
                    authProvider: "apple-local",
                    isOwner: true
                ),
                message: "已进入本机 Apple 身份登录。"
            )
        }
    }

    func makeLongbridgeAPIClient() async throws -> LongbridgeAPIClient {
        let token = try await ensureLongbridgeAccessToken()
        let tokenBaseURL = URL(string: token.endpointBaseURL ?? "")
        let preferredEndpoint = LongbridgeEndpoint.preferredEndpoint(for: tokenBaseURL)
        LongbridgeDiagnosticsStore.shared.append(
            "创建 Longbridge API client: endpoint=\(preferredEndpoint.displayName), api=\(preferredEndpoint.apiBaseURL.host ?? preferredEndpoint.apiBaseURL.absoluteString), quote=\(preferredEndpoint.quoteBaseURL.host ?? preferredEndpoint.quoteBaseURL.absoluteString)"
        )
        return LongbridgeAPIClient(
            configuration: LongbridgeAPIConfiguration(
                apiBaseURL: preferredEndpoint.apiBaseURL,
                quoteBaseURL: preferredEndpoint.quoteBaseURL,
                tradeBaseURL: preferredEndpoint.tradeBaseURL,
                fallbackEndpoints: LongbridgeEndpoint.candidates(preferring: tokenBaseURL ?? LongbridgeEndpoint.mainlandChina.apiBaseURL),
                accessToken: token.accessToken
            ),
            diagnosticHandler: { message in
                LongbridgeDiagnosticsStore.shared.append(message)
            }
        )
    }

    func makeLongbridgeQuoteMarkdownClient() -> LongbridgeQuoteMarkdownClient {
        LongbridgeQuoteMarkdownClient(localePrefix: "zh-CN")
    }

    func fallbackClientForAIMode() async -> PortfolioWorkbenchAPIClient? {
        guard canAccessRemoteData else {
            return nil
        }
        return try? makeClient()
    }

    func ensureLongbridgeAccessToken() async throws -> LongbridgeOAuthTokenPayload {
        guard var stored = longbridgeAuthService.loadStoredToken() else {
            longbridgeSessionState = .unauthorized
            LongbridgeDiagnosticsStore.shared.append("Longbridge 授权缺失，当前无法发起拉数。")
            throw LongbridgeAuthError.service("Longbridge 尚未授权。")
        }

        longbridgeEndpointBaseURL = stored.endpointBaseURL
        if !stored.isExpired {
            longbridgeSessionState = .authorized
            longbridgeTokenExpiresAt = stored.expiresAt
            LongbridgeDiagnosticsStore.shared.append(
                "Longbridge access token 有效，endpoint=\(stored.endpointBaseURL ?? "unknown")"
            )
            return stored
        }

        if let lastFailure = lastLongbridgeRefreshFailureAt,
           Date().timeIntervalSince(lastFailure) < Self.longbridgeRefreshCooldownSeconds {
            let remaining = Int(Self.longbridgeRefreshCooldownSeconds - Date().timeIntervalSince(lastFailure))
            LongbridgeDiagnosticsStore.shared.append(
                "Longbridge refresh cooldown 中（\(remaining)s），跳过本次刷新。"
            )
            throw LongbridgeAuthError.service("Longbridge token 刷新冷却中，\(remaining)s 后重试。")
        }

        do {
            LongbridgeDiagnosticsStore.shared.append("Longbridge access token 即将过期，开始刷新。")
            stored = try await longbridgeAuthService.refreshToken(stored)
            longbridgeSessionState = .authorized
            longbridgeTokenExpiresAt = stored.expiresAt
            longbridgeEndpointBaseURL = stored.endpointBaseURL
            longbridgeAuthErrorMessage = nil
            lastLongbridgeRefreshFailureAt = nil
            LongbridgeDiagnosticsStore.shared.append(
                "Longbridge access token 刷新成功，endpoint=\(stored.endpointBaseURL ?? "unknown")"
            )
            return stored
        } catch {
            lastLongbridgeRefreshFailureAt = Date()
            longbridgeSessionState = .tokenExpired
            longbridgeAuthErrorMessage = error.localizedDescription
            LongbridgeDiagnosticsStore.shared.append("Longbridge access token 刷新失败: \(error.localizedDescription)")
            throw error
        }
    }

    private var effectiveDataIdentity: String {
        if isLocalOnlySession {
            return deviceAccountProfile.installationID
        }
        let resolved =
            effectiveCurrentUser?.userId
            ?? deviceAccountProfile.assignedUserID
            ?? deviceAccountProfile.installationID
        return resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "anonymous" : resolved
    }

    private var persistedCurrentUser: MobileUser? {
        guard let data = UserDefaults.standard.data(forKey: Self.currentUserKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MobileUser.self, from: data)
    }

    func refreshBiometryAvailability() {
        let context = LAContext()
        var error: NSError?
        let canUseBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometryType = canUseBiometrics ? DeviceBiometryType(context.biometryType) : .none
        if !canUseBiometrics {
            biometricUnlockEnabled = false
            requiresBiometricUnlock = false
        }
    }

    func toggleSensitiveAmounts() {
        hideSensitiveAmounts.toggle()
    }

    func selectServerURL(_ rawValue: String, name: String? = nil, rememberSelection: Bool = false) {
        let normalized = Self.normalizeServerURLString(rawValue) ?? rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        serverURLString = normalized
        guard rememberSelection, let persistedURL = Self.normalizeServerURLString(normalized) else {
            return
        }
        upsertSavedServer(name: name ?? inferredServerName(from: persistedURL), url: persistedURL)
    }

    func saveCurrentServer(named name: String? = nil) {
        guard let normalized = Self.normalizeServerURLString(trimmedServerURLString) else {
            return
        }
        upsertSavedServer(name: name ?? inferredServerName(from: normalized), url: normalized)
    }

    func removeSavedServer(_ server: SavedServerEndpoint) {
        savedServers.removeAll { $0.id == server.id }
    }

    func updateAuthenticatedSession(_ payload: MobileSessionPayload) {
        sessionToken = payload.sessionToken
        currentUser = payload.user
        isUsingLocalMockSession = false
        standaloneAIEntryEnabled = false
        mergeDeviceAccount(payload)
        requiresBiometricUnlock = false
        lastSessionValidationAt = .now
        lastValidatedServerURLString = trimmedServerURLString
        automaticRestoreAttemptServerURLString = nil
        automaticDeviceRestoreSuppressed = false
        connectionStatusMessage = "已连接 \(displayServerName(from: trimmedServerURLString))"
    }

    func activateLocalMockPhoneSession(phoneNumber: String = PortfolioWorkbenchLocalMock.mockPhoneNumber) {
        let payload = PortfolioWorkbenchLocalMock.makePhoneSession(phoneNumber: phoneNumber)
        sessionToken = payload.sessionToken
        currentUser = payload.user
        isUsingLocalMockSession = true
        requiresBiometricUnlock = false
        lastSessionValidationAt = .now
        lastValidatedServerURLString = trimmedServerURLString
        automaticRestoreAttemptServerURLString = nil
        automaticDeviceRestoreSuppressed = false
        connectionStatusMessage = nil
    }

    func activateLocalMockWeChatSession(displayName: String? = nil) {
        let payload = PortfolioWorkbenchLocalMock.makeWeChatSession(displayName: displayName)
        sessionToken = payload.sessionToken
        currentUser = payload.user
        isUsingLocalMockSession = true
        requiresBiometricUnlock = false
        lastSessionValidationAt = .now
        lastValidatedServerURLString = trimmedServerURLString
        automaticRestoreAttemptServerURLString = nil
        automaticDeviceRestoreSuppressed = false
        connectionStatusMessage = nil
    }

    func updateCurrentUser(_ user: MobileUser) {
        currentUser = user
        if user.authProvider == "device" {
            var next = deviceAccountProfile
            next.assignedUserID = user.userId
            deviceAccountProfile = next
        }
    }

    func clearAuthentication() {
        sessionToken = nil
        currentUser = nil
        isUsingLocalMockSession = false
        requiresBiometricUnlock = false
        lastSessionValidationAt = nil
        lastValidatedServerURLString = nil
        connectionStatusMessage = nil
        scopedSessions.removeValue(forKey: Self.localScopedSessionKey)
        if let data = try? JSONEncoder().encode(scopedSessions) {
            UserDefaults.standard.set(data, forKey: Self.scopedSessionsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.scopedSessionsKey)
        }
    }

    func logoutCurrentSession() {
        automaticDeviceRestoreSuppressed = true
        disableStandaloneAIEntry()
        clearAuthentication()
    }

    func restoreDeviceSessionIfPossible() async {
        guard !canAccessRemoteData, !isUsingLocalMockSession, !isRestoringDeviceSession else {
            return
        }
        guard hasProvisionedDeviceAccount, !automaticDeviceRestoreSuppressed else {
            return
        }

        let currentURL = trimmedServerURLString
        guard automaticRestoreAttemptServerURLString != currentURL else {
            return
        }

        automaticRestoreAttemptServerURLString = currentURL
        isRestoringDeviceSession = true
        defer { isRestoringDeviceSession = false }
        connectionStatusMessage = "正在连接服务器…"

        do {
            let payload = try await bootstrapDeviceSessionWithAutoFailover()
            updateAuthenticatedSession(payload)
        } catch {
            activateLocalDeviceSession()
            connectionStatusMessage = "服务器暂时不可用，已进入本机设备身份。"
        }
    }

    func ensureLaunchSessionIfPossible() async {
        guard !canAccessRemoteData, !isUsingLocalMockSession else {
            return
        }

        await restoreDeviceSessionIfPossible()
        guard !canAccessRemoteData else {
            return
        }

        do {
            _ = try await loginWithDeviceAccount(requireLocalAuthentication: false)
        } catch {
            // Keep startup resilient. The login method already falls back to a local-only
            // session when the server is unreachable, so there is nothing else to do here.
        }
    }

    func loginWithDeviceAccount(requireLocalAuthentication: Bool = false) async throws -> MobileSessionPayload {
        refreshBiometryAvailability()
        if requireLocalAuthentication {
            try await authenticateLocalUser(reason: "使用 \(biometryType.displayName) 登录你的投资账户")
        }
        connectionStatusMessage = "正在连接服务器…"

        do {
            let payload = try await bootstrapDeviceSessionWithAutoFailover()
            updateAuthenticatedSession(payload)
            if supportsBiometricUnlock {
                biometricUnlockEnabled = true
            }
            return payload
        } catch {
            activateLocalDeviceSession()
            connectionStatusMessage = "服务器暂时不可用，已进入本机设备身份。"
            return MobileSessionPayload(
                sessionToken: sessionToken,
                user: currentUser ?? MobileUser(
                    userId: "device-\(deviceAccountProfile.installationID)",
                    displayName: deviceAccountProfile.deviceLabel,
                    phoneNumberMasked: nil,
                    authProvider: "device",
                    isOwner: true
                ),
                message: "已进入本机设备身份。"
            )
        }
    }

    func enableBiometricUnlock() async throws {
        refreshBiometryAvailability()
        guard supportsBiometricUnlock else {
            throw AppSecurityError.biometricUnavailable("当前设备未开启 Face ID / Touch ID，暂时无法启用本机解锁。")
        }
        try await authenticateLocalUser(reason: "启用 \(biometryType.displayName) 以保护你的投资账户")
        biometricUnlockEnabled = true
        requiresBiometricUnlock = false
    }

    func disableBiometricUnlock() {
        biometricUnlockEnabled = false
        requiresBiometricUnlock = false
    }

    func lockIfNeeded() {
        guard biometricUnlockEnabled, isAuthenticated else {
            return
        }
        requiresBiometricUnlock = true
    }

    func unlockActiveSession() async throws {
        guard biometricUnlockEnabled else {
            requiresBiometricUnlock = false
            return
        }
        try await authenticateLocalUser(reason: "解锁你的投资账户与个人持仓数据")
        try await validateAuthenticatedSessionIfNeeded(force: true)
        requiresBiometricUnlock = false
    }

    func proceedIntoActiveSessionWithoutBiometric() async throws {
        try await validateAuthenticatedSessionIfNeeded(force: true)
        requiresBiometricUnlock = false
        connectionStatusMessage = "已连接 \(displayServerName(from: trimmedServerURLString))"
    }

    func makeClient() throws -> PortfolioWorkbenchAPIClient {
        hydrateAuthenticatedSessionIfNeeded()
        if isUsingLocalMockSession {
            return PortfolioWorkbenchLocalMock.makeClient(
                currentUser: effectiveCurrentUser,
                sessionToken: effectiveSessionToken
            )
        }
        return try makeNetworkClient()
    }

    func makeValidatedClient(forceSessionCheck: Bool = true) async throws -> PortfolioWorkbenchAPIClient {
        hydrateAuthenticatedSessionIfNeeded()
        if isLocalOnlySession {
            throw PortfolioWorkbenchAPIClientError.transport("当前为本机 Apple 身份，暂未连接服务器。")
        }
        do {
            let client = try makeClient()
            try await validateAuthenticatedSessionIfNeeded(using: client, force: forceSessionCheck)
            connectionStatusMessage = "已连接 \(displayServerName(from: trimmedServerURLString))"
            return client
        } catch {
            guard shouldAttemptServerFailover(for: error) else {
                connectionStatusMessage = userFriendlyConnectionMessage(for: error)
                throw error
            }
            connectionStatusMessage = "当前连接异常，正在自动恢复服务器连接…"
            guard await recoverServerConnectionIfNeeded() else {
                throw error
            }
            let retriedClient = try makeClient()
            try await validateAuthenticatedSessionIfNeeded(using: retriedClient, force: true)
            connectionStatusMessage = "已自动切换到 \(displayServerName(from: trimmedServerURLString))"
            return try makeClient()
        }
    }

    func makeNetworkClient(allowLocalOnly: Bool = true) throws -> PortfolioWorkbenchAPIClient {
        hydrateAuthenticatedSessionIfNeeded()
        guard let url = URL(string: trimmedServerURLString), url.scheme?.hasPrefix("http") == true else {
            throw PortfolioWorkbenchAPIClientError.transport("请填写可访问的服务地址，例如 \(Self.defaultServerURLString)")
        }

        if isLocalOnlySession && !allowLocalOnly {
            throw PortfolioWorkbenchAPIClientError.transport("当前为本机 Apple 身份，服务器登录已切换为本地模式。")
        }

        #if DEBUG
        NSLog("[AppSettingsStore] makeNetworkClient url=%@ auth=%@ user=%@ tokenLen=%d localOnly=%@",
              url.absoluteString,
              String(isAuthenticated),
              effectiveCurrentUser.map { "\($0.authProvider):\($0.userId)" } ?? "nil",
              effectiveSessionToken?.count ?? 0,
              String(isLocalOnlySession))
        #endif

        return PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(
                baseURL: url,
                sessionToken: effectiveSessionToken,
                aiRequestConfiguration: currentAIRequestConfiguration()
            )
        )
    }

    func validateAuthenticatedSessionIfNeeded(
        using client: PortfolioWorkbenchAPIClient? = nil,
        force: Bool = false
    ) async throws {
        hydrateAuthenticatedSessionIfNeeded()
        guard isAuthenticated, !isUsingLocalMockSession, !isLocalOnlySession else {
            return
        }
        let currentURL = trimmedServerURLString
        if !force,
           let lastSessionValidationAt,
           lastValidatedServerURLString == currentURL,
           Date().timeIntervalSince(lastSessionValidationAt) < Self.sessionValidationInterval {
            return
        }

        let networkClient = try (client ?? makeNetworkClient())
        do {
            let session = try await networkClient.fetchCurrentSession()
            updateCurrentUser(session.user)
            lastSessionValidationAt = .now
            lastValidatedServerURLString = currentURL
        } catch let error as PortfolioWorkbenchAPIClientError {
            if case let .server(statusCode, _) = error, statusCode == 401 {
                if await renewDeviceSessionIfPossible(using: networkClient) {
                    return
                }
                clearAuthentication()
            }
            throw error
        } catch {
            throw error
        }
    }

    private func renewDeviceSessionIfPossible(using client: PortfolioWorkbenchAPIClient? = nil) async -> Bool {
        guard hasProvisionedDeviceAccount || effectiveCurrentUser?.authProvider == "device" else {
            return false
        }

        do {
            let networkClient = try (client ?? makeNetworkClient())
            let payload = try await networkClient.bootstrapDeviceAccount(
                deviceID: deviceAccountProfile.installationID,
                deviceName: Self.currentDeviceLabel
            )
            updateAuthenticatedSession(payload)
            if supportsBiometricUnlock {
                biometricUnlockEnabled = true
            }
            return true
        } catch {
            return false
        }
    }

    private func bootstrapDeviceSessionWithAutoFailover() async throws -> MobileSessionPayload {
        do {
            let client = try makeNetworkClient()
            return try await client.bootstrapDeviceAccount(
                deviceID: deviceAccountProfile.installationID,
                deviceName: Self.currentDeviceLabel
            )
        } catch {
            guard shouldAttemptServerFailover(for: error) else {
                connectionStatusMessage = userFriendlyConnectionMessage(for: error)
                throw error
            }
            connectionStatusMessage = "当前网络连接异常，正在自动恢复服务器连接…"
            guard await recoverServerConnectionIfNeeded() else {
                throw error
            }
            let retriedClient = try makeNetworkClient()
            connectionStatusMessage = "已自动切换到 \(displayServerName(from: trimmedServerURLString))，正在继续登录…"
            return try await retriedClient.bootstrapDeviceAccount(
                deviceID: deviceAccountProfile.installationID,
                deviceName: Self.currentDeviceLabel
            )
        }
    }

    private func shouldAttemptServerFailover(for error: Error) -> Bool {
        if let apiError = error as? PortfolioWorkbenchAPIClientError {
            switch apiError {
            case .transport:
                return true
            case let .server(statusCode, _):
                return statusCode >= 500 || statusCode == 404
            case .invalidResponse:
                return true
            }
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("timed out")
            || message.contains("could not connect")
            || message.contains("offline")
            || message.contains("network")
            || message.contains("transport")
    }

    @discardableResult
    private func autoSwitchToReachableServer(excludingCurrent: Bool) async -> Bool {
        let current = normalizedCurrentServerURL
        let candidates = candidateServerURLs(
            includeCurrent: !excludingCurrent,
            current: current
        )
        guard !candidates.isEmpty else {
            connectionStatusMessage = "暂无可探测服务器地址，请检查网络后重试。"
            return false
        }

        connectionStatusMessage = "正在自动探测可用服务器…"
        for candidate in candidates.prefix(6) {
            connectionStatusMessage = "正在探测 \(displayServerName(from: candidate))…"
            let reachable = await isServerReachable(candidate)
            guard reachable else { continue }
            if candidate != current {
                selectServerURL(candidate, name: inferredServerName(from: candidate), rememberSelection: true)
                connectionStatusMessage = "已自动切换到 \(displayServerName(from: candidate))"
            } else {
                connectionStatusMessage = "已连接 \(displayServerName(from: candidate))"
            }
            return true
        }
        connectionStatusMessage = "暂未发现可用服务器，请检查网络后重试。"
        return false
    }

    func recoverServerConnectionIfNeeded() async -> Bool {
        if await autoSwitchToReachableServer(excludingCurrent: true) {
            return true
        }
        if await autoDiscoverAndSwitchToReachableServer() {
            return true
        }
        connectionStatusMessage = "未找到可连接的服务器，请点击“配置服务器”手动设置。"
        return false
    }

    private func autoDiscoverAndSwitchToReachableServer() async -> Bool {
        let localAddresses = localIPv4Addresses()
        guard !localAddresses.isEmpty else {
            connectionStatusMessage = "当前未获取到局域网地址，无法自动探测服务器。"
            return false
        }

        let seededHosts = [
            normalizedCurrentServerURL.flatMap { URL(string: $0)?.host },
            bundledDefaultServerURLString.flatMap { URL(string: $0)?.host },
        ].compactMap { $0 }
        let subnets = NetworkDiscoveryHints.candidateSubnetPrefixes(
            localAddresses: localAddresses,
            seededHosts: seededHosts
        )
        guard !subnets.isEmpty else {
            connectionStatusMessage = "局域网地址格式异常，无法自动探测服务器。"
            return false
        }

        let ports = discoveryPorts()
        connectionStatusMessage = "正在自动扫描局域网服务器…"

        var discoveredURL: String?
        await withTaskGroup(of: String?.self) { group in
            for subnet in subnets {
                for hostIndex in Self.discoveryHostCandidates(for: subnet, localAddresses: localAddresses) {
                    let candidateIP = "\(subnet).\(hostIndex)"
                    if localAddresses.contains(candidateIP) {
                        continue
                    }
                    for port in ports {
                        group.addTask {
                            await self.probeDiscoveryServer(ip: candidateIP, port: port)
                        }
                    }
                }
            }

            for await result in group {
                guard let result else { continue }
                discoveredURL = result
                group.cancelAll()
                break
            }
        }

        guard let discoveredURL else {
            connectionStatusMessage = "自动探测完成，未发现可连接的局域网服务器。"
            return false
        }

        if discoveredURL != normalizedCurrentServerURL {
            selectServerURL(discoveredURL, name: inferredServerName(from: discoveredURL), rememberSelection: true)
            connectionStatusMessage = "已自动切换到 \(displayServerName(from: discoveredURL))"
        } else {
            connectionStatusMessage = "已连接 \(displayServerName(from: discoveredURL))"
        }
        return true
    }

    private func discoveryPorts() -> [Int] {
        let currentPort = currentServerPort
        if currentPort == 8008 {
            return [8008]
        }
        return [currentPort, 8008]
    }

    private static func discoveryHostCandidates(for subnet: String, localAddresses: [String]) -> [Int] {
        if localAddresses.contains(where: { $0.hasPrefix("\(subnet).") }) {
            return Array(1...254)
        }
        let fallbackSubnets: Set<String> = [
            "10.0.0",
            "10.8.144",
            "10.10.10",
            "172.16.0",
            "172.20.10",
            "192.168.0",
            "192.168.1",
            "192.168.31",
        ]
        if fallbackSubnets.contains(subnet) {
            return [1, 2, 10, 20, 31, 50, 100, 128, 168, 193, 200, 254]
        }
        return Array(1...254)
    }

    private func probeDiscoveryServer(ip: String, port: Int) async -> String? {
        guard let url = URL(string: "http://\(ip):\(port)/api/mobile/discovery") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 0.6
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(MobileServerDiscoveryPayload.self, from: data)
            guard payload.service == "portfolio-workbench" else {
                return nil
            }

            let discoveredBaseURL = payload.suggestedBaseUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let discoveredBaseURL, !discoveredBaseURL.isEmpty {
                return discoveredBaseURL
            }
            return "http://\(ip):\(port)/"
        } catch {
            return nil
        }
    }

    private func localIPv4Addresses() -> [String] {
        var addresses: Set<String> = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let interfaceAddress = interface.ifa_addr else { continue }
            guard interfaceAddress.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interfaceAddress,
                socklen_t(interfaceAddress.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            let candidate = String(cString: hostname)
            if !candidate.isEmpty, !candidate.hasPrefix("169.254."), !candidate.hasPrefix("127.") {
                addresses.insert(candidate)
            }
        }

        return Array(addresses)
    }

    private func candidateServerURLs(includeCurrent: Bool, current: String?) -> [String] {
        var raw: [String] = []
        if includeCurrent, let current {
            raw.append(current)
        }
        raw.append(Self.defaultServerURLString)
        raw.append(Self.remoteDefaultServerURLString)
        if let bundledDefaultServerURLString {
            raw.append(bundledDefaultServerURLString)
        }
        raw.append(contentsOf: savedServers.map(\.url))

        var seen = Set<String>()
        var normalized: [String] = []
        for item in raw {
            guard let value = Self.normalizeServerURLString(item), !seen.contains(value) else {
                continue
            }
            seen.insert(value)
            normalized.append(value)
        }
        return normalized
    }

    private func isServerReachable(_ baseURLString: String) async -> Bool {
        guard let baseURL = URL(string: baseURLString) else {
            return false
        }
        let discoveryURL = baseURL.appending(path: "api/mobile/discovery")
        var request = URLRequest(url: discoveryURL)
        request.timeoutInterval = 1.2
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.2
        configuration.timeoutIntervalForResource = 1.8
        let session = URLSession(configuration: configuration)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return false
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(MobileServerDiscoveryPayload.self, from: data)
            return payload.service == "portfolio-workbench"
        } catch {
            return false
        }
    }

    private func syncDeviceAccountLabel() {
        let currentLabel = Self.currentDeviceLabel
        guard deviceAccountProfile.deviceLabel != currentLabel else {
            return
        }
        var next = deviceAccountProfile
        next.deviceLabel = currentLabel
        deviceAccountProfile = next
    }

    private func mergeDeviceAccount(_ payload: MobileSessionPayload) {
        guard payload.user.authProvider == "device" || payload.deviceCredentials != nil else {
            return
        }

        var next = deviceAccountProfile
        next.assignedUserID = payload.deviceCredentials?.assignedUserId ?? payload.user.userId
        next.deviceLabel = payload.deviceCredentials?.deviceName ?? Self.currentDeviceLabel
        if let defaultPassword = payload.deviceCredentials?.defaultPassword,
           !defaultPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.defaultPassword = defaultPassword
        }
        next.lastProvisionedAt = .now
        deviceAccountProfile = next
    }

    private func activateLocalAppleSession(
        userIdentifier: String,
        displayName: String?,
        emailAddress: String?
    ) {
        let normalizedIdentifier = userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName =
            displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? displayName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Apple 用户"
        let user = MobileUser(
            userId: "apple-\(normalizedIdentifier)",
            displayName: resolvedName,
            phoneNumberMasked: emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            authProvider: "apple-local",
            isOwner: true
        )
        sessionToken = "local-apple-\(normalizedIdentifier)"
        currentUser = user
        isUsingLocalMockSession = false
        standaloneAIEntryEnabled = false
        requiresBiometricUnlock = false
        lastSessionValidationAt = .now
        lastValidatedServerURLString = trimmedServerURLString
        automaticRestoreAttemptServerURLString = nil
        automaticDeviceRestoreSuppressed = false
        connectionStatusMessage = nil
    }

    func activateLocalAppleSessionFallback(displayName: String? = nil) {
        let resolvedName =
            displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? displayName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Apple 用户"
        activateLocalAppleSession(
            userIdentifier: deviceAccountProfile.installationID,
            displayName: resolvedName,
            emailAddress: nil
        )
        connectionStatusMessage = "已进入本机 Apple 身份，服务器可用时会自动同步。"
    }

    func activateLocalDeviceSession() {
        let user = MobileUser(
            userId: deviceAccountProfile.assignedUserID ?? "device-\(deviceAccountProfile.installationID)",
            displayName: deviceAccountProfile.deviceLabel,
            phoneNumberMasked: nil,
            authProvider: "device",
            isOwner: true
        )
        var nextProfile = deviceAccountProfile
        nextProfile.assignedUserID = user.userId
        nextProfile.deviceLabel = deviceAccountProfile.deviceLabel
        deviceAccountProfile = nextProfile
        sessionToken = "local-device-\(deviceAccountProfile.installationID)"
        currentUser = user
        isUsingLocalMockSession = false
        standaloneAIEntryEnabled = false
        requiresBiometricUnlock = false
        lastSessionValidationAt = .now
        lastValidatedServerURLString = trimmedServerURLString
        automaticRestoreAttemptServerURLString = nil
        automaticDeviceRestoreSuppressed = false
        connectionStatusMessage = nil
    }

    private func currentAIRequestConfiguration() -> AIRequestConfiguration? {
        let providers = AppAIProvider.allCases.map { provider in
            return AIProviderRequestConfiguration(
                provider: provider.kind,
                model: aiModelIdentifier(for: provider)
            )
        }

        return AIRequestConfiguration(
            primaryProvider: aiSettingsProfile.primaryProvider.kind,
            enableFallbacks: aiSettingsProfile.enableFallbacks,
            providers: providers
        )
    }

    private static func migrateLegacyDefaultAIProfileIfNeeded(
        _ profile: AppAISettingsProfile,
        credentialStore: AIProviderCredentialStore
    ) -> AppAISettingsProfile {
        let matchesLegacyDefaults =
            profile.primaryProvider == .kimi
            && profile.enableFallbacks
            && AppAIProvider.allCases.allSatisfy { provider in
                profile.profile(for: provider).modelIdentifier == provider.defaultModelIdentifier
            }

        let hasAnyStoredKey = AppAIProvider.allCases.contains { provider in
            credentialStore.loadAPIKey(for: provider) != nil
        }

        guard matchesLegacyDefaults, !hasAnyStoredKey else {
            return profile
        }

        var migrated = profile
        migrated.primaryProvider = .anthropic
        return migrated
    }

    private func authenticateLocalUser(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "稍后"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw AppSecurityError.biometricUnavailable(
                error?.localizedDescription ?? "当前设备未检测到可用的本机生物识别能力。"
            )
        }
        let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        guard success else {
            throw AppSecurityError.biometricAuthenticationFailed
        }
    }

    private func upsertSavedServer(name: String, url: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = SavedServerEndpoint(
            name: trimmedName.isEmpty ? inferredServerName(from: url) : trimmedName,
            url: url
        )
        savedServers.removeAll { $0.id == endpoint.id }
        savedServers.insert(endpoint, at: 0)
        if savedServers.count > 8 {
            savedServers = Array(savedServers.prefix(8))
        }
    }

    private func inferredServerName(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            return "当前服务器"
        }
        return host
    }

    private var normalizedCurrentServerURL: String? {
        Self.normalizeServerURLString(trimmedServerURLString)
    }

    private func restoreScopedSessionForCurrentServer() {
        hydrateAuthenticatedSessionIfNeeded()
        guard let currentServerURL = normalizedCurrentServerURL else {
            sessionToken = nil
            currentUser = nil
            isUsingLocalMockSession = false
            requiresBiometricUnlock = false
            return
        }

        if isLocalOnlySession {
            persistCurrentScopedSession()
            return
        }

        guard let scopedSession = scopedSessions[currentServerURL] else {
            // Keep the current in-memory session if we do not yet have a server-scoped
            // copy for this URL. Clearing here would wipe a valid login whenever the
            // server selection changes before the first scoped session is stored.
            persistCurrentScopedSession()
            return
        }

        sessionToken = scopedSession.sessionToken
        currentUser = scopedSession.currentUser
        isUsingLocalMockSession = scopedSession.isUsingLocalMockSession
        if biometricUnlockEnabled {
            requiresBiometricUnlock = true
        }
    }

    private func hydrateAuthenticatedSessionIfNeeded() {
        guard currentUser == nil || (sessionToken ?? "").isEmpty else {
            return
        }

        let persistedToken = UserDefaults.standard.string(forKey: Self.sessionTokenKey)
        let persistedUser: MobileUser? = {
            guard let data = UserDefaults.standard.data(forKey: Self.currentUserKey) else {
                return nil
            }
            return try? JSONDecoder().decode(MobileUser.self, from: data)
        }()
        let persistedMockSession = UserDefaults.standard.bool(forKey: Self.localMockSessionKey)

        if let persistedToken, !persistedToken.isEmpty, let persistedUser {
            sessionToken = persistedToken
            currentUser = persistedUser
            isUsingLocalMockSession = persistedMockSession
            #if DEBUG
            NSLog("[AppSettingsStore] hydrated persisted session user=%@ tokenLen=%d localOnly=%@",
                  "\(persistedUser.authProvider):\(persistedUser.userId)",
                  persistedToken.count,
                  String(isLocalOnlySession))
            #endif
            return
        }

        guard currentUser == nil || (sessionToken ?? "").isEmpty else {
            return
        }

        if let currentServerURL = normalizedCurrentServerURL,
           let scopedSession = scopedSessions[currentServerURL] {
            sessionToken = scopedSession.sessionToken
            currentUser = scopedSession.currentUser
            isUsingLocalMockSession = scopedSession.isUsingLocalMockSession
            #if DEBUG
            NSLog("[AppSettingsStore] hydrated scoped session server=%@ user=%@ tokenLen=%d",
                  currentServerURL,
                  "\(scopedSession.currentUser.authProvider):\(scopedSession.currentUser.userId)",
                  scopedSession.sessionToken.count)
            #endif
        }
    }

    var effectiveSessionToken: String? {
        let runtimeToken = sessionToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        if runtimeToken?.isEmpty == false {
            return runtimeToken
        }
        let persistedToken = UserDefaults.standard.string(forKey: Self.sessionTokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if persistedToken?.isEmpty == false {
            return persistedToken
        }
        return nil
    }

    private func persistCurrentScopedSession() {
        let storageKey = isLocalOnlySession ? Self.localScopedSessionKey : normalizedCurrentServerURL
        guard let storageKey else {
            return
        }

        if let sessionToken, !sessionToken.isEmpty, let currentUser {
            scopedSessions[storageKey] = ScopedServerSession(
                sessionToken: sessionToken,
                currentUser: currentUser,
                isUsingLocalMockSession: isUsingLocalMockSession
            )
        } else {
            scopedSessions.removeValue(forKey: storageKey)
        }

        if let data = try? JSONEncoder().encode(scopedSessions) {
            UserDefaults.standard.set(data, forKey: Self.scopedSessionsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.scopedSessionsKey)
        }
    }

    private func syncLongbridgeTokenState() {
        guard let token = longbridgeAuthService.loadStoredToken() else {
            longbridgeTokenExpiresAt = nil
            longbridgeEndpointBaseURL = nil
            if longbridgeSessionState != .authorizing {
                longbridgeSessionState = .unauthorized
            }
            return
        }
        longbridgeClientID = token.clientID
        longbridgeTokenExpiresAt = token.expiresAt
        longbridgeEndpointBaseURL = token.endpointBaseURL
        if token.isExpired {
            if longbridgeSessionState != .authorizing {
                longbridgeSessionState = .tokenExpired
            }
        } else if longbridgeSessionState != .authorizing {
            longbridgeSessionState = .authorized
        }
    }

    private func persistLongbridgePKCEContext(_ context: LongbridgePKCEContext?) {
        if let context, let data = try? JSONEncoder().encode(context) {
            UserDefaults.standard.set(data, forKey: Self.longbridgePKCEContextKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.longbridgePKCEContextKey)
        }
    }

    private func isLongbridgeOAuthCallback(_ url: URL) -> Bool {
        guard let redirect = URL(string: Self.longbridgeRedirectURI),
              let redirectComponents = URLComponents(url: redirect, resolvingAgainstBaseURL: false),
              let incomingComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return incomingComponents.scheme?.lowercased() == redirectComponents.scheme?.lowercased()
            && incomingComponents.host?.lowercased() == redirectComponents.host?.lowercased()
            && incomingComponents.path == redirectComponents.path
    }

    private static func normalizeServerURLString(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed) else { return nil }
        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        guard let host = components.host, !host.isEmpty else { return nil }
        components.scheme = scheme
        if components.path.isEmpty {
            components.path = "/"
        } else if !components.path.hasSuffix("/") {
            components.path += "/"
        }
        return components.url?.absoluteString
    }

    private static func isLoopbackServerURLString(_ rawValue: String) -> Bool {
        guard let components = URLComponents(string: rawValue), let host = components.host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private static func cacheSafeIdentifier(for rawValue: String) -> String {
        let cleaned = rawValue.replacingOccurrences(
            of: "[^A-Za-z0-9]+",
            with: "_",
            options: .regularExpression
        )
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "default" : trimmed
    }

    private func displayServerName(from rawValue: String) -> String {
        guard let components = URLComponents(string: rawValue), let host = components.host, !host.isEmpty else {
            return "当前服务器"
        }
        if let port = components.port {
            return "\(host):\(port)"
        }
        return host
    }

    private func userFriendlyConnectionMessage(for error: Error) -> String {
        if let apiError = error as? PortfolioWorkbenchAPIClientError {
            switch apiError {
            case .invalidResponse:
                return "服务返回异常，请稍后重试。"
            case let .server(statusCode, message):
                if statusCode == 401 {
                    return "登录状态已失效，请重新验证。"
                }
                if statusCode >= 500 {
                    return "服务暂时不可用，请稍后重试。"
                }
                return message
            case let .transport(message):
                let lowered = message.lowercased()
                if lowered.contains("timed out") || lowered.contains("timeout") {
                    return "连接超时，已尝试自动切换服务器。"
                }
                if lowered.contains("could not connect")
                    || lowered.contains("offline")
                    || lowered.contains("network")
                    || lowered.contains("connection") {
                    return "网络连接异常，请检查网络后重试。"
                }
                return "连接失败，请稍后重试。"
            }
        }
        return shouldAttemptServerFailover(for: error)
            ? "当前网络连接异常，请稍后重试。"
            : error.localizedDescription
    }

    #if DEBUG
    private func debugPrintStartupState() {
        let currentUserSummary =
            effectiveCurrentUser.map { "\($0.authProvider):\($0.userId)" } ?? "nil"
        let tokenSummary =
            (effectiveSessionToken?.isEmpty == false)
            ? "len=\(effectiveSessionToken?.count ?? 0)"
            : "nil"
        let message = "[AppSettingsStore] startup server=\(trimmedServerURLString) auth=\(isAuthenticated) user=\(currentUserSummary) token=\(tokenSummary) localOnly=\(isLocalOnlySession) longbridge=\(longbridgeSessionState.rawValue)"
        NSLog("%@", message)
        persistStartupDebugMessage(message)
    }

    private func persistStartupDebugMessage(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "[\(formatter.string(from: .now))] \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        do {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let url = directory.appendingPathComponent("portfolio-workbench-startup.log")
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                    return
                }
            }
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[AppSettingsStore] failed to persist startup debug log: %@", error.localizedDescription)
        }
    }
    #endif
}
