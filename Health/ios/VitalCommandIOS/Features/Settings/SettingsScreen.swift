import SwiftUI
import AuthenticationServices
import VitalCommandMobileCore

struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var discovery = ServerDiscoveryService()
    @State private var showLogoutConfirmation = false
    @State private var syncStatus: SyncStatusResponse?
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var syncMessage: String?
    @State private var serverStatuses: [String: Bool] = [:]
    @State private var checkingServers: Set<String> = []
    @State private var modelStatus: AIModelStatusResponse?
    @State private var isLoadingModelStatus = false
    @State private var isSwitchingProvider = false
    @State private var availableUsers: [UserListItem] = []
    @State private var isLoadingUsers = false
    @State private var currentUserId: String?
    @State private var isSwitchingUser = false
    @State private var isCreatingTestUser = false
    @State private var canSwitchUser = false
    @State private var isLinkingApple = false
    @State private var appleLinkMessage: String?

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
                            if let email = user.email, email.isEmpty == false {
                                Text(email)
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

                    if !user.authProviders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(user.authProviders) { provider in
                                    StatusBadge(
                                        text: providerLabel(provider.provider),
                                        tint: provider.provider == .apple ? .black : (provider.provider == .phone ? .blue : tealColor)
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if let user = authManager.currentUser {
                Section("账号安全") {
                    if user.hasAppleLinked {
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo")
                                .foregroundStyle(.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple 账号已绑定")
                                    .font(.subheadline.weight(.medium))
                                Text(user.email ?? "后续可直接使用 Apple 登录当前账号")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("绑定 Apple 后，同一用户在不同节点登录时会更稳定，也能避免设备号和 Apple 账号分裂成不同用户。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleLink(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(isLinkingApple)

                        if isLinkingApple {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("正在绑定 Apple 账号...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let appleLinkMessage {
                        Text(appleLinkMessage)
                            .font(.caption)
                            .foregroundStyle(user.hasAppleLinked ? .green : .secondary)
                    }
                }
            }

            Section("HealthAI") {
                Text("HealthAI 展示首页结论、趋势、报告和数据同步状态。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if isLoadingModelStatus && modelStatus == nil {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("正在检测...").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if let status = modelStatus {
                    ForEach(status.providers) { provider in
                        Button {
                            guard provider.isConfigured, !isSwitchingProvider else { return }
                            Task { await switchProvider(to: provider.name) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: provider.isPrimary && provider.isConfigured ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(provider.isPrimary && provider.isConfigured ? tealColor : (provider.isConfigured ? Color.secondary : Color.gray.opacity(0.3)))
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(provider.label)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(provider.isConfigured ? .primary : .tertiary)
                                        if provider.isPrimary && provider.isConfigured {
                                            Text("使用中")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(tealColor, in: Capsule())
                                        }
                                    }
                                    if let model = provider.model {
                                        Text(model)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("未配置")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                if isSwitchingProvider && status.activeProvider != provider.name && provider.isPrimary {
                                    ProgressView().scaleEffect(0.6)
                                } else {
                                    Circle()
                                        .fill(provider.isConfigured ? Color.green : Color.gray.opacity(0.4))
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!provider.isConfigured)
                    }

                    if isSwitchingProvider {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("切换中...").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button("检测 AI 模型") {
                        Task { await loadModelStatus() }
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("AI 模型选择")
            } footer: {
                Text("点击已配置的模型切换为首选。未配置的模型不可选择。")
            }

            // Server address section with status
            Section("服务地址") {
                HStack {
                    TextField(AppSettingsStore.currentRemoteServerURL, text: $settings.serverURLString)
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
                serverSwitchRow(name: "远端主服务器 (16)", url: AppSettingsStore.currentRemoteServerURL)

                // Saved servers (excluding built-in ones)
                ForEach(settings.savedServers.filter { saved in
                    saved.url != AppSettingsStore.currentRemoteServerURL
                }) { server in
                    serverSwitchRow(name: server.name, url: server.url)
                }
                .onDelete { indexSet in
                    let filtered = settings.savedServers.filter { saved in
                        saved.url != AppSettingsStore.currentRemoteServerURL
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
                        settings.rememberDiscoveredServerURLs([server.urlString])
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

                if let syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
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

            if canSwitchUser {
            Section {
                if isLoadingUsers {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("加载中...").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if !availableUsers.isEmpty {
                    ForEach(availableUsers) { user in
                        Button {
                            guard user.id != currentUserId, !isSwitchingUser else { return }
                            Task { await performSwitchUser(to: user.id) }
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(user.id == currentUserId
                                            ? LinearGradient(colors: [tealColor, Color(hex: "#0d5263") ?? .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            : LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                        .frame(width: 36, height: 36)
                                    Text(String((user.displayName ?? "U").prefix(1)))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(user.id == currentUserId ? .white : .secondary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(user.displayName ?? "未命名")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if user.id == "user-self" {
                                            Text("🛠️ 种子数据")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.orange, in: Capsule())
                                        }
                                    }
                                    Text("ID: \(String(user.id.suffix(6)))")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                if isSwitchingUser && user.id != currentUserId {
                                    // show nothing for non-target rows during switch
                                } else if user.id == currentUserId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(tealColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(user.id == currentUserId || isSwitchingUser)
                    }

                    if isSwitchingUser {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("切换中...").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button("加载账号列表") {
                        Task { await loadUsers() }
                    }
                    .font(.subheadline)
                }

                Button {
                    Task { await createTestUser() }
                } label: {
                    HStack(spacing: 6) {
                        if isCreatingTestUser {
                            ProgressView().scaleEffect(0.7)
                        }
                        Label("创建测试账号", systemImage: "person.badge.plus")
                    }
                    .font(.subheadline)
                }
                .disabled(isCreatingTestUser)
            } header: {
                Text("账号切换（开发）")
            } footer: {
                Text("切换用户后首页数据会刷新为该用户的数据。\"种子数据\" 为开发者默认账号。")
            }
            } // end if canSwitchUser

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
                await loadModelStatus()
                await loadUsers()
            }
        }
        .onReceive(discovery.$discoveredServers) { servers in
            settings.rememberDiscoveredServerURLs(servers.map(\.urlString))
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

    // MARK: - Account Switching

    private func loadUsers() async {
        guard !isLoadingUsers else { return }
        isLoadingUsers = true
        defer { isLoadingUsers = false }
        do {
            let client = try settings.makeClient(token: authManager.token)
            let response = try await client.fetchUsers()
            availableUsers = response.users
            currentUserId = response.currentUserId
            canSwitchUser = response.canSwitchUser ?? false
        } catch {
            // Silently fail
        }
    }

    private func performSwitchUser(to targetUserId: String) async {
        guard !isSwitchingUser else { return }
        isSwitchingUser = true
        defer { isSwitchingUser = false }
        do {
            let client = try settings.makeClient(token: authManager.token)
            let response = try await client.switchUser(SwitchUserRequest(targetUserId: targetUserId))
            authManager.switchUser(token: response.token, user: response.user)
            currentUserId = response.user.id
            settings.markHealthDataChanged()
        } catch {
            // Could show error
        }
    }

    private func createTestUser() async {
        guard !isCreatingTestUser else { return }
        isCreatingTestUser = true
        defer { isCreatingTestUser = false }
        do {
            let client = try settings.makeClient(token: authManager.token)
            let randomDeviceId = UUID().uuidString
            let response = try await client.deviceLogin(
                DeviceLoginRequest(deviceId: randomDeviceId, deviceLabel: "测试账号")
            )
            // Switch to the new user
            authManager.switchUser(token: response.token, user: response.user)
            currentUserId = response.user.id
            settings.markHealthDataChanged()
            // Reload user list
            await loadUsers()
        } catch {
            // Could show error
        }
    }

    private func handleAppleLink(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .failure(error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            appleLinkMessage = error.localizedDescription

        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleLinkMessage = "Apple 绑定返回格式无效，请重试。"
                return
            }

            Task {
                isLinkingApple = true
                defer { isLinkingApple = false }

                do {
                    let payload = try AppleAuthorizationPayload(credential: credential)
                    try await authManager.linkAppleIdentity(payload, using: settings)
                    appleLinkMessage = "Apple 账号已成功绑定到当前 HealthAI 账号。"
                } catch {
                    appleLinkMessage = error.localizedDescription
                }
            }
        }
    }

    private func providerLabel(_ provider: AuthProviderKind) -> String {
        switch provider {
        case .device:
            return "设备"
        case .phone:
            return "手机号"
        case .apple:
            return "Apple"
        }
    }

    // MARK: - AI Model Status

    private func loadModelStatus() async {
        guard !isLoadingModelStatus else { return }
        isLoadingModelStatus = true
        defer { isLoadingModelStatus = false }
        if let client = try? settings.makeClient(token: authManager.token) {
            modelStatus = try? await client.fetchModelStatus()
        }
    }

    private func switchProvider(to provider: String) async {
        guard !isSwitchingProvider else { return }
        isSwitchingProvider = true
        defer { isSwitchingProvider = false }
        if let client = try? settings.makeClient(token: authManager.token) {
            if let updated = try? await client.setPreferredProvider(provider) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    modelStatus = updated
                }
            }
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
            let reachable = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            serverStatuses[urlString] = reachable
        } catch {
            serverStatuses[urlString] = false
        }
    }

    private func checkAllServers() async {
        let urls = Set(
            [AppSettingsStore.currentRemoteServerURL]
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
        syncMessage = nil
        do {
            let client = try settings.makeClient(token: authManager.token)
            let response = try await client.triggerSync(peerURLs: knownPeerURLs())
            // Reload full sync status after trigger completes
            await loadSyncStatus()
            syncMessage = response.message
            if response.successfulPeers == 0 {
                syncError = response.failedPeers > 0 ? response.message : nil
            }
        } catch {
            syncError = error.localizedDescription
        }
        isSyncing = false
    }

    private func knownPeerURLs() -> [String] {
        let current = normalizedServerURL(settings.trimmedServerURLString)
        let candidates = Set(
            discovery.discoveredServers.map(\.urlString)
            + settings.recentDiscoveredServerURLs
            + settings.savedServers.map(\.url)
            + [AppSettingsStore.currentRemoteServerURL]
        )

        return candidates
            .map(normalizedServerURL)
            .filter { !$0.isEmpty && $0 != current }
            .sorted()
    }

    private func normalizedServerURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            return ""
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? trimmed
    }

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterBasic = ISO8601DateFormatter()

    private func formatRelativeTime(_ isoString: String) -> String {
        guard let date = Self.isoFormatterFractional.date(from: isoString) ?? Self.isoFormatterBasic.date(from: isoString) else {
            return isoString
        }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        return "\(Int(interval / 86400))天前"
    }
}
