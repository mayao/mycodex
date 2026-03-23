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
    @Published private(set) var connectionStatusMessage: String?

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
        self.connectionStatusMessage = nil

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
        connectionStatusMessage = "正在连接服务器…"

        do {
            let payload = try await bootstrapDeviceSessionWithAutoFailover()
            updateAuthenticatedSession(payload)
        } catch {
            connectionStatusMessage = userFriendlyConnectionMessage(for: error)
            // Keep the login screen visible; the user can still switch server or log in manually.
        }
    }

    func loginWithDeviceAccount(requireLocalAuthentication: Bool = false) async throws -> MobileSessionPayload {
        refreshBiometryAvailability()
        if requireLocalAuthentication {
            try await authenticateLocalUser(reason: "使用 \(biometryType.displayName) 登录你的投资账户")
        }
        connectionStatusMessage = "正在连接服务器…"

        let payload = try await bootstrapDeviceSessionWithAutoFailover()
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

    func proceedIntoActiveSessionWithoutBiometric() async throws {
        try await validateAuthenticatedSessionIfNeeded(force: true)
        requiresBiometricUnlock = false
        connectionStatusMessage = "已连接 \(displayServerName(from: trimmedServerURLString))"
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
        do {
            let client = try makeClient()
            try await validateAuthenticatedSessionIfNeeded(using: client, force: forceSessionCheck)
            connectionStatusMessage = "已连接 \(displayServerName(from: trimmedServerURLString))"
            return try makeClient()
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
        guard let wifiAddress = getWiFiAddress() else {
            connectionStatusMessage = "当前未获取到局域网地址，无法自动探测服务器。"
            return false
        }

        let segments = wifiAddress.split(separator: ".")
        guard segments.count == 4 else {
            connectionStatusMessage = "局域网地址格式异常，无法自动探测服务器。"
            return false
        }

        let subnet = segments[0...2].joined(separator: ".")
        let ports = discoveryPorts()
        connectionStatusMessage = "正在自动扫描局域网服务器…"

        var discoveredURL: String?
        await withTaskGroup(of: String?.self) { group in
            for hostIndex in 1...254 {
                let candidateIP = "\(subnet).\(hostIndex)"
                if candidateIP == wifiAddress {
                    continue
                }
                for port in ports {
                    group.addTask {
                        await self.probeDiscoveryServer(ip: candidateIP, port: port)
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

    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let interfaceAddress = interface.ifa_addr else { continue }
            guard interfaceAddress.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

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
            if !candidate.isEmpty, !candidate.hasPrefix("169.254.") {
                address = candidate
                break
            }
        }

        return address
    }

    private func candidateServerURLs(includeCurrent: Bool, current: String?) -> [String] {
        var raw: [String] = []
        if includeCurrent, let current {
            raw.append(current)
        }
        raw.append(Self.defaultServerURLString)
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
}
