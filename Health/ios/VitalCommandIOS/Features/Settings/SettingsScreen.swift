import SwiftUI
import VitalCommandMobileCore

struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var discovery = ServerDiscoveryService()
    @State private var showLogoutConfirmation = false
    @State private var syncStatus: SyncStatusResponse?
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var serverStatuses: [String: Bool] = [:]
    @State private var checkingServers: Set<String> = []

    private let tealColor = Color(hex: "#0f766e") ?? .teal

    var body: some View {
        Form {
            // User info section
            if let user = authManager.currentUser {
                Section("账号信息") {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#0f766e") ?? .teal, Color(hex: "#0d5263") ?? .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)

                            Text(String(user.displayName.prefix(1)))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.subheadline.weight(.semibold))
                            if let phone = user.phoneNumber {
                                Text(maskPhoneNumber(phone))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text("ID: \(String(user.id.suffix(6)))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("HealthAI") {
                Text("HealthAI 展示首页结论、趋势、报告和数据同步状态。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Server address section with status
            Section("服务地址") {
                HStack {
                    TextField("http://10.8.140.209:3000/", text: $settings.serverURLString)
                        .appURLTextEntry()

                    if checkingServers.contains(settings.trimmedServerURLString) {
                        ProgressView().scaleEffect(0.7)
                    } else if let reachable = serverStatuses[settings.trimmedServerURLString] {
                        Circle()
                            .fill(reachable ? .green : .red)
                            .frame(width: 10, height: 10)
                    }
                }

                Button("检测连接") {
                    Task { await checkServer(settings.trimmedServerURLString) }
                }

                Button("保存当前服务器") {
                    settings.saveCurrentServer()
                }

                Text("iPhone 连接开发机时，请使用电脑的局域网 IP；不要填 localhost。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Quick server switching
            Section("快速切换") {
                // Built-in servers
                serverSwitchRow(name: "主服务器 (209)", url: "http://10.8.140.209:3000/")
                serverSwitchRow(name: "备用服务器 (16)", url: "http://10.8.144.16:3001/")

                // Saved servers (excluding built-in ones)
                ForEach(settings.savedServers.filter { saved in
                    saved.url != "http://10.8.140.209:3000/" && saved.url != "http://10.8.144.16:3001/"
                }) { server in
                    serverSwitchRow(name: server.name, url: server.url)
                }
                .onDelete { indexSet in
                    let filtered = settings.savedServers.filter { saved in
                        saved.url != "http://10.8.140.209:3000/" && saved.url != "http://10.8.144.16:3001/"
                    }
                    for index in indexSet {
                        settings.removeSavedServer(filtered[index])
                    }
                }

                Button {
                    Task { await checkAllServers() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("检测所有服务器")
                    }
                    .font(.subheadline)
                }
            }

            Section("局域网服务发现") {
                if discovery.isScanning {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("正在扫描局域网...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(discovery.discoveredServers) { server in
                    Button {
                        settings.serverURLString = server.urlString
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(server.isRecentlyActive ? .green : .orange)
                                        .frame(width: 8, height: 8)
                                    Text(server.name)
                                        .font(.subheadline.weight(.medium))
                                }
                                Text(server.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.serverURLString == server.urlString {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if discovery.discoveredServers.isEmpty && !discovery.isScanning {
                    Text("未发现局域网服务")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    if discovery.isScanning {
                        discovery.stopScanning()
                    } else {
                        discovery.startScanning()
                        Task { await discovery.scanSubnet() }
                    }
                } label: {
                    Label(
                        discovery.isScanning ? "停止扫描" : "扫描局域网",
                        systemImage: discovery.isScanning ? "stop.circle" : "antenna.radiowaves.left.and.right"
                    )
                }
            }

            Section("数据同步") {
                HStack(spacing: 10) {
                    Circle()
                        .fill(syncStatusColor)
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(syncStatusText)
                            .font(.subheadline.weight(.medium))
                        if let status = syncStatus {
                            Text("服务器 ID: \(String(status.serverId.prefix(8)))...")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if let status = syncStatus {
                        Text("\(status.peers.count) 节点")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }

                if let status = syncStatus, !status.peers.isEmpty {
                    ForEach(status.peers) { peer in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.name)
                                    .font(.caption.weight(.medium))
                                Text(peer.url)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let lastSync = peer.lastSyncAt {
                                Text(formatRelativeTime(lastSync))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("未同步")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                if let error = syncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await triggerManualSync() }
                } label: {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Label(
                            isSyncing ? "同步中..." : "立即同步",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }
                .disabled(isSyncing)
            }

            Section("使用说明") {
                Text("首页用于快速查看核心结论和行动提示。")
                Text("趋势页可以查看完整图表。")
                Text("报告页用于阅读周报和月报。")
                Text("数据页可以上传文件并同步 Apple 健康。")
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("退出登录")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            discovery.startScanning()
            Task {
                await loadSyncStatus()
                await checkAllServers()
            }
        }
        .onDisappear { discovery.stopScanning() }
        .navigationTitle("设置")
        .alert("确认退出？", isPresented: $showLogoutConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出登录", role: .destructive) {
                authManager.logout()
            }
        } message: {
            Text("退出后需要重新验证身份登录")
        }
    }

    // MARK: - Server switch row

    @ViewBuilder
    private func serverSwitchRow(name: String, url: String) -> some View {
        Button {
            settings.serverURLString = url
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Connection status
                if checkingServers.contains(url) {
                    ProgressView().scaleEffect(0.6)
                } else if let reachable = serverStatuses[url] {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(reachable ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(reachable ? "在线" : "离线")
                            .font(.caption2)
                            .foregroundStyle(reachable ? .green : .red)
                    }
                }

                // Active indicator
                if settings.trimmedServerURLString == url {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tealColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Server health check

    private func checkServer(_ urlString: String) async {
        checkingServers.insert(urlString)
        defer { checkingServers.remove(urlString) }

        let healthURL = urlString.hasSuffix("/")
            ? urlString + "api/health"
            : urlString + "/api/health"

        guard let url = URL(string: healthURL) else {
            serverStatuses[urlString] = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let reachable = (response as? HTTPURLResponse).map { (200...499).contains($0.statusCode) } ?? false
            serverStatuses[urlString] = reachable
        } catch {
            serverStatuses[urlString] = false
        }
    }

    private func checkAllServers() async {
        let urls = Set(
            ["http://10.8.140.209:3000/", "http://10.8.144.16:3001/"]
            + settings.savedServers.map(\.url)
            + [settings.trimmedServerURLString]
        )
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { await checkServer(url) }
            }
        }
    }

    private func maskPhoneNumber(_ phone: String) -> String {
        guard phone.count >= 7 else { return phone }
        let start = phone.prefix(3)
        let end = phone.suffix(4)
        return "\(start)****\(end)"
    }

    // MARK: - Sync helpers

    private var syncStatusColor: Color {
        guard let status = syncStatus else { return .gray }
        if status.peers.isEmpty { return .gray }
        let recentSync = status.recentLogs.first { $0.status == "success" }
        if recentSync != nil { return .green }
        return .orange
    }

    private var syncStatusText: String {
        guard let status = syncStatus else { return "加载中..." }
        if status.peers.isEmpty { return "无已知节点" }
        let successLogs = status.recentLogs.filter { $0.status == "success" }
        if let latest = successLogs.first {
            return "已同步 · \(formatRelativeTime(latest.finishedAt))"
        }
        return "\(status.peers.count) 个节点待同步"
    }

    private func loadSyncStatus() async {
        do {
            let client = try settings.makeClient(token: authManager.token)
            syncStatus = try await client.fetchSyncStatus()
            syncError = nil
        } catch {
            // Silently fail — sync status is informational
        }
    }

    private func triggerManualSync() async {
        isSyncing = true
        syncError = nil
        do {
            let client = try settings.makeClient(token: authManager.token)
            let _ = try await client.triggerSync()
            // Reload full sync status after trigger completes
            await loadSyncStatus()
        } catch {
            syncError = error.localizedDescription
        }
        isSyncing = false
    }

    private func formatRelativeTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return isoString
        }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        return "\(Int(interval / 86400))天前"
    }
}
