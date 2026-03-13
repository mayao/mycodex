import Foundation

@MainActor
final class ServerDiscoveryService: ObservableObject {
    struct DiscoveredServer: Identifiable, Equatable {
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

    func startScan(currentServerURLString: String) {
        stopScanning()
        isScanning = true
        statusMessage = "正在扫描同一局域网内可用的 Invest 服务…"

        scanTask = Task {
            await performScan(currentServerURLString: currentServerURLString)
            guard !Task.isCancelled else { return }
            isScanning = false
            statusMessage = discoveredServers.isEmpty
                ? "没有发现可连接的局域网服务。"
                : "发现 \(discoveredServers.count) 台可连接的部署机器。"
        }
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func performScan(currentServerURLString: String) async {
        let currentURL = URL(string: currentServerURLString.trimmingCharacters(in: .whitespacesAndNewlines))
        let preferredPort = currentURL?.port ?? 8008
        let preferredHost = currentURL?.host
        var nextServers: [DiscoveredServer] = []

        if let preferredHost,
           let preferred = await probeServer(ip: preferredHost, port: preferredPort) {
            nextServers.append(preferred)
        }

        guard let wifiAddress = getWiFiAddress() else {
            discoveredServers = deduplicated(nextServers)
            if nextServers.isEmpty {
                statusMessage = "当前没有拿到 Wi‑Fi 局域网地址，请确认手机已连接无线网络。"
            }
            return
        }

        let segments = wifiAddress.split(separator: ".")
        guard segments.count == 4 else {
            discoveredServers = deduplicated(nextServers)
            return
        }

        let subnet = segments[0...2].joined(separator: ".")
        var candidatePorts = [preferredPort]
        if preferredPort != 8008 {
            candidatePorts.append(8008)
        }

        await withTaskGroup(of: DiscoveredServer?.self) { group in
            for hostIndex in 1...254 {
                let candidateIP = "\(subnet).\(hostIndex)"
                if candidateIP == wifiAddress {
                    continue
                }
                for port in candidatePorts {
                    group.addTask {
                        await self.probeServer(ip: candidateIP, port: port)
                    }
                }
            }

            for await result in group {
                guard let result, !Task.isCancelled else { continue }
                nextServers.append(result)
                discoveredServers = deduplicated(nextServers)
            }
        }

        discoveredServers = deduplicated(nextServers)
    }

    private func deduplicated(_ servers: [DiscoveredServer]) -> [DiscoveredServer] {
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

    private func probeServer(ip: String, port: Int) async -> DiscoveredServer? {
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

            let payload = try JSONDecoder().decode(DiscoveryResponse.self, from: data)
            guard payload.service == "portfolio-workbench" else {
                return nil
            }

            let urlString = payload.suggestedBaseURL.isEmpty ? "http://\(ip):\(port)/" : payload.suggestedBaseURL
            return DiscoveredServer(
                name: payloadHostName(from: payload, fallbackIP: ip),
                urlString: urlString,
                ip: payload.detectedLANIP ?? ip,
                port: payload.port,
                appName: payload.appName,
                lastSeen: .now
            )
        } catch {
            return nil
        }
    }

    private func payloadHostName(from payload: DiscoveryResponse, fallbackIP: String) -> String {
        if let host = URL(string: payload.suggestedBaseURL)?.host, !host.isEmpty {
            return host
        }
        return payload.appName.isEmpty ? fallbackIP : payload.appName
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
