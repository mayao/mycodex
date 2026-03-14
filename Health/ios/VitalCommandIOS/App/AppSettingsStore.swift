import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class AppSettingsStore: ObservableObject {
    static let defaultLANServerURL = "http://192.168.31.193:3000/"
    static let defaultSimulatorServerURL = "http://127.0.0.1:3000/"
    @Published var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey)
        }
    }
    @Published private(set) var dataRefreshVersion = 0
    var authToken: String?

    static let serverURLKey = "vital-command.server-url"
    static let savedServersKey = "vital-command.saved-servers"

    struct SavedServer: Codable, Identifiable, Equatable {
        var id: String { url }
        let url: String
        let name: String
        let addedAt: Date
    }

    @Published var savedServers: [SavedServer] {
        didSet {
            if let data = try? JSONEncoder().encode(savedServers) {
                UserDefaults.standard.set(data, forKey: Self.savedServersKey)
            }
        }
    }

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

        if let data = UserDefaults.standard.data(forKey: Self.savedServersKey),
           let servers = try? JSONDecoder().decode([SavedServer].self, from: data) {
            self.savedServers = servers
        } else {
            self.savedServers = []
        }
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

    func saveCurrentServer(name: String? = nil) {
        let url = trimmedServerURLString
        guard !url.isEmpty else { return }
        if !savedServers.contains(where: { $0.url == url }) {
            savedServers.append(SavedServer(url: url, name: name ?? url, addedAt: Date()))
        }
    }

    func removeSavedServer(_ server: SavedServer) {
        savedServers.removeAll { $0.id == server.id }
    }
}
