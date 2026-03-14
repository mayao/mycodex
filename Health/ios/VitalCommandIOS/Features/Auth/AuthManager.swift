import SwiftUI
import LocalAuthentication
import VitalCommandMobileCore

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: UserInfo?
    @Published var isLoading = true

    private(set) var token: String?

    private static let tokenKey = "vital-command.auth-token"
    private static let userKey = "vital-command.auth-user"
    private static let deviceIdKey = "vital-command.device-id"

    init() {
        loadSavedSession()
    }

    // MARK: - Device ID

    /// Stable per-installation device identifier (persisted in Keychain to survive reinstalls)
    var deviceId: String {
        if let saved = KeychainHelper.read(key: Self.deviceIdKey) {
            return saved
        }
        let newId = UUID().uuidString
        KeychainHelper.save(key: Self.deviceIdKey, value: newId)
        return newId
    }

    // MARK: - Session persistence

    func loadSavedSession() {
        isLoading = true
        if let savedToken = KeychainHelper.read(key: Self.tokenKey) {
            token = savedToken
            if let userData = UserDefaults.standard.data(forKey: Self.userKey),
               let user = try? JSONDecoder().decode(UserInfo.self, from: userData) {
                currentUser = user
                isAuthenticated = true
            } else {
                isAuthenticated = true
            }
        }
        isLoading = false
    }

    func login(token: String, user: UserInfo) {
        self.token = token
        self.currentUser = user
        self.isAuthenticated = true

        KeychainHelper.save(key: Self.tokenKey, value: token)
        if let userData = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(userData, forKey: Self.userKey)
        }
    }

    func logout() {
        token = nil
        currentUser = nil
        isAuthenticated = false

        KeychainHelper.delete(key: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
    }

    // MARK: - Device-based auto login

    /// Register / login using device ID — no SMS needed
    func deviceAutoLogin(using settings: AppSettingsStore) async throws {
        let client = try settings.makeClient()
        let deviceLabel = UIDevice.current.name
        let response = try await client.deviceLogin(
            DeviceLoginRequest(deviceId: deviceId, deviceLabel: deviceLabel)
        )
        login(token: response.token, user: response.user)
    }

    // MARK: - Offline mode

    /// Allow user to enter app in offline/cached mode when server is unreachable
    func enterOfflineMode() {
        isAuthenticated = true
        isLoading = false
    }

    // MARK: - Face ID / Touch ID

    static var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    static var biometricName: String {
        switch biometricType {
        case .faceID: return "面容 ID"
        case .touchID: return "指纹"
        case .opticID: return "Optic ID"
        @unknown default: return "生物识别"
        }
    }

    static var biometricIcon: String {
        switch biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.shield"
        }
    }

    func authenticateWithBiometrics() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "使用\(Self.biometricName)快速登录"
            )
        } catch {
            return false
        }
    }

    // MARK: - Validate existing session

    func validateSession(using settings: AppSettingsStore) async {
        guard let token else {
            isAuthenticated = false
            isLoading = false
            return
        }

        do {
            let client = try settings.makeClient(token: token)
            let response = try await client.fetchCurrentUser()
            currentUser = response.user
            isAuthenticated = true
            isLoading = false
            if let userData = try? JSONEncoder().encode(response.user) {
                UserDefaults.standard.set(userData, forKey: Self.userKey)
            }
        } catch {
            let isUnauthorized = (error as? HealthAPIClientError).map {
                if case let .server(statusCode, _) = $0 { return statusCode == 401 }
                return false
            } ?? false

            if isUnauthorized {
                // Token expired — clear but keep device ID for easy re-login
                KeychainHelper.delete(key: Self.tokenKey)
                self.token = nil
                isAuthenticated = false
            } else {
                // Network error — stay authenticated with cached user data
                if currentUser != nil {
                    isAuthenticated = true
                }
            }
            isLoading = false
        }
    }
}
