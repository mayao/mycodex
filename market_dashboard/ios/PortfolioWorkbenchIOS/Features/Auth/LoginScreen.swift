import SwiftUI
import PortfolioWorkbenchMobileCore

struct LoginScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var isSubmitting = false
    @State private var statusMessage: String?
    @State private var isShowingServerSwitcher = false
    @State private var serverDraft = ""

    var body: some View {
        AppBackdrop {
            ScrollView {
                VStack(spacing: 18) {
                    Spacer(minLength: 24)
                    headerSection
                    accessSection
                    serverAccessory
                    if let statusMessage, !statusMessage.isEmpty {
                        statusBanner
                    }
                    Spacer(minLength: 12)
                }
                .padding(18)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $isShowingServerSwitcher) {
            serverSwitcherSheet
        }
        .task(id: settings.trimmedServerURLString) {
            await settings.restoreDeviceSessionIfPossible()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(BrokerPalette.panelStrong.opacity(0.96))
                    .frame(width: 92, height: 92)

                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(BrokerPalette.cyan)
            }

            Text("MyInvAI")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(BrokerPalette.ink)
            Text("打开你的投资组合、持仓详情和 AI 判断。")
                .font(.subheadline)
                .foregroundStyle(BrokerPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var accessSection: some View {
        SectionPanel(title: "进入应用", subtitle: accessSubtitle) {
            VStack(alignment: .leading, spacing: 12) {
                if settings.isRestoringDeviceSession {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(BrokerPalette.cyan)
                        Text("正在恢复当前设备的专属会话…")
                            .font(.footnote)
                            .foregroundStyle(BrokerPalette.muted)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await loginWithDevice(requireLocalAuthentication: false) }
                    } label: {
                        HStack {
                            if isSubmitting || settings.isRestoringDeviceSession {
                                ProgressView()
                                    .tint(Color.black)
                            } else {
                                Image(systemName: settings.hasProvisionedDeviceAccount ? "iphone.gen3" : "person.crop.circle.badge.plus")
                            }
                            Text(deviceLoginButtonTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrokerPalette.cyan)
                    .foregroundStyle(Color.black)
                    .disabled(isSubmitting || settings.isRestoringDeviceSession)

                    if settings.supportsBiometricUnlock && settings.hasProvisionedDeviceAccount {
                        Button {
                            Task { await loginWithDevice(requireLocalAuthentication: true) }
                        } label: {
                            Text("\(settings.biometryType.displayName) 继续")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BrokerPalette.teal)
                        .disabled(isSubmitting || settings.isRestoringDeviceSession)
                    }
                }

                Text(deviceAccessHint)
                    .font(.footnote)
                    .foregroundStyle(BrokerPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var serverAccessory: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("服务器")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrokerPalette.muted)
                Text(serverDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrokerPalette.ink)
                Text(settings.trimmedServerURLString)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(BrokerPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                serverDraft = settings.trimmedServerURLString
                isShowingServerSwitcher = true
            } label: {
                Text("切换服务器")
            }
            .buttonStyle(.bordered)
            .tint(BrokerPalette.teal)

            if !isUsingDefaultServer {
                Button {
                    settings.selectServerURL(
                        preferredDefaultServerURL,
                        name: "默认服务器",
                        rememberSelection: true
                    )
                    statusMessage = "已切换到默认服务器。"
                } label: {
                    Text("默认")
                }
                .buttonStyle(.bordered)
                .tint(BrokerPalette.cyan)
            }
        }
        .padding(.horizontal, 2)
    }

    private var statusBanner: some View {
        Text(statusMessage ?? "")
            .font(.footnote)
            .foregroundStyle(statusColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var deviceLoginButtonTitle: String {
        if settings.isRestoringDeviceSession {
            return "正在恢复"
        }
        return settings.hasProvisionedDeviceAccount ? "继续进入" : "启用并进入"
    }

    private var accessSubtitle: String {
        if settings.isRestoringDeviceSession {
            return "已检测到当前设备，正在尝试恢复之前的专属会话。"
        }
        return settings.hasProvisionedDeviceAccount
            ? "当前设备已绑定，可直接继续进入。"
            : "首次使用会为当前设备创建一个专属账户。"
    }

    private var deviceAccessHint: String {
        if settings.supportsBiometricUnlock {
            return settings.biometricUnlockEnabled
                ? "已开启 \(settings.biometryType.displayName) 本机解锁。"
                : "登录成功后可启用 \(settings.biometryType.displayName) 本机解锁。"
        }
        return "当前设备未检测到可用的 Face ID / Touch ID，仍可直接使用设备登录。"
    }

    private var isUsingDefaultServer: Bool {
        settings.trimmedServerURLString == preferredDefaultServerURL
    }

    private var preferredDefaultServerURL: String {
        settings.suggestedBuildServerURLString ?? AppSettingsStore.defaultServerURLString
    }

    private var serverDisplayName: String {
        if isUsingDefaultServer {
            return "默认服务器"
        }
        guard let host = URL(string: settings.trimmedServerURLString)?.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "自定义服务器"
        }
        return host
    }

    private var statusColor: Color {
        let message = statusMessage ?? ""
        return message.contains("失败") || message.contains("错误") || message.contains("无效")
            ? BrokerPalette.red
            : BrokerPalette.teal
    }

    private var serverSwitcherSheet: some View {
        NavigationStack {
            AppBackdrop {
                ScrollView {
                    VStack(spacing: 16) {
                        SectionPanel(title: "服务器地址", subtitle: "默认地址已经预填，也可以切到其他服务器。") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField(preferredDefaultServerURL, text: $serverDraft)
                                    .appURLTextEntry()
                                    .padding(14)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                                HStack(spacing: 10) {
                                    Button {
                                        serverDraft = preferredDefaultServerURL
                                    } label: {
                                        Text("填入默认地址")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(BrokerPalette.teal)

                                    Button {
                                        applyServerDraft()
                                    } label: {
                                        Text("保存并使用")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(BrokerPalette.cyan)
                                    .foregroundStyle(Color.black)
                                }
                            }
                        }

                        if let suggestedBuildURL = settings.suggestedBuildServerURLString, !suggestedBuildURL.isEmpty {
                            SectionPanel(title: "本机测试地址", subtitle: "当前构建已注入你这台 Mac 的最新局域网 IP。") {
                                Button {
                                    settings.selectServerURL(suggestedBuildURL, name: "本机测试地址", rememberSelection: true)
                                    statusMessage = "已切换到本机测试地址。"
                                    isShowingServerSwitcher = false
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("当前构建本机地址")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(BrokerPalette.ink)
                                            Text(suggestedBuildURL)
                                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                                .foregroundStyle(BrokerPalette.muted)
                                                .multilineTextAlignment(.leading)
                                        }

                                        Spacer()

                                        if settings.trimmedServerURLString == suggestedBuildURL {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(BrokerPalette.cyan)
                                        }
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !settings.savedServers.isEmpty {
                            SectionPanel(title: "最近服务器", subtitle: "点一下即可切换。") {
                                VStack(spacing: 10) {
                                    ForEach(settings.savedServers) { server in
                                        Button {
                                            settings.selectServerURL(server.url, name: server.name, rememberSelection: true)
                                            statusMessage = "已切换到 \(server.name)。"
                                            isShowingServerSwitcher = false
                                        } label: {
                                            HStack(alignment: .top, spacing: 12) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(server.name)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(BrokerPalette.ink)
                                                    Text(server.url)
                                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                                        .foregroundStyle(BrokerPalette.muted)
                                                        .multilineTextAlignment(.leading)
                                                }

                                                Spacer()

                                                if settings.trimmedServerURLString == server.url {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(BrokerPalette.cyan)
                                                }
                                            }
                                            .padding(14)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("切换服务器")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        isShowingServerSwitcher = false
                    }
                    .tint(BrokerPalette.cyan)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func loginWithDevice(requireLocalAuthentication: Bool) async {
        await withBusyState {
            let response = try await settings.loginWithDeviceAccount(requireLocalAuthentication: requireLocalAuthentication)
            let isNewDevice = response.deviceCredentials?.isNewDevice == true
            let hasPassword = !(settings.deviceAccountProfile.defaultPassword ?? "").isEmpty
            statusMessage = isNewDevice
                ? "设备已完成绑定。\(hasPassword ? "备用密码已保存，可在设置页查看。" : "")"
                : (requireLocalAuthentication ? "已通过 \(settings.biometryType.displayName) 登录。" : (response.message ?? "登录成功。"))
        }
    }

    private func applyServerDraft() {
        settings.selectServerURL(serverDraft, rememberSelection: true)
        statusMessage = "已切换到 \(settings.trimmedServerURLString)"
        isShowingServerSwitcher = false
    }

    private func withBusyState(_ operation: @escaping () async throws -> Void) async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
