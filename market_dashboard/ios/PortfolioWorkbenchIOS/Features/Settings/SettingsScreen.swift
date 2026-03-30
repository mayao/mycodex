import Combine
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PortfolioWorkbenchMobileCore

struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var dashboardStore: PortfolioDashboardStore
    @StateObject private var discovery = ServerDiscoveryService()

    @FocusState private var isEditingURL: Bool
    @State private var isImporting = false
    @State private var isUploading = false
    @State private var isRefreshing = false
    @State private var isLoggingInApple = false
    @State private var isLoggingInDevice = false
    @State private var refreshMessage: String?
    @State private var uploadTarget: StatementUploadTarget?
    @State private var uploadIssues: [String: String] = [:]
    @State private var aiServiceStatus: AIServiceStatusPayload?
    @State private var isLoadingAIServiceStatus = false
    @State private var aiModelDrafts: [AppAIProvider: String] = [:]
    @State private var didLoadAISettings = false
    @State private var longbridgeDiagnosticsReport = LongbridgeDiagnosticsStore.shared.report()

    var body: some View {
        NavigationStack {
            AppBackdrop {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        accountSection
                        connectionSection
                        dataStatusSection
                        cacheSection
                        aiModelSection
                        #if DEBUG
                        debugSection
                        #endif
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("设置")
            .appInlineNavigationTitle()
            .task {
                await loadAIServiceStatus()
                loadAISettingsIfNeeded()
                longbridgeDiagnosticsReport = LongbridgeDiagnosticsStore.shared.report()
            }
            .onDisappear {
                discovery.stopScanning()
            }
            .onReceive(NotificationCenter.default.publisher(for: .longbridgeDiagnosticsDidChange)) { notification in
                if let report = notification.object as? String {
                    longbridgeDiagnosticsReport = report
                } else {
                    longbridgeDiagnosticsReport = LongbridgeDiagnosticsStore.shared.report()
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf, .image]) { result in
                switch result {
                case let .success(url):
                    Task { await upload(url: url) }
                case let .failure(error):
                    refreshMessage = error.localizedDescription
                }
            }
        }
    }

    private var accountSection: some View {
        SectionPanel(title: "账户", subtitle: "当前设备已登录到你的个人投资数据。") {
            VStack(alignment: .leading, spacing: 12) {
                if let currentUser = settings.effectiveCurrentUser {
                    LabelValueRow(label: "显示名称", value: currentUser.displayName)
                    LabelValueRow(label: "用户 ID", value: currentUser.userId)
                    LabelValueRow(label: "登录方式", value: authProviderLabel(currentUser.authProvider))
                    if settings.isLocalOnlySession {
                        LabelValueRow(label: "会话模式", value: "本机身份")
                    }
                    if currentUser.authProvider == "device" {
                        LabelValueRow(label: "设备名称", value: settings.deviceAccountProfile.deviceLabel)
                        if let defaultPassword = settings.deviceAccountProfile.defaultPassword, !defaultPassword.isEmpty {
                            LabelValueRow(label: "默认密码", value: defaultPassword)
                        }
                        LabelValueRow(
                            label: "本机解锁",
                            value: settings.biometricUnlockEnabled ? "已启用 \(settings.biometryType.displayName)" : "未启用"
                        )
                    }
                    if let phoneNumberMasked = currentUser.phoneNumberMasked, !phoneNumberMasked.isEmpty {
                        LabelValueRow(label: "手机号", value: phoneNumberMasked)
                    }

                    HStack(spacing: 8) {
                        TagBadge(text: "已登录", tint: BrokerPalette.cyan)
                        TagBadge(text: authProviderLabel(currentUser.authProvider), tint: BrokerPalette.teal)
                        TagBadge(text: "个人数据", tint: BrokerPalette.gold)
                    }

                    biometricLoginButton

                    if currentUser.authProvider == "device" {
                        if settings.supportsBiometricUnlock {
                            Button {
                                Task { await toggleBiometricUnlock() }
                            } label: {
                                Text(settings.biometricUnlockEnabled ? "关闭 \(settings.biometryType.displayName) 解锁" : "启用 \(settings.biometryType.displayName) 解锁")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(BrokerPalette.teal)
                        } else {
                            Text("当前设备未检测到可用的 Face ID / Touch ID，可继续使用设备账号登录。")
                                .font(.footnote)
                                .foregroundStyle(BrokerPalette.muted)
                        }
                    }

                    Button {
                        Task { await logout() }
                    } label: {
                        Text("退出登录")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrokerPalette.red)
                    .foregroundStyle(Color.black)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前未登录。默认建议先用 Apple ID 登录；如果你更想沿用这台设备的本机身份，也可以继续用设备账号。")
                            .font(.subheadline)
                            .foregroundStyle(BrokerPalette.muted)

                        AppleSignInControl(
                            onStart: {
                                refreshMessage = "正在请求 Apple 授权…"
                            },
                            onSuccess: { userIdentifier, displayName, emailAddress in
                                Task {
                                    await loginWithAppleAccount(
                                        userIdentifier: userIdentifier,
                                        displayName: displayName,
                                        emailAddress: emailAddress
                                    )
                                }
                            },
                            onFailure: { message in
                                refreshMessage = message
                            }
                        )
                        .disabled(isLoggingInApple || isLoggingInDevice)

                        biometricLoginButton
                    }
                }
            }
        }
    }

    private var connectionSection: some View {
        SectionPanel(title: "服务连接", subtitle: "支持远端与本机双部署，可手工切换多个服务器地址。") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前连接：\(settings.trimmedServerURLString)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(BrokerPalette.ink)
                        .lineLimit(1)

                    if let suggestedBuildURL = settings.suggestedBuildServerURLString, !suggestedBuildURL.isEmpty {
                        Text("本机构建：\(suggestedBuildURL)")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(BrokerPalette.muted)
                            .lineLimit(1)
                    }
                }

                if let suggestedBuildURL = settings.suggestedBuildServerURLString, !suggestedBuildURL.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("当前 Mac 局域网地址")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(BrokerPalette.muted)
                                Text(suggestedBuildURL)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundStyle(BrokerPalette.ink)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = suggestedBuildURL
                                refreshMessage = "已复制当前 Mac 地址"
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(BrokerPalette.cyan)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("这是安装脚本写入手机的本机服务入口。如果自动探测没有找到，就直接用这个地址。")
                            .font(.footnote)
                            .foregroundStyle(BrokerPalette.muted)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                TextField(AppSettingsStore.defaultServerURLString, text: $settings.serverURLString)
                    .appURLTextEntry()
                    .focused($isEditingURL)
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(BrokerPalette.ink)

                if let suggestedBuildURL = settings.suggestedBuildServerURLString, !suggestedBuildURL.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前构建地址")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BrokerPalette.muted)

                        serverRow(
                            title: "本机默认",
                            subtitle: "\(suggestedBuildURL) · 安装脚本会把当前 Mac 的局域网地址写入这里",
                            isSelected: settings.trimmedServerURLString == suggestedBuildURL,
                            tint: BrokerPalette.gold
                        ) {
                            settings.selectServerURL(suggestedBuildURL, name: "本机默认", rememberSelection: true)
                            refreshMessage = "已切换到当前构建地址"
                        } trailing: {
                            Button {
                                UIPasteboard.general.string = suggestedBuildURL
                                refreshMessage = "已复制本机地址"
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(BrokerPalette.cyan)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    Task { await refreshNow() }
                } label: {
                    HStack {
                        if isRefreshing {
                            ProgressView()
                                .tint(Color.black)
                        } else {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        Text(isRefreshing ? "连接中" : "保存并刷新")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BrokerPalette.cyan)
                .foregroundStyle(Color.black)

                HStack(spacing: 10) {
                    Button {
                        settings.saveCurrentServer()
                        refreshMessage = "已保存 \(settings.trimmedServerURLString)"
                    } label: {
                        Label("保存当前地址", systemImage: "bookmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(BrokerPalette.teal)

                    Button {
                        if discovery.isScanning {
                            discovery.stopScanning()
                            refreshMessage = "已停止自动探测。"
                        } else {
                            discovery.startScan(currentServerURLString: settings.trimmedServerURLString)
                            refreshMessage = nil
                        }
                    } label: {
                        Label(
                            discovery.isScanning ? "停止探测" : "自动探测",
                            systemImage: discovery.isScanning ? "stop.circle" : "antenna.radiowaves.left.and.right"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(BrokerPalette.gold)
                }

                if !quickServerEndpoints.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("常用地址")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BrokerPalette.muted)

                        ForEach(quickServerEndpoints, id: \.url) { endpoint in
                            serverRow(
                                title: endpoint.name,
                                subtitle: endpoint.url,
                                isSelected: settings.trimmedServerURLString == endpoint.url,
                                tint: BrokerPalette.gold
                            ) {
                                settings.selectServerURL(endpoint.url, name: endpoint.name, rememberSelection: true)
                                refreshMessage = "已切换到 \(endpoint.name)"
                            }
                        }
                    }
                }

                if let suggestedBuildURL = settings.suggestedBuildServerURLString, !suggestedBuildURL.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("本机测试地址")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BrokerPalette.muted)

                        serverRow(
                            title: "当前构建的本机最新 IP",
                            subtitle: "\(suggestedBuildURL) · 重新安装 App 时会自动刷新这台 Mac 的局域网地址",
                            isSelected: settings.trimmedServerURLString == suggestedBuildURL,
                            tint: BrokerPalette.gold
                        ) {
                            settings.selectServerURL(suggestedBuildURL, name: "本机测试地址", rememberSelection: true)
                            refreshMessage = "已切换到本机测试地址"
                        }
                    }
                }

                if !settings.savedServers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已保存地址")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BrokerPalette.muted)

                        ForEach(settings.savedServers) { server in
                            serverRow(
                                title: server.name,
                                subtitle: server.url,
                                isSelected: settings.trimmedServerURLString == server.url,
                                tint: BrokerPalette.teal
                            ) {
                                settings.selectServerURL(server.url)
                                refreshMessage = "已切换到 \(server.url)"
                            } trailing: {
                                Button {
                                    settings.removeSavedServer(server)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(BrokerPalette.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("自动探测结果")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BrokerPalette.muted)
                        if discovery.isScanning {
                            ProgressView()
                                .tint(BrokerPalette.cyan)
                                .scaleEffect(0.8)
                        }
                    }

                    if !discovery.discoveredServers.isEmpty {
                        ForEach(discovery.discoveredServers) { server in
                            serverRow(
                                title: server.name,
                                subtitle: "\(server.urlString) · \(server.appName)",
                                isSelected: settings.trimmedServerURLString == server.urlString,
                                tint: BrokerPalette.cyan
                            ) {
                                settings.selectServerURL(server.urlString, name: server.name, rememberSelection: true)
                                refreshMessage = "已切换到 \(server.name)"
                            }
                        }
                    } else {
                        Text(discovery.statusMessage ?? "点击“自动探测”后，会扫描可连接的部署机器。")
                            .font(.footnote)
                            .foregroundStyle(BrokerPalette.muted)
                    }
                }

                if let refreshMessage {
                    Text(refreshMessage)
                        .font(.footnote)
                        .foregroundStyle(refreshMessage.contains("失败") || refreshMessage.contains("错误") ? BrokerPalette.red : BrokerPalette.teal)
                }
            }
        }
    }

    private var aiModelSection: some View {
        SectionPanel(title: "AI 模型", subtitle: "选择模型并查看每个 provider 的可用状态。") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("首选模型", selection: aiPrimaryProviderBinding) {
                    ForEach(AppAIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("首选失败时自动回退", isOn: aiFallbackEnabledBinding)
                    .tint(BrokerPalette.cyan)

                Button {
                    Task { await loadAIServiceStatus(probe: true, autoSelectFastest: true) }
                } label: {
                    HStack {
                        if isLoadingAIServiceStatus {
                            ProgressView()
                                .tint(Color.black)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isLoadingAIServiceStatus ? "刷新中" : "刷新服务端模型状态")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BrokerPalette.gold)
                .foregroundStyle(Color.black)

                ForEach(AppAIProvider.allCases) { provider in
                    aiProviderCard(provider)
                }
            }
        }
    }

    private func aiProviderCard(_ provider: AppAIProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.headline)
                        .foregroundStyle(BrokerPalette.ink)
                }

                Spacer()

                if settings.aiPrimaryProvider == provider {
                    TagBadge(text: "首选", tint: BrokerPalette.cyan)
                }
                if fastestProvider == provider.kind {
                    TagBadge(text: "最快", tint: BrokerPalette.teal)
                }
                if let status = aiServiceStatus?.providers.first(where: { $0.provider == provider.kind }) {
                    TagBadge(text: aiAccessStateLabel(status.accessState), tint: aiAccessStateTint(status.accessState))
                } else {
                    TagBadge(text: isLoadingAIServiceStatus ? "检查中" : "待刷新", tint: BrokerPalette.gold)
                }
            }

            TextField("模型 ID", text: aiModelBinding(for: provider))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(BrokerPalette.ink)

            if let status = aiServiceStatus?.providers.first(where: { $0.provider == provider.kind }) {
                VStack(alignment: .leading, spacing: 8) {
                    LabelValueRow(label: "服务端 Key", value: credentialSourceLabel(status.credentialSource))
                    LabelValueRow(label: "访问状态", value: status.accessMessage, valueColor: aiAccessStateTint(status.accessState))
                    if let preset = status.preset, provider == .kimi {
                        LabelValueRow(label: "Kimi 通道", value: kimiPresetLabel(preset))
                    }
                    if let checkedAt = status.checkedAt, !checkedAt.isEmpty {
                        LabelValueRow(label: "最近检查", value: checkedAt)
                    }
                    if let latency = status.latencyMs, latency > 0 {
                        LabelValueRow(label: "延迟", value: "\(latency) ms")
                    }
                }
            } else {
                Text("服务端状态未刷新。")
                    .font(.footnote)
                    .foregroundStyle(BrokerPalette.muted)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func serverRow<Trailing: View>(
        title: String,
        subtitle: String,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isSelected ? BrokerPalette.green : tint)
                        .frame(width: 8, height: 8)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrokerPalette.ink)
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(BrokerPalette.muted)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BrokerPalette.green)
            } else {
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(tint)
            }

            trailing()
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: action)
    }

    private var quickServerEndpoints: [SavedServerEndpoint] {
        var endpoints: [SavedServerEndpoint] = [
            SavedServerEndpoint(name: "远端部署", url: AppSettingsStore.remoteDefaultServerURLString),
        ]
        if let suggestedBuildURL = settings.suggestedBuildServerURLString, !suggestedBuildURL.isEmpty {
            endpoints.append(SavedServerEndpoint(name: "本机部署", url: suggestedBuildURL))
        }
        for discovered in discovery.discoveredServers.prefix(3) {
            endpoints.append(SavedServerEndpoint(name: discovered.name, url: discovered.urlString))
        }
        endpoints.append(contentsOf: settings.savedServers)
        var seen = Set<String>()
        return endpoints.filter { endpoint in
            guard !endpoint.url.isEmpty else { return false }
            if seen.contains(endpoint.url) {
                return false
            }
            seen.insert(endpoint.url)
            return true
        }
    }

    private var dataStatusSection: some View {
        SectionPanel(title: "数据状态", subtitle: "查看每个券商最近一次的数据来源与解析状态。") {
            VStack(alignment: .leading, spacing: 12) {
                if let payload = dashboardPayload, !payload.statementSources.isEmpty {
                    ForEach(brokerGroups(from: payload.statementSources)) { group in
                        brokerGroupCard(group)
                    }
                } else {
                    Text("暂时还没有结单来源信息。先连接服务并同步一次数据后，这里会显示各券商的状态。")
                        .font(.subheadline)
                        .foregroundStyle(BrokerPalette.muted)
                }

                if let refreshMessage, !refreshMessage.isEmpty {
                    Text(refreshMessage)
                        .font(.footnote)
                        .foregroundStyle(refreshMessage.contains("失败") || refreshMessage.contains("错误") ? BrokerPalette.red : BrokerPalette.teal)
                }
            }
        }
    }

    private struct StatementUploadTarget: Equatable {
        let accountId: String
        let broker: String
        let statementType: String
    }

    private struct BrokerSourceGroup: Identifiable {
        let broker: String
        let sources: [MobileStatementSource]

        var id: String { broker }
    }

    private struct BrokerSourceSummary {
        let label: String
        let tint: Color
        let latestUpdateText: String?
    }

    private func brokerGroups(from sources: [MobileStatementSource]) -> [BrokerSourceGroup] {
        let grouped = Dictionary(grouping: sources) { $0.broker }
        return grouped.keys.sorted().map { broker in
            let sources = (grouped[broker] ?? []).sorted { lhs, rhs in
                if lhs.statementType != rhs.statementType {
                    return lhs.statementType < rhs.statementType
                }
                return lhs.accountId < rhs.accountId
            }
            return BrokerSourceGroup(broker: broker, sources: sources)
        }
    }

    private func brokerGroupCard(_ group: BrokerSourceGroup) -> some View {
        let summary = brokerSourceSummary(group.sources)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(group.broker)
                    .font(.headline)
                    .foregroundStyle(BrokerPalette.ink)

                TagBadge(text: summary.label, tint: summary.tint)

                Spacer()

                if let latest = summary.latestUpdateText, !latest.isEmpty {
                    Text(latest)
                        .font(.caption)
                        .foregroundStyle(BrokerPalette.muted)
                }
            }

            ForEach(group.sources) { source in
                statementSourceCard(source)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrokerPalette.line, lineWidth: 1)
        )
    }

    private func statementSourceCard(_ source: MobileStatementSource) -> some View {
        let isUploadingThis = isUploading && uploadTarget?.accountId == source.accountId
        let sourceMode = statementSourceModeLabel(source.sourceMode)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.fileName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrokerPalette.ink)
                        .lineLimit(1)

                    Text(statementTypeLabel(source.statementType))
                        .font(.caption)
                        .foregroundStyle(BrokerPalette.muted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        TagBadge(text: sourceMode.label, tint: sourceMode.tint)
                        TagBadge(
                            text: loadStatusLabel(source.loadStatus),
                            tint: BrokerPalette.sourceStatus(source.loadStatus)
                        )
                    }

                    Text(source.accountId.suffix(8))
                        .font(.caption.monospaced())
                        .foregroundStyle(BrokerPalette.muted)
                }
            }

            if let statementDate = source.statementDate, !statementDate.isEmpty {
                LabelValueRow(label: "结单日期", value: statementDate)
            }
            if let uploadedAt = source.uploadedAt, !uploadedAt.isEmpty {
                LabelValueRow(label: "最近上传", value: uploadedAt)
            }
            LabelValueRow(
                label: "数据来源",
                value: availabilityLabel(for: source),
                valueColor: availabilityTint(for: source)
            )
            if let availabilityNote = source.availabilityNote, !availabilityNote.isEmpty {
                Text(availabilityNote)
                    .font(.footnote)
                    .foregroundStyle(BrokerPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let issue = source.issue, !issue.isEmpty {
                LabelValueRow(
                    label: source.loadStatus == "error" ? "异常" : "提示",
                    value: issue,
                    valueColor: source.loadStatus == "error" ? BrokerPalette.red : BrokerPalette.gold
                )
            }

            if let issue = uploadIssues[source.accountId], !issue.isEmpty {
                Text(issue)
                    .font(.footnote)
                    .foregroundStyle(BrokerPalette.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                beginStatementUpload(for: source)
            } label: {
                HStack {
                    if isUploadingThis {
                        ProgressView()
                            .tint(BrokerPalette.cyan)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isUploadingThis ? "上传中" : "更新该结单")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(BrokerPalette.cyan)
            .disabled(isUploading)
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BrokerPalette.line, lineWidth: 1)
        )
    }

    private func beginStatementUpload(for source: MobileStatementSource) {
        uploadTarget = StatementUploadTarget(
            accountId: source.accountId,
            broker: source.broker,
            statementType: source.statementType
        )
        refreshMessage = nil
        isImporting = true
    }

    private func brokerSourceSummary(_ sources: [MobileStatementSource]) -> BrokerSourceSummary {
        let total = max(sources.count, 1)
        let parsedCount = sources.filter { $0.loadStatus == "parsed" }.count
        let cacheCount = sources.filter { $0.loadStatus == "cache" }.count
        let errorCount = sources.filter { $0.loadStatus == "error" }.count
        let parsedPayloadCount = sources.filter { $0.availabilityStatus == "parsed_payload" }.count
        let hasWarning = sources.contains { source in
            if source.loadStatus == "cache" {
                return true
            }
            if source.availabilityStatus == "parsed_payload" {
                return true
            }
            return false
        }

        let label: String
        let tint: Color
        if errorCount > 0 {
            label = "存在异常"
            tint = BrokerPalette.red
        } else if cacheCount > 0 {
            label = "使用缓存 \(cacheCount)/\(total)"
            tint = BrokerPalette.gold
        } else if parsedPayloadCount > 0 {
            label = "已解析数据 \(parsedPayloadCount)/\(total)"
            tint = BrokerPalette.cyan
        } else if parsedCount == total {
            label = "全部已更新"
            tint = BrokerPalette.green
        } else if parsedCount > 0 {
            label = "已更新 \(parsedCount)/\(total)"
            tint = BrokerPalette.green
        } else if hasWarning {
            label = "可用但有提醒"
            tint = BrokerPalette.gold
        } else {
            label = "待检查"
            tint = BrokerPalette.cyan
        }

        return BrokerSourceSummary(
            label: label,
            tint: tint,
            latestUpdateText: latestUpdateText(sources)
        )
    }

    private func latestUpdateText(_ sources: [MobileStatementSource]) -> String? {
        let candidates = sources.compactMap { source in
            if let uploadedAt = source.uploadedAt, !uploadedAt.isEmpty {
                return uploadedAt
            }
            if let statementDate = source.statementDate, !statementDate.isEmpty {
                return statementDate
            }
            return nil
        }
        return candidates.sorted().last
    }

    private func statementTypeLabel(_ value: String) -> String {
        switch value {
        case "tiger_activity":
            return "Tiger · Activity"
        case "ib_daily":
            return "IB · Daily"
        case "futu_monthly_us":
            return "Futu · US Monthly"
        case "futu_monthly_hk":
            return "Futu · HK Monthly"
        case "longbridge_daily":
            return "Longbridge · Daily"
        default:
            return value
        }
    }

    private func statementSourceModeLabel(_ value: String) -> (label: String, tint: Color) {
        switch value {
        case "upload":
            return ("上传替代", BrokerPalette.cyan)
        case "default":
            return ("默认来源", BrokerPalette.teal)
        default:
            return (value, BrokerPalette.teal)
        }
    }

    private func availabilityLabel(for source: MobileStatementSource) -> String {
        switch source.availabilityStatus {
        case "original":
            return "源文件可用"
        case "parsed_payload":
            return "使用已解析数据"
        case "cache":
            return "使用缓存快照"
        case "missing":
            return "缺少源文件"
        default:
            if source.fileExists {
                return "源文件可用"
            }
            if source.parsedPayloadExists == true {
                return "使用已解析数据"
            }
            if source.loadStatus == "cache" {
                return "使用缓存快照"
            }
            return "待检查"
        }
    }

    private func availabilityTint(for source: MobileStatementSource) -> Color {
        switch source.availabilityStatus {
        case "original":
            return BrokerPalette.green
        case "parsed_payload":
            return BrokerPalette.cyan
        case "cache":
            return BrokerPalette.gold
        case "missing":
            return source.loadStatus == "error" ? BrokerPalette.red : BrokerPalette.gold
        default:
            if source.loadStatus == "error" {
                return BrokerPalette.red
            }
            if source.loadStatus == "cache" {
                return BrokerPalette.gold
            }
            return BrokerPalette.cyan
        }
    }

    private var cacheSection: some View {
        SectionPanel(title: "同步状态") {
            VStack(alignment: .leading, spacing: 12) {
                SectionStatusRow(
                    lastUpdatedAt: dashboardStore.lastUpdatedAt,
                    isRefreshing: dashboardStore.isRefreshing || isRefreshing || isUploading || isLoadingAIServiceStatus,
                    isShowingCachedSnapshot: dashboardStore.isShowingCachedSnapshot
                )

                LabelValueRow(
                    label: "最近更新",
                    value: NumberFormatters.relativeTimestamp(dashboardStore.lastUpdatedAt)
                )
                Text("首页、持仓、账户和个股详情会优先显示最近一次同步结果。")
                    .font(.subheadline)
                    .foregroundStyle(BrokerPalette.ink)
                Text("手动刷新后，会用最新数据更新当前页面。")
                    .font(.subheadline)
                    .foregroundStyle(BrokerPalette.ink)

                HStack(spacing: 10) {
                    Button {
                        Task { await refreshDashboard() }
                    } label: {
                        Label("刷新行情", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(BrokerPalette.cyan)

                    Button {
                        Task { await refreshAI() }
                    } label: {
                        Label("刷新洞察", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(BrokerPalette.gold)
                }
            }
        }
    }

    private func refreshNow() async {
        isRefreshing = true
        isEditingURL = false

        guard settings.canAccessRemoteData else {
            refreshMessage = "当前是本机身份，服务端刷新会在连接服务器后再执行。"
            isRefreshing = false
            return
        }

        do {
            let client = try settings.makeClient()
            await dashboardStore.load(using: client, force: true)
            await loadAIServiceStatus(probe: true, autoSelectFastest: true)
            refreshMessage = "已连接 \(settings.trimmedServerURLString)"
        } catch {
            refreshMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    private func refreshDashboard() async {
        guard settings.canAccessRemoteData else {
            dashboardStore.setNotice("当前是本机身份，先展示手机缓存。")
            return
        }
        do {
            let client = try settings.makeClient()
            await dashboardStore.refreshVisible(using: client)
        } catch {
            dashboardStore.setError(error.localizedDescription)
        }
    }

    private func refreshAI() async {
        guard settings.canAccessRemoteData else {
            dashboardStore.setNotice("当前是本机身份，AI 页已切换到 Longbridge 与本地缓存。")
            return
        }
        do {
            let client = try settings.makeClient()
            await dashboardStore.refreshAI(using: client, force: true)
        } catch {
            dashboardStore.setError(error.localizedDescription)
        }
    }

    private var fastestProvider: AIProviderKind? {
        aiServiceStatus?.providers
            .filter { $0.accessState == "success" && ($0.latencyMs ?? 0) > 0 }
            .min(by: { ($0.latencyMs ?? Int.max) < ($1.latencyMs ?? Int.max) })?
            .provider
    }

    private func appProvider(from kind: AIProviderKind) -> AppAIProvider {
        switch kind {
        case .anthropic:
            return .anthropic
        case .kimi:
            return .kimi
        case .gemini:
            return .gemini
        }
    }

    private func loadAIServiceStatus(probe: Bool = false, autoSelectFastest: Bool = false) async {
        guard settings.canAccessRemoteData else {
            aiServiceStatus = nil
            return
        }

        isLoadingAIServiceStatus = true
        defer { isLoadingAIServiceStatus = false }

        do {
            let client = try settings.makeClient()
            let status = try await client.fetchAIServiceStatus(probe: probe)
            aiServiceStatus = status
            guard autoSelectFastest else { return }

            let candidates = status.providers
                .filter { $0.accessState == "success" && ($0.latencyMs ?? 0) > 0 }
                .sorted { ($0.latencyMs ?? Int.max) < ($1.latencyMs ?? Int.max) }
            guard let winner = candidates.first else {
                refreshMessage = "模型测速完成：暂无可用 provider，已保留当前默认模型。"
                return
            }
            let fastest = appProvider(from: winner.provider)
            if settings.aiPrimaryProvider != fastest {
                settings.setAIPrimaryProvider(fastest)
                refreshMessage = "模型测速完成：已自动切换到 \(fastest.displayName)（\(winner.latencyMs ?? 0) ms）。"
            } else {
                refreshMessage = "模型测速完成：\(fastest.displayName) 仍是最快（\(winner.latencyMs ?? 0) ms）。"
            }
        } catch {
            aiServiceStatus = nil
            refreshMessage = error.localizedDescription
        }
    }

    private func logout() async {
        if settings.canAccessRemoteData {
            do {
                let client = try settings.makeClient()
                _ = try await client.logout()
            } catch {
                refreshMessage = error.localizedDescription
            }
        }
        settings.logoutCurrentSession()
    }

    private func toggleBiometricUnlock() async {
        do {
            if settings.biometricUnlockEnabled {
                settings.disableBiometricUnlock()
                refreshMessage = "已关闭本机生物识别解锁。"
            } else {
                try await settings.enableBiometricUnlock()
                refreshMessage = "已启用 \(settings.biometryType.displayName) 解锁。"
            }
        } catch {
            refreshMessage = error.localizedDescription
        }
    }

    private func loginWithDeviceAccount() async {
        isLoggingInDevice = true
        defer { isLoggingInDevice = false }
        do {
            _ = try await settings.loginWithDeviceAccount(requireLocalAuthentication: false)
            refreshMessage = "设备账号登录成功。"
            do {
                let client = try settings.makeClient()
                await dashboardStore.refreshVisible(using: client)
            } catch {
                // Keep login success; dashboard can refresh later.
            }
        } catch {
            refreshMessage = error.localizedDescription
        }
    }

    private func loginWithAppleAccount(
        userIdentifier: String,
        displayName: String?,
        emailAddress: String?
    ) async {
        isLoggingInApple = true
        defer { isLoggingInApple = false }
        do {
            _ = try await settings.loginWithAppleAccount(
                userIdentifier: userIdentifier,
                displayName: displayName,
                emailAddress: emailAddress
            )
            refreshMessage = settings.isLocalOnlySession ? "已进入本机 Apple 身份。" : "Apple ID 登录成功。"
            if settings.canAccessRemoteData {
                do {
                    let client = try settings.makeClient()
                    await dashboardStore.refreshVisible(using: client)
                } catch {
                    // Keep login success; dashboard can refresh later.
                }
            }
        } catch {
            refreshMessage = error.localizedDescription
        }
    }

    private var dashboardPayload: MobileDashboardPayload? {
        dashboardStore.state.value
    }

    private var aiPrimaryProviderBinding: Binding<AppAIProvider> {
        Binding(
            get: { settings.aiPrimaryProvider },
            set: { settings.setAIPrimaryProvider($0) }
        )
    }

    private var aiFallbackEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.aiFallbacksEnabled },
            set: { settings.setAIFallbacksEnabled($0) }
        )
    }

    private func aiModelBinding(for provider: AppAIProvider) -> Binding<String> {
        Binding(
            get: { aiModelDrafts[provider] ?? settings.aiModelIdentifier(for: provider) },
            set: { newValue in
                aiModelDrafts[provider] = newValue
                settings.setAIModelIdentifier(newValue, for: provider)
            }
        )
    }

    private func aiAccessStateLabel(_ state: String) -> String {
        switch state {
        case "success":
            return "最近成功"
        case "ready":
            return "已配置"
        case "error":
            return "最近失败"
        case "missing_key":
            return "缺少 Key"
        default:
            return "待检查"
        }
    }

    private func aiAccessStateTint(_ state: String) -> Color {
        switch state {
        case "success", "ready":
            return BrokerPalette.green
        case "error":
            return BrokerPalette.red
        case "missing_key":
            return BrokerPalette.gold
        default:
            return BrokerPalette.cyan
        }
    }

    private func credentialSourceLabel(_ source: String) -> String {
        switch source {
        case "service_config":
            return "服务端配置文件"
        case "environment":
            return "服务端环境变量"
        case "request":
            return "当前请求"
        default:
            return "未配置"
        }
    }

    private func kimiPresetLabel(_ preset: String) -> String {
        switch preset {
        case "kimi_coding":
            return "Kimi Coding 兼容通道"
        default:
            return "Moonshot 通道"
        }
    }

    private func loadAISettingsIfNeeded() {
        guard !didLoadAISettings else {
            return
        }
        for provider in AppAIProvider.allCases {
            aiModelDrafts[provider] = settings.aiModelIdentifier(for: provider)
        }
        didLoadAISettings = true
    }

    private func upload(url: URL) async {
        guard let target = uploadTarget else {
            refreshMessage = "请先选择要更新的券商结单。"
            return
        }

        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            refreshMessage = "正在读取 \(url.lastPathComponent)…"
            let fileData = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/pdf"
            let client = try settings.makeClient()

            isUploading = true
            refreshMessage = "正在上传并校验结单…"
            let response = try await client.uploadStatement(
                accountID: target.accountId,
                fileName: fileName,
                mimeType: mimeType,
                fileData: fileData,
                broker: target.broker,
                statementType: target.statementType
            )
            if response.routingAction == "rerouted",
               let broker = response.resolvedBroker,
               let accountID = response.resolvedAccountId {
                refreshMessage = "\(response.message) 自动路由目标：\(broker) / \(accountID)"
            } else {
                refreshMessage = response.message
            }
            uploadIssues[target.accountId] = nil
            if let payload = response.payload {
                dashboardStore.apply(payload, message: "新结单已接入，正在后台同步最新行情…")
                await dashboardStore.load(
                    using: client,
                    force: false,
                    fast: false,
                    allowLoadedRefresh: true,
                    loadingMessage: "新结单已接入，正在更新最新数据…"
                )
            } else {
                await dashboardStore.load(
                    using: client,
                    force: true,
                    fast: false,
                    allowLoadedRefresh: true
                )
            }
        } catch {
            refreshMessage = error.localizedDescription
            uploadIssues[target.accountId] = error.localizedDescription
        }

        isUploading = false
        uploadTarget = nil
    }

    private func loadStatusLabel(_ status: String?) -> String {
        switch status {
        case "parsed":
            return "已更新"
        case "cache":
            return "最近结果"
        case "error":
            return "异常"
        default:
            return "待检查"
        }
    }

    private func authProviderLabel(_ provider: String) -> String {
        switch provider {
        case "device":
            return "设备账号"
        case "phone":
            return "手机号"
        case "wechat":
            return "微信授权"
        case "owner":
            return "本机账户"
        case "apple":
            return "Apple ID"
        case "apple-local":
            return "本机身份"
        default:
            return provider
        }
    }

    #if DEBUG
    private var debugSection: some View {
        SectionPanel(title: "调试状态", subtitle: "用于排查当前会话恢复和 Longbridge 拉数。") {
            VStack(alignment: .leading, spacing: 8) {
                LabelValueRow(label: "是否已登录", value: settings.isAuthenticated ? "是" : "否")
                LabelValueRow(
                    label: "会话 token",
                    value: settings.sessionToken?.isEmpty == false ? "len \(settings.sessionToken?.count ?? 0)" : "nil"
                )
                LabelValueRow(
                    label: "当前用户",
                    value: settings.effectiveCurrentUser.map { "\($0.authProvider):\($0.userId)" } ?? "nil"
                )
                LabelValueRow(label: "Longbridge", value: settings.longbridgeSessionState.rawValue)
                LabelValueRow(label: "Longbridge 端点", value: settings.longbridgeEndpointLabel)

                HStack(spacing: 8) {
                    Button {
                        Task { await dashboardStore.refreshLocalFirst(using: settings) }
                    } label: {
                        Label(
                            dashboardStore.isRefreshing ? "诊断中…" : "重新跑 Longbridge 诊断",
                            systemImage: "waveform.path.ecg"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(BrokerPalette.teal)
                    .disabled(dashboardStore.isRefreshing || !settings.canUseLongbridgeSession)

                    Button {
                        UIPasteboard.general.string = longbridgeDiagnosticsReport
                        refreshMessage = longbridgeDiagnosticsReport.isEmpty ? "当前没有可复制的诊断日志。" : "已复制 Longbridge 诊断日志。"
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(BrokerPalette.gold)

                    Button {
                        LongbridgeDiagnosticsStore.shared.clear()
                        refreshMessage = "已清空 Longbridge 诊断日志。"
                    } label: {
                        Label("清空", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(BrokerPalette.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Longbridge 拉数诊断")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BrokerPalette.muted)
                    Text(longbridgeDiagnosticsReport.isEmpty ? "暂无诊断日志。启动 App 或点击上方按钮后，这里会显示真机可读的 Longbridge 拉数过程。" : longbridgeDiagnosticsReport)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(BrokerPalette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
    #endif

    private var biometricLoginButton: some View {
        Button {
            Task { await performBiometricLoginAction() }
        } label: {
            HStack {
                if isLoggingInDevice {
                    ProgressView().tint(Color.black)
                } else {
                    Image(systemName: settings.supportsBiometricUnlock ? "faceid" : "person.crop.circle.badge.checkmark")
                }
                Text(deviceLoginButtonTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(BrokerPalette.teal)
        .foregroundStyle(Color.black)
        .disabled(isLoggingInDevice)
    }

    private var deviceLoginButtonTitle: String {
        if isLoggingInDevice {
            return "验证中…"
        }
        if settings.isAuthenticated {
            if !settings.supportsBiometricUnlock {
                return "当前会话已登录"
            }
            return settings.biometricUnlockEnabled ? "使用 Face ID 解锁" : "启用 Face ID 解锁"
        }
        return settings.supportsBiometricUnlock ? "使用 Face ID 登录" : "使用设备账号登录"
    }

    private func performBiometricLoginAction() async {
        do {
            isLoggingInDevice = true
            defer { isLoggingInDevice = false }

            if settings.isAuthenticated {
                guard settings.supportsBiometricUnlock else {
                    refreshMessage = "当前设备不支持 Face ID / Touch ID，已保持当前会话。"
                    return
                }
                if settings.biometricUnlockEnabled {
                    try await settings.unlockActiveSession()
                    refreshMessage = "已通过 Face ID 解锁当前会话。"
                } else {
                    try await settings.enableBiometricUnlock()
                    refreshMessage = "已启用 Face ID 解锁。"
                }
            } else {
                let payload = try await settings.loginWithDeviceAccount(
                    requireLocalAuthentication: settings.supportsBiometricUnlock
                )
                refreshMessage = payload.message ?? settings.connectionStatusMessage ?? (
                    settings.supportsBiometricUnlock ? "设备账号已通过 Face ID 登录。" : "设备账号已登录。"
                )
            }
        } catch {
            refreshMessage = error.localizedDescription
        }
    }

}
