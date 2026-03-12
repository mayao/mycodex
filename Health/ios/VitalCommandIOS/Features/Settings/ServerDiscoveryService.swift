import Foundation
import Network

@MainActor
final class ServerDiscoveryService: ObservableObject {
    struct DiscoveredServer: Identifiable, Equatable, Codable {
        var id: String { "\(ip):\(port)" }
        let service: String
        let name: String
        let ip: String
        let port: Int
        let version: String
        var lastSeen: Date

        var urlString: String { "http://\(ip):\(port)/" }

        var isRecentlyActive: Bool {
            Date().timeIntervalSince(lastSeen) < 15
        }
    }

    @Published private(set) var discoveredServers: [DiscoveredServer] = []
    @Published private(set) var isScanning = false

    private var listener: NWListener?
    private var connection: NWConnection?
    private var udpGroup: NWConnectionGroup?

    func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        listenForBroadcasts()
    }

    func stopScanning() {
        isScanning = false
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
        udpGroup?.cancel()
        udpGroup = nil
    }

    private func listenForBroadcasts() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .wifi

        do {
            let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: 41234))
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                self?.startReceiving(on: connection)
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[Discovery] Listening for broadcasts on port 41234")
                case .failed(let error):
                    print("[Discovery] Listener failed: \(error)")
                default:
                    break
                }
            }

            listener.start(queue: .main)
        } catch {
            print("[Discovery] Failed to create listener: \(error)")
            Task { await scanSubnet() }
        }
    }

    nonisolated private func startReceiving(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data = data, let json = try? JSONDecoder().decode(BroadcastMessage.self, from: data) {
                Task { @MainActor in
                    self?.addOrUpdateServer(from: json)
                }
            }
            if error == nil {
                self?.startReceiving(on: connection)
            }
        }
    }

    private struct BroadcastMessage: Codable {
        let service: String
        let name: String
        let ip: String
        let port: Int
        let version: String
    }

    private func addOrUpdateServer(from msg: BroadcastMessage) {
        guard msg.service == "vital-command" else { return }

        let server = DiscoveredServer(
            service: msg.service,
            name: msg.name,
            ip: msg.ip,
            port: msg.port,
            version: msg.version,
            lastSeen: Date()
        )

        if let idx = discoveredServers.firstIndex(where: { $0.id == server.id }) {
            discoveredServers[idx] = server
        } else {
            discoveredServers.append(server)
        }

        discoveredServers.removeAll { !$0.isRecentlyActive && Date().timeIntervalSince($0.lastSeen) > 30 }
    }

    /// Fallback: scan common ports on the local subnet
    func scanSubnet() async {
        guard let ip = getWiFiAddress() else { return }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return }
        let subnet = parts[0...2].joined(separator: ".")

        await withTaskGroup(of: DiscoveredServer?.self) { group in
            for i in 1...254 {
                let targetIP = "\(subnet).\(i)"
                group.addTask {
                    await self.probeServer(ip: targetIP, port: 3000)
                }
            }

            for await result in group {
                if let server = result {
                    addOrUpdateServer(from: BroadcastMessage(
                        service: server.service,
                        name: server.name,
                        ip: server.ip,
                        port: server.port,
                        version: server.version
                    ))
                }
            }
        }
    }

    private func probeServer(ip: String, port: Int) async -> DiscoveredServer? {
        let urlString = "http://\(ip):\(port)/api/discover"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            let msg = try JSONDecoder().decode(BroadcastMessage.self, from: data)
            guard msg.service == "vital-command" else { return nil }
            return DiscoveredServer(
                service: msg.service, name: msg.name, ip: msg.ip, port: msg.port, version: msg.version, lastSeen: Date()
            )
        } catch {
            return nil
        }
    }

    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
}
