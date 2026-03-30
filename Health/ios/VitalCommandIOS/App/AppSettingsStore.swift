import Foundation
import SwiftUI
import VitalCommandMobileCore

enum AppTab: Hashable {
    case home
    case plan
    case reports
    case data
}

enum HomeDestination {
    case medicalInsight
    case geneticInsight
    case dietInsight
}

@MainActor
final class AppSettingsStore: ObservableObject {
    static let currentRemoteServerURL = "http://10.8.144.16:3000/"
    static let defaultLANServerURL = currentRemoteServerURL
    static let defaultSimulatorServerURL = "http://127.0.0.1:3000/"
    @Published var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey)
        }
    }
    @Published private(set) var dataRefreshVersion = 0
    @Published var selectedTab: AppTab = .home
    @Published var pendingHomeDestination: HomeDestination?
    var authToken: String?

    static let serverURLKey = "vital-command.server-url"
    static let savedServersKey = "vital-command.saved-servers"
    static let discoveredServersKey = "vital-command.discovered-servers"

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
    @Published private(set) var recentDiscoveredServerURLs: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(recentDiscoveredServerURLs) {
                UserDefaults.standard.set(data, forKey: Self.discoveredServersKey)
            }
        }
    }

    private static let legacyServerURLMap: [String: String] = [
        "http://10.8.140.209:3000": currentRemoteServerURL,
        "http://10.8.140.209:3000/": currentRemoteServerURL,
        "http://10.8.144.16:3001": currentRemoteServerURL,
        "http://10.8.144.16:3001/": currentRemoteServerURL,
        "http://192.168.31.193:3000": currentRemoteServerURL,
        "http://192.168.31.193:3000/": currentRemoteServerURL
    ]

    init() {
        let storedValue = Self.migrateServerURL(
            UserDefaults.standard.string(forKey: Self.serverURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let storedValue {
            UserDefaults.standard.set(storedValue, forKey: Self.serverURLKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.serverURLKey)
        }

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
            self.savedServers = Self.migrateSavedServers(servers)
        } else {
            self.savedServers = []
        }

        if let data = UserDefaults.standard.data(forKey: Self.discoveredServersKey),
           let urls = try? JSONDecoder().decode([String].self, from: data) {
            self.recentDiscoveredServerURLs = urls.compactMap { HealthKitUploadTargetResolver.canonicalize($0) }
        } else {
            self.recentDiscoveredServerURLs = []
        }
    }

    var trimmedServerURLString: String {
        serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var dashboardReloadKey: String {
        "\(trimmedServerURLString)#\(dataRefreshVersion)"
    }

    func cacheScope(userID: String?) -> String {
        let server = HealthKitUploadTargetResolver.canonicalize(trimmedServerURLString) ?? trimmedServerURLString
        let user = userID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? userID! : "anonymous"
        return "\(server)#\(user)"
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

    func openHome(destination: HomeDestination? = nil) {
        pendingHomeDestination = destination
        selectedTab = .home
    }

    func saveCurrentServer(name: String? = nil) {
        let url = trimmedServerURLString
        guard !url.isEmpty else { return }
        if !savedServers.contains(where: { $0.url == url }) {
            savedServers.append(SavedServer(url: url, name: name ?? url, addedAt: Date()))
        }
    }

    func rememberDiscoveredServerURLs(_ urls: [String]) {
        let candidates =
            urls
            .compactMap { HealthKitUploadTargetResolver.canonicalize($0) }
            .filter { HealthKitUploadTargetResolver.isLikelyLAN(urlString: $0) }

        guard candidates.isEmpty == false else { return }

        var merged: [String] = []
        var seen = Set<String>()

        for url in candidates + recentDiscoveredServerURLs {
            guard seen.insert(url).inserted else { continue }
            merged.append(url)
        }

        recentDiscoveredServerURLs = Array(merged.prefix(12))
    }

    func healthKitUploadTargetURLs() -> [String] {
        return HealthKitUploadTargetResolver.prioritizeTargets(
            discoveredServerURLs: recentDiscoveredServerURLs,
            currentServerURL: trimmedServerURLString,
            savedServerURLs: savedServers.map(\.url)
        )
    }

    func removeSavedServer(_ server: SavedServer) {
        savedServers.removeAll { $0.id == server.id }
    }

    private static func migrateServerURL(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }

        return legacyServerURLMap[raw] ?? raw
    }

    private static func migrateSavedServers(_ servers: [SavedServer]) -> [SavedServer] {
        var seen = Set<String>()
        var migrated: [SavedServer] = []

        for server in servers {
            let nextURL = migrateServerURL(server.url) ?? server.url
            guard seen.insert(nextURL).inserted else {
                continue
            }

            migrated.append(
                SavedServer(
                    url: nextURL,
                    name: server.name,
                    addedAt: server.addedAt
                )
            )
        }

        return migrated
    }
}
