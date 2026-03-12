import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class AppSettingsStore: ObservableObject {
    static let defaultLANServerURL = "http://10.8.140.209:3000/"
    static let defaultSimulatorServerURL = "http://127.0.0.1:3000/"
    @Published var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey)
        }
    }
    @Published private(set) var dataRefreshVersion = 0
    var authToken: String?

    static let serverURLKey = "vital-command.server-url"

    init() {
        let storedValue = UserDefaults.standard.string(forKey: Self.serverURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines)

#if targetEnvironment(simulator)
        self.serverURLString = (storedValue?.isEmpty == false ? storedValue : Self.defaultSimulatorServerURL) ?? Self.defaultSimulatorServerURL
#else
        if let storedValue, storedValue.isEmpty == false, storedValue.contains("localhost") == false, storedValue.contains("127.0.0.1") == false {
            self.serverURLString = storedValue
        } else {
            self.serverURLString = Self.defaultLANServerURL
        }
#endif
    }

    var trimmedServerURLString: String {
        serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var dashboardReloadKey: String {
        "\(trimmedServerURLString)#\(dataRefreshVersion)"
    }

    func makeClient(token: String? = nil) throws -> HealthAPIClient {
        guard let url = URL(string: trimmedServerURLString), url.scheme?.hasPrefix("http") == true else {
            throw HealthAPIClientError.transport("请填写可访问的服务地址，例如 http://192.168.1.10:3000/")
        }

        let effectiveToken = token ?? authToken
        return HealthAPIClient(configuration: AppServerConfiguration(baseURL: url), token: effectiveToken)
    }

    func markHealthDataChanged() {
        dataRefreshVersion += 1
    }
}
