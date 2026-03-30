import Foundation

@MainActor
final class ServerDiscoveryService: ObservableObject {
    struct DiscoveredServer: Identifiable, Equatable, Sendable {
        var id: String { urlString }
        let name: String
        let urlString: String
        let ip: String
        let port: Int
        let appName: String
        let lastSeen: Date
    }

    @Published private(set) var discoveredServers: [DiscoveredServer] = []
    @Published private(set) var isScanning = false
    @Published private(set) var statusMessage: String?

    private var scanTask: Task<Void, Never>?
    private nonisolated static let maxConcurrentProbes = 24
    private nonisolated static let maxScannedSubnets = 2

    func startScan(currentServerURLString: String) {
        stopScanning()
        isScanning = true
        statusMessage = "正在自动探测可用的 Invest 服务…"

        scanTask = Task {
            let scanResult = await Self.performScan(currentServerURLString: currentServerURLString)
            guard !Task.isCancelled else { return }
            discoveredServers = scanResult.servers
            isScanning = false
            statusMessage = scanResult.statusMessage ?? (
                discoveredServers.isEmpty
                ? "没有发现可连接的服务。"
                : "发现 \(discoveredServers.count) 台可连接的部署机器。"
            )
        }
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private struct ScanResult: Sendable {
        let servers: [DiscoveredServer]
        let statusMessage: String?
    }

    private nonisolated static func performScan(currentServerURLString: String) async -> ScanResult {
        let currentURL = URL(string: currentServerURLString.trimmingCharacters(in: .whitespacesAndNewlines))
        let preferredPort = currentURL?.port ?? 8008
        let preferredHost = currentURL?.host
        var nextServers: [DiscoveredServer] = []

        if let preferredHost,
           let preferred = await probeServer(host: preferredHost, port: preferredPort) {
            nextServers.append(preferred)
        }

        let localAddresses = localIPv4Addresses()
        if localAddresses.isEmpty && nextServers.isEmpty {
            return ScanResult(
                servers: [],
                statusMessage: "未获取到当前网络地址，请确认设备已联网。"
            )
        }
        guard !localAddresses.isEmpty else {
            return ScanResult(
                servers: deduplicated(nextServers),
                statusMessage: nil
            )
        }

        let subnets = Array(
            NetworkDiscoveryHints.candidateSubnetPrefixes(
                localAddresses: localAddresses,
                seededHosts: preferredHost.map { [$0] } ?? []
            ).prefix(Self.maxScannedSubnets)
        )
        guard !subnets.isEmpty else {
            return ScanResult(
                servers: deduplicated(nextServers),
                statusMessage: nextServers.isEmpty ? "当前网络没有可探测的私有网段。" : nil
            )
        }

        var candidatePorts = [preferredPort]
        if preferredPort != 8008 {
            candidatePorts.append(8008)
        }

        var targets: [(host: String, port: Int)] = []
        var seenTargets = Set<String>()

        func appendTarget(host: String, port: Int) {
            let key = "\(host):\(port)"
            guard seenTargets.insert(key).inserted else {
                return
            }
            targets.append((host: host, port: port))
        }

        for subnet in subnets {
            for hostIndex in 1...254 {
                let candidateHost = "\(subnet).\(hostIndex)"
                if localAddresses.contains(candidateHost) {
                    continue
                }
                for port in candidatePorts {
                    appendTarget(host: candidateHost, port: port)
                }
            }
        }

        if let preferredHost {
            appendTarget(host: preferredHost, port: preferredPort)
        }

        for chunkStart in stride(from: 0, to: targets.count, by: Self.maxConcurrentProbes) {
            if Task.isCancelled {
                break
            }
            let chunkEnd = min(chunkStart + Self.maxConcurrentProbes, targets.count)
            let chunk = targets[chunkStart..<chunkEnd]

            await withTaskGroup(of: DiscoveredServer?.self) { group in
                for target in chunk {
                    group.addTask {
                        await probeServer(host: target.host, port: target.port)
                    }
                }

                for await result in group {
                    guard let result else { continue }
                    nextServers.append(result)
                }
            }
        }

        return ScanResult(
            servers: deduplicated(nextServers),
            statusMessage: nil
        )
    }

    private nonisolated static func deduplicated(_ servers: [DiscoveredServer]) -> [DiscoveredServer] {
        var seen = Set<String>()
        return servers
            .sorted { lhs, rhs in
                if lhs.lastSeen != rhs.lastSeen {
                    return lhs.lastSeen > rhs.lastSeen
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .filter { server in
                seen.insert(server.id).inserted
            }
    }

    private nonisolated static func probeServer(host: String, port: Int) async -> DiscoveredServer? {
        guard !Task.isCancelled else {
            return nil
        }
        guard let url = URL(string: "http://\(host):\(port)/api/mobile/discovery") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else {
                return nil
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let payload = try JSONDecoder().decode(DiscoveryResponse.self, from: data)
            guard payload.service == "portfolio-workbench" else {
                return nil
            }

            let urlString = payload.suggestedBaseURL.isEmpty ? "http://\(host):\(port)/" : payload.suggestedBaseURL
            return DiscoveredServer(
                name: payloadHostName(from: payload, fallbackHost: host),
                urlString: urlString,
                ip: payload.detectedLANIP ?? host,
                port: payload.port,
                appName: payload.appName,
                lastSeen: .now
            )
        } catch {
            return nil
        }
    }

    private nonisolated static func payloadHostName(from payload: DiscoveryResponse, fallbackHost: String) -> String {
        if let host = URL(string: payload.suggestedBaseURL)?.host, !host.isEmpty {
            return host
        }
        return payload.appName.isEmpty ? fallbackHost : payload.appName
    }

    private nonisolated static func localIPv4Addresses() -> [String] {
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
}

enum NetworkDiscoveryHints {
    static func candidateSubnetPrefixes(localAddresses: [String], seededHosts: [String] = []) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            ordered.append(trimmed)
        }

        for address in localAddresses {
            if let prefix = privateSubnetPrefix(from: address) {
                append(prefix)
            }
        }

        for host in seededHosts {
            if let prefix = privateSubnetPrefix(from: host) {
                append(prefix)
            }
        }

        return ordered
    }

    static func privateSubnetPrefix(from host: String) -> String? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: ".")
        guard components.count == 4 else {
            return nil
        }
        guard isPrivateIPv4(components: components) else {
            return nil
        }
        return components[0...2].joined(separator: ".")
    }

    private static func isPrivateIPv4(components: [Substring]) -> Bool {
        guard components.count == 4,
              let first = Int(components[0]),
              let second = Int(components[1]) else {
            return false
        }

        switch first {
        case 10:
            return true
        case 172:
            return (16...31).contains(second)
        case 192:
            return second == 168
        default:
            return false
        }
    }
}

private struct DiscoveryResponse: Decodable {
    let service: String
    let appName: String
    let port: Int
    let suggestedBaseURL: String
    let detectedLANIP: String?

    private enum CodingKeys: String, CodingKey {
        case service
        case appName = "app_name"
        case port
        case suggestedBaseURL = "suggested_base_url"
        case detectedLANIP = "detected_lan_ip"
    }
}
