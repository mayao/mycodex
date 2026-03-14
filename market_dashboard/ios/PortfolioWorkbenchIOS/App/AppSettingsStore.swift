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

@MainActor
final class AppSettingsStore: ObservableObject {
    static let defaultServerURLString = "http://10.8.144.16:8008/"
    static let defaultServerURLInfoKey = "PORTFOLIO_WORKBENCH_DEFAULT_SERVER_URL"
    static let autoMockLoginInfoKey = "PORTFOLIO_WORKBENCH_AUTO_MOCK_LOGIN"
    static let autoOwnerLoginInfoKey = "PORTFOLIO_WORKBENCH_AUTO_OWNER_LOGIN"
    static let resetStateOnLaunchInfoKey = "PORTFOLIO_WORKBENCH_RESET_STATE_ON_LAUNCH"
    static let serverURLKey = "portfolio-workbench-ios.server-url"
    static let scopedSessionsKey = "portfolio-workbench-ios.scoped-sessions"
    static let savedServersKey = "portfolio-workbench-ios.saved-servers"
    static let hideSensitiveAmountsKey = "portfolio-workbench-ios.hide-sensitive-amounts"
    static let aiSettingsKey = "portfolio-workbench-ios.ai-settings"
    static let sessionTokenKey = "portfolio-workbench-ios.session-token"
    static let currentUserKey = "portfolio-workbench-ios.current-user"
    static let localMockSessionKey = "portfolio-workbench-ios.local-mock-session"
    static let biometricUnlockEnabledKey = "portfolio-workbench-ios.biometric-unlock-enabled"
    static let automaticDeviceRestoreSuppressedKey = "portfolio-workbench-ios.device-restore-suppressed"
    private static let sessionValidationInterval: TimeInterval = 90

    private let identityStore: DeviceAccountIdentityStore
    private let aiCredentialStore: AIProviderCredentialStore
    private let bundledDefaultServerURLString: String?
    private var scopedSessions: [String: ScopedServerSession]
    private var lastSessionValidationAt: Date?
    private var lastValidatedServerURLString: String?
    private var automaticRestoreAttemptServerURLString: String?
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

    init(
        identityStore: DeviceAccountIdentityStore = .shared,
        aiCredentialStore: AIProviderCredentialStore = .shared
    ) {
        self.identityStore = identityStore
        self.aiCredentialStore = aiCredentialStore

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
        if let initialScopedSession = self.scopedSessions[initialServerURL] {
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
        if biometricUnlockEnabled && isAuthenticated {
            requiresBiometricUnlock = true
        }
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

    var isAuthenticated: Bool {
        currentUser != nil && !(sessionToken ?? "").isEmpty
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

    private var effectiveDataIdentity: String {
        let resolved =
            currentUser?.userId
            ?? deviceAccountProfile.assignedUserID
            ?? deviceAccountProfile.installationID
        return resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "anonymous" : resolved
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
        mergeDeviceAccount(payload)
        requiresBiometricUnlock = false
        lastSessionValidationAt = .now
        lastValidatedServerURLString = trimmedServerURLString
        automaticRestoreAttemptServerURLString = nil
        automaticDeviceRestoreSuppressed = false
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
    }

    func logoutCurrentSession() {
        automaticDeviceRestoreSuppressed = true
        clearAuthentication()
    }

    func restoreDeviceSessionIfPossible() async {
        guard !isAuthenticated, !isUsingLocalMockSession, !isRestoringDeviceSession else {
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

        do {
            let client = try makeNetworkClient()
            let payload = try await client.bootstrapDeviceAccount(
                deviceID: deviceAccountProfile.installationID,
                deviceName: Self.currentDeviceLabel
            )
            updateAuthenticatedSession(payload)
        } catch {
            // Keep the login screen visible; the user can still switch server or log in manually.
        }
    }

    func loginWithDeviceAccount(requireLocalAuthentication: Bool = false) async throws -> MobileSessionPayload {
        refreshBiometryAvailability()
        if requireLocalAuthentication {
            try await authenticateLocalUser(reason: "使用 \(biometryType.displayName) 登录你的投资账户")
        }

        let client = try makeNetworkClient()
        let payload = try await client.bootstrapDeviceAccount(
            deviceID: deviceAccountProfile.installationID,
            deviceName: Self.currentDeviceLabel
        )
        updateAuthenticatedSession(payload)
        if supportsBiometricUnlock {
            biometricUnlockEnabled = true
        }
        return payload
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

    func makeClient() throws -> PortfolioWorkbenchAPIClient {
        if isUsingLocalMockSession {
            return PortfolioWorkbenchLocalMock.makeClient(
                currentUser: currentUser,
                sessionToken: sessionToken
            )
        }
        return try makeNetworkClient()
    }

    func makeValidatedClient(forceSessionCheck: Bool = true) async throws -> PortfolioWorkbenchAPIClient {
        let client = try makeClient()
        try await validateAuthenticatedSessionIfNeeded(using: client, force: forceSessionCheck)
        return try makeClient()
    }

    func makeNetworkClient() throws -> PortfolioWorkbenchAPIClient {
        guard let url = URL(string: trimmedServerURLString), url.scheme?.hasPrefix("http") == true else {
            throw PortfolioWorkbenchAPIClientError.transport("请填写可访问的服务地址，例如 \(Self.defaultServerURLString)")
        }

        return PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(
                baseURL: url,
                sessionToken: sessionToken,
                aiRequestConfiguration: currentAIRequestConfiguration()
            )
        )
    }

    func validateAuthenticatedSessionIfNeeded(
        using client: PortfolioWorkbenchAPIClient? = nil,
        force: Bool = false
    ) async throws {
        guard isAuthenticated, !isUsingLocalMockSession else {
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
        guard hasProvisionedDeviceAccount || currentUser?.authProvider == "device" else {
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
        guard let currentServerURL = normalizedCurrentServerURL else {
            sessionToken = nil
            currentUser = nil
            isUsingLocalMockSession = false
            requiresBiometricUnlock = false
            return
        }

        guard let scopedSession = scopedSessions[currentServerURL] else {
            sessionToken = nil
            currentUser = nil
            isUsingLocalMockSession = false
            requiresBiometricUnlock = false
            return
        }

        sessionToken = scopedSession.sessionToken
        currentUser = scopedSession.currentUser
        isUsingLocalMockSession = scopedSession.isUsingLocalMockSession
        if biometricUnlockEnabled {
            requiresBiometricUnlock = true
        }
    }

    private func persistCurrentScopedSession() {
        guard let currentServerURL = normalizedCurrentServerURL else {
            return
        }

        if let sessionToken, !sessionToken.isEmpty, let currentUser {
            scopedSessions[currentServerURL] = ScopedServerSession(
                sessionToken: sessionToken,
                currentUser: currentUser,
                isUsingLocalMockSession: isUsingLocalMockSession
            )
        } else {
            scopedSessions.removeValue(forKey: currentServerURL)
        }

        if let data = try? JSONEncoder().encode(scopedSessions) {
            UserDefaults.standard.set(data, forKey: Self.scopedSessionsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.scopedSessionsKey)
        }
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

    private static func cacheSafeIdentifier(for rawValue: String) -> String {
        let cleaned = rawValue.replacingOccurrences(
            of: "[^A-Za-z0-9]+",
            with: "_",
            options: .regularExpression
        )
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "default" : trimmed
    }
}
