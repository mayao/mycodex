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

@MainActor
final class AppSettingsStore: ObservableObject {
    static let defaultServerURLInfoKey = "PORTFOLIO_WORKBENCH_DEFAULT_SERVER_URL"
    static let autoMockLoginInfoKey = "PORTFOLIO_WORKBENCH_AUTO_MOCK_LOGIN"
    static let autoOwnerLoginInfoKey = "PORTFOLIO_WORKBENCH_AUTO_OWNER_LOGIN"
    static let resetStateOnLaunchInfoKey = "PORTFOLIO_WORKBENCH_RESET_STATE_ON_LAUNCH"
    static let serverURLKey = "portfolio-workbench-ios.server-url"
    static let hideSensitiveAmountsKey = "portfolio-workbench-ios.hide-sensitive-amounts"
    static let sessionTokenKey = "portfolio-workbench-ios.session-token"
    static let currentUserKey = "portfolio-workbench-ios.current-user"
    static let localMockSessionKey = "portfolio-workbench-ios.local-mock-session"
    static let biometricUnlockEnabledKey = "portfolio-workbench-ios.biometric-unlock-enabled"
    private static let sessionValidationInterval: TimeInterval = 90

    private let identityStore: DeviceAccountIdentityStore
    private var lastSessionValidationAt: Date?
    private var lastValidatedServerURLString: String?

    @Published var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey)
            lastSessionValidationAt = nil
            lastValidatedServerURLString = nil
        }
    }
    @Published var hideSensitiveAmounts: Bool {
        didSet {
            UserDefaults.standard.set(hideSensitiveAmounts, forKey: Self.hideSensitiveAmountsKey)
        }
    }
    @Published var sessionToken: String? {
        didSet {
            if let sessionToken, !sessionToken.isEmpty {
                UserDefaults.standard.set(sessionToken, forKey: Self.sessionTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.sessionTokenKey)
            }
        }
    }
    @Published private(set) var isUsingLocalMockSession: Bool {
        didSet {
            UserDefaults.standard.set(isUsingLocalMockSession, forKey: Self.localMockSessionKey)
        }
    }
    @Published private(set) var currentUser: MobileUser? {
        didSet {
            if let currentUser, let data = try? JSONEncoder().encode(currentUser) {
                UserDefaults.standard.set(data, forKey: Self.currentUserKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentUserKey)
            }
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

    init(identityStore: DeviceAccountIdentityStore = .shared) {
        self.identityStore = identityStore

        let bundledDefaultURL =
            (Bundle.main.object(forInfoDictionaryKey: Self.defaultServerURLInfoKey) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        self.serverURLString =
            UserDefaults.standard.string(forKey: Self.serverURLKey)
            ?? (bundledDefaultURL?.isEmpty == false ? bundledDefaultURL : nil)
            ?? "http://127.0.0.1:8008/"
        self.hideSensitiveAmounts = UserDefaults.standard.bool(forKey: Self.hideSensitiveAmountsKey)
        self.sessionToken = UserDefaults.standard.string(forKey: Self.sessionTokenKey)
        self.isUsingLocalMockSession = UserDefaults.standard.bool(forKey: Self.localMockSessionKey)
        if let data = UserDefaults.standard.data(forKey: Self.currentUserKey),
           let decoded = try? JSONDecoder().decode(MobileUser.self, from: data) {
            self.currentUser = decoded
        } else {
            self.currentUser = nil
        }
        self.deviceAccountProfile = identityStore.resolveProfile(defaultDeviceLabel: Self.currentDeviceLabel)
        self.biometricUnlockEnabled = UserDefaults.standard.object(forKey: Self.biometricUnlockEnabledKey) as? Bool ?? false
        self.requiresBiometricUnlock = false
        self.biometryType = .none

        let environment = ProcessInfo.processInfo.environment
        let autoMockLogin = environment[Self.autoMockLoginInfoKey]?.lowercased()
        let shouldResetState =
            environment[Self.resetStateOnLaunchInfoKey] == "1"
            || environment[Self.resetStateOnLaunchInfoKey]?.lowercased() == "true"
        if shouldResetState {
            self.sessionToken = nil
            self.currentUser = nil
            self.isUsingLocalMockSession = false
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

    func updateAuthenticatedSession(_ payload: MobileSessionPayload) {
        sessionToken = payload.sessionToken
        currentUser = payload.user
        isUsingLocalMockSession = false
        mergeDeviceAccount(payload)
        requiresBiometricUnlock = false
        lastSessionValidationAt = .now
        lastValidatedServerURLString = trimmedServerURLString
    }

    func activateLocalMockPhoneSession(phoneNumber: String = PortfolioWorkbenchLocalMock.mockPhoneNumber) {
        let payload = PortfolioWorkbenchLocalMock.makePhoneSession(phoneNumber: phoneNumber)
        sessionToken = payload.sessionToken
        currentUser = payload.user
        isUsingLocalMockSession = true
        requiresBiometricUnlock = false
        lastSessionValidationAt = .now
        lastValidatedServerURLString = trimmedServerURLString
    }

    func activateLocalMockWeChatSession(displayName: String? = nil) {
        let payload = PortfolioWorkbenchLocalMock.makeWeChatSession(displayName: displayName)
        sessionToken = payload.sessionToken
        currentUser = payload.user
        isUsingLocalMockSession = true
        requiresBiometricUnlock = false
        lastSessionValidationAt = .now
        lastValidatedServerURLString = trimmedServerURLString
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

    func makeValidatedClient(forceSessionCheck: Bool = false) async throws -> PortfolioWorkbenchAPIClient {
        let client = try makeClient()
        try await validateAuthenticatedSessionIfNeeded(using: client, force: forceSessionCheck)
        return client
    }

    func makeNetworkClient() throws -> PortfolioWorkbenchAPIClient {
        guard let url = URL(string: trimmedServerURLString), url.scheme?.hasPrefix("http") == true else {
            throw PortfolioWorkbenchAPIClientError.transport("请填写可访问的服务地址，例如 http://192.168.1.10:8008/")
        }

        return PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(
                baseURL: url,
                sessionToken: sessionToken
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
                clearAuthentication()
            }
            throw error
        } catch {
            throw error
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
}
