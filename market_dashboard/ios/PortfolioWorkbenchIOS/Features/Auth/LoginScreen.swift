import SwiftUI
import PortfolioWorkbenchMobileCore

struct LoginScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var isSubmitting = false
    @State private var statusMessage: String = "正在连接你的投资账户…"
    @State private var hasTriggeredAutoLogin = false
    @State private var hasAttemptedServerRecovery = false
    @State private var isShowingServerConfig = false
    @State private var showManualActions = false

    var body: some View {
        ZStack {
            BootBrandBackdrop()

            VStack {
                BootBrandWordmark(logoSize: 86, titleSize: 33, subtitleSize: 11)

                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(0.78))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 2)
            }
            .offset(y: -112)

            VStack(spacing: 12) {
                Spacer()

                if isSubmitting || settings.isRestoringDeviceSession {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.14)
                }

                Text(displayStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.90))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                VStack(spacing: 10) {
                    if shouldShowRetryActions {
                        Button {
                            Task { await attemptAutomaticLogin() }
                        } label: {
                            Text("重新尝试")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrokerPalette.cyan)
                        .foregroundStyle(Color.black)
                        .disabled(isSubmitting || settings.isRestoringDeviceSession)

                        if settings.hasProvisionedDeviceAccount {
                            Button {
                                Task { await loginWithDevice(requireLocalAuthentication: false) }
                            } label: {
                                Text("跳过生物识别继续")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(BrokerPalette.teal)
                            .disabled(isSubmitting || settings.isRestoringDeviceSession)
                        }

                    }
                    Button {
                        isShowingServerConfig = true
                    } label: {
                        Text("配置服务器")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(BrokerPalette.gold)
                }
                .padding(.top, 2)
                .padding(.horizontal, 20)

                if let message = settings.connectionStatusMessage,
                   message.contains("未找到可连接的服务器") || message.contains("暂无可探测服务器地址") {
                    Text("如果自动切换失败，可以直接点上方“配置服务器”手工切换。")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.66))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Text(settings.trimmedServerURLString)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await attemptAutomaticLogin()
        }
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !settings.isAuthenticated {
                showManualActions = true
            }
        }
        .onChange(of: settings.connectionStatusMessage) { _, newValue in
            guard let newValue, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            statusMessage = newValue
        }
        .sheet(isPresented: $isShowingServerConfig) {
            ServerConnectionConfigSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private var shouldShowRetryActions: Bool {
        let lowered = displayStatusMessage.lowercased()
        return showManualActions
            || lowered.contains("失败")
            || lowered.contains("错误")
            || lowered.contains("超时")
            || lowered.contains("无法")
            || lowered.contains("未找到可连接的服务器")
            || lowered.contains("暂未发现可用服务器")
            || lowered.contains("暂无可探测服务器地址")
    }

    private var displayStatusMessage: String {
        if let message = settings.connectionStatusMessage,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return statusMessage
    }

    private func attemptAutomaticLogin() async {
        guard !hasTriggeredAutoLogin || shouldShowRetryActions else {
            return
        }
        hasTriggeredAutoLogin = true

        if settings.canAttemptAutomaticDeviceLogin {
            statusMessage = "正在恢复设备会话…"
            await settings.restoreDeviceSessionIfPossible()
            if settings.isAuthenticated {
                showManualActions = false
                statusMessage = "已恢复会话。"
                return
            }
        }

        let shouldUseBiometric = settings.supportsBiometricUnlock
            && settings.hasProvisionedDeviceAccount
            && settings.canAttemptAutomaticDeviceLogin

        statusMessage = shouldUseBiometric
            ? "请完成 \(settings.biometryType.displayName) 验证…"
            : "正在登录设备账号…"
        await loginWithDevice(requireLocalAuthentication: shouldUseBiometric)
    }

    private func loginWithDevice(requireLocalAuthentication: Bool) async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response = try await performDeviceLogin(requireLocalAuthentication: requireLocalAuthentication)
            let isNewDevice = response.deviceCredentials?.isNewDevice == true
            if isNewDevice {
                statusMessage = "设备绑定完成，正在进入首页…"
            } else if requireLocalAuthentication {
                statusMessage = "验证通过，正在进入首页…"
            } else {
                statusMessage = "登录成功，正在进入首页…"
            }
            showManualActions = false
        } catch {
            if !hasAttemptedServerRecovery, await settings.recoverServerConnectionIfNeeded() {
                hasAttemptedServerRecovery = true
                statusMessage = settings.connectionStatusMessage ?? "已切换到可用服务器，正在重新登录…"
                do {
                    let response = try await performDeviceLogin(requireLocalAuthentication: false)
                    let isNewDevice = response.deviceCredentials?.isNewDevice == true
                    if isNewDevice {
                        statusMessage = "设备绑定完成，正在进入首页…"
                    } else {
                        statusMessage = "已切换到可用服务器，正在进入首页…"
                    }
                    showManualActions = false
                    return
                } catch {
                    statusMessage = friendlyErrorMessage(error)
                    showManualActions = true
                    return
                }
            }
            statusMessage = friendlyErrorMessage(error)
            showManualActions = true
        }
    }

    private func performDeviceLogin(requireLocalAuthentication: Bool) async throws -> MobileSessionPayload {
        try await settings.loginWithDeviceAccount(requireLocalAuthentication: requireLocalAuthentication)
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("timed out") || lowered.contains("timeout") {
            return "连接超时，已尝试自动切换服务器，请稍后重试。"
        }
        if lowered.contains("could not connect")
            || lowered.contains("offline")
            || lowered.contains("network")
            || lowered.contains("connection") {
            return "当前网络连接异常，请检查网络后重试。"
        }
        return error.localizedDescription
    }
}

struct ServerConnectionConfigSheet: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var discovery = ServerDiscoveryService()
    @Environment(\.dismiss) private var dismiss
    @State private var isApplying = false
    @State private var helperMessage: String = "如果当前默认服务器不可用，可以自动探测或手动切换到可连接的地址。"
    @State private var statusItems: [ServerStatusItem] = []
    @State private var isRefreshingStatus = false

    var body: some View {
        NavigationStack {
            AppBackdrop {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionPanel(
                            title: "服务器配置",
                            subtitle: "先试自动探测；如果仍无可用服务器，再手工填写服务地址。"
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("http://10.8.144.16:8008/", text: $settings.serverURLString)
                                    .appURLTextEntry()
                                    .padding(14)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .foregroundStyle(BrokerPalette.ink)

                                HStack(spacing: 10) {
                                    Button {
                                        settings.selectServerURL(AppSettingsStore.defaultServerURLString, name: "远端默认服务器", rememberSelection: true)
                                        helperMessage = "已切换到远端默认服务器。"
                                    } label: {
                                        Text("远端默认")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(BrokerPalette.cyan)

                                    Button {
                                        Task { await autoRecover() }
                                    } label: {
                                        Text(discovery.isScanning ? "探测中…" : "自动探测")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(BrokerPalette.gold)
                                    .foregroundStyle(Color.black)
                                    .disabled(isApplying)
                                }

                                Button {
                                    Task { await saveAndRetry() }
                                } label: {
                                    Text("保存并重新连接")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(BrokerPalette.teal)
                                .foregroundStyle(Color.black)
                                .disabled(isApplying)

                                Text(helperMessage)
                                    .font(.footnote)
                                    .foregroundStyle(BrokerPalette.muted)
                            }
                        }

                        SectionPanel(
                            title: "网络状态",
                            subtitle: "这里会显示当前地址和远端默认地址的实时连通情况。"
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Button {
                                        Task { await refreshServerStatuses() }
                                    } label: {
                                        HStack(spacing: 8) {
                                            if isRefreshingStatus {
                                                ProgressView()
                                                    .tint(BrokerPalette.cyan)
                                            } else {
                                                Image(systemName: "dot.radiowaves.left.and.right")
                                            }
                                            Text(isRefreshingStatus ? "检查中…" : "刷新状态")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(BrokerPalette.cyan)

                                    TagBadge(
                                        text: discovery.discoveredServers.isEmpty ? "已发现 0 台" : "已发现 \(discovery.discoveredServers.count) 台",
                                        tint: discovery.discoveredServers.isEmpty ? BrokerPalette.gold : BrokerPalette.green
                                    )
                                }

                                ForEach(statusItems) { item in
                                    serverStatusRow(item)
                                }

                                if statusItems.isEmpty {
                                    Text("当前还没有状态数据，点击“刷新状态”后会检查当前地址与远端默认地址。")
                                        .font(.footnote)
                                        .foregroundStyle(BrokerPalette.muted)
                                }
                            }
                        }

                        SectionPanel(
                            title: "探测结果",
                            subtitle: "如果这台 Mac 或远端机器在当前网络可达，会出现在这里。"
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                if discovery.isScanning {
                                    ProgressView()
                                        .tint(BrokerPalette.cyan)
                                }

                                if discovery.discoveredServers.isEmpty {
                                    Text(discovery.statusMessage ?? "点击“自动探测”后，系统会扫描当前局域网中的可用服务。")
                                        .font(.footnote)
                                        .foregroundStyle(BrokerPalette.muted)
                                } else {
                                    ForEach(discovery.discoveredServers) { server in
                                        Button {
                                            settings.selectServerURL(server.urlString, name: server.name, rememberSelection: true)
                                            helperMessage = "已切换到 \(server.name)。"
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(server.name)
                                                    .foregroundStyle(BrokerPalette.ink)
                                                Text(server.urlString)
                                                    .font(.footnote)
                                                    .foregroundStyle(BrokerPalette.muted)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(BrokerPalette.cyan)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("配置服务器")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onChange(of: discovery.discoveredServers) { _, servers in
                guard let first = servers.first else { return }
                if settings.trimmedServerURLString != first.urlString {
                    settings.selectServerURL(first.urlString, name: first.name, rememberSelection: true)
                    helperMessage = "已自动切换到 \(first.name)。"
                }
            }
            .task(id: settings.trimmedServerURLString) {
                discovery.stopScanning()
                discovery.startScan(currentServerURLString: settings.trimmedServerURLString)
                await refreshServerStatuses()
            }
        }
    }

    private struct ServerStatusItem: Identifiable {
        let name: String
        let url: String
        let state: String
        let detail: String
        let tint: Color

        var id: String { name + url }
    }

    @ViewBuilder
    private func serverStatusRow(_ item: ServerStatusItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrokerPalette.ink)

                TagBadge(text: item.state, tint: item.tint)

                Spacer()
            }

            Text(item.url)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(BrokerPalette.muted)
                .lineLimit(1)

            Text(item.detail)
                .font(.footnote)
                .foregroundStyle(BrokerPalette.muted)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BrokerPalette.line, lineWidth: 1)
        )
    }

    private func autoRecover() async {
        isApplying = true
        defer { isApplying = false }
        helperMessage = "正在自动探测并切换可用服务器…"
        if await settings.recoverServerConnectionIfNeeded() {
            helperMessage = settings.connectionStatusMessage ?? "已找到可用服务器。"
            await refreshServerStatuses()
            return
        }
        helperMessage = "未发现可用服务器，请手工填写运行服务的机器地址。"
        await refreshServerStatuses()
    }

    private func saveAndRetry() async {
        isApplying = true
        defer { isApplying = false }
        settings.saveCurrentServer()
        helperMessage = "已保存当前地址，正在重新连接…"
        _ = await settings.recoverServerConnectionIfNeeded()
        await refreshServerStatuses()
    }

    private func refreshServerStatuses() async {
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }

        let candidates = [
            ("当前地址", settings.trimmedServerURLString),
            ("远端默认", AppSettingsStore.defaultServerURLString)
        ]

        var rows: [ServerStatusItem] = []
        for (name, url) in candidates {
            guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            rows.append(await probeStatus(name: name, url: url))
        }
        statusItems = rows
    }

    private func probeStatus(name: String, url: String) async -> ServerStatusItem {
        guard let baseURL = URL(string: url) else {
            return ServerStatusItem(
                name: name,
                url: url,
                state: "地址异常",
                detail: "URL 格式无效，请检查 http/https 和端口。",
                tint: BrokerPalette.red
            )
        }

        let startedAt = Date()
        var request = URLRequest(url: baseURL.appending(path: "api/mobile/discovery"))
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return ServerStatusItem(
                    name: name,
                    url: url,
                    state: "不可用",
                    detail: "服务返回异常状态码。",
                    tint: BrokerPalette.red
                )
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(MobileServerDiscoveryPayload.self, from: data)
            let latency = max(Int(Date().timeIntervalSince(startedAt) * 1000), 1)
            return ServerStatusItem(
                name: name,
                url: url,
                state: "在线",
                detail: "\(payload.appName) · \(payload.detectedLanIp ?? payload.bindHost):\(payload.port) · \(latency)ms",
                tint: BrokerPalette.green
            )
        } catch {
            return ServerStatusItem(
                name: name,
                url: url,
                state: "离线",
                detail: "当前未连通该地址：\(error.localizedDescription)",
                tint: BrokerPalette.orange
            )
        }
    }
}
