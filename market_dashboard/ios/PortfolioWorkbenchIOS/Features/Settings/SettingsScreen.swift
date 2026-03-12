import SwiftUI
import UniformTypeIdentifiers
import PortfolioWorkbenchMobileCore

struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var dashboardStore: PortfolioDashboardStore

    @FocusState private var isEditingURL: Bool
    @State private var selectedAccountID = ""
    @State private var isImporting = false
    @State private var isUploading = false
    @State private var isRefreshing = false
    @State private var refreshMessage: String?
    @State private var importCenter: ImportCenterPayload?
    @State private var isLoadingImportCenter = false

    var body: some View {
        NavigationStack {
            AppBackdrop {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        accountSection
                        connectionSection
                        updateStatementSection
                        importCenterSection
                        refreshSection
                        cacheSection
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("设置")
            .appInlineNavigationTitle()
            .task {
                await loadImportCenter()
                syncSelectedAccountIfNeeded()
            }
            .task(id: dashboardAccountSeed) {
                syncSelectedAccountIfNeeded()
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf]) { result in
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
                if let currentUser = settings.currentUser {
                    LabelValueRow(label: "显示名称", value: currentUser.displayName)
                    LabelValueRow(label: "用户 ID", value: currentUser.userId)
                    LabelValueRow(label: "登录方式", value: authProviderLabel(currentUser.authProvider))
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
                    Text("当前未登录。返回首页将看到登录入口。")
                        .font(.subheadline)
                        .foregroundStyle(BrokerPalette.muted)
                }
            }
        }
    }

    private var refreshSection: some View {
        RefreshActionStrip(
            title: "数据刷新",
            subtitle: "手动同步",
            lastUpdatedAt: dashboardStore.lastUpdatedAt,
            isRefreshing: dashboardStore.isRefreshing,
            isShowingCachedSnapshot: dashboardStore.isShowingCachedSnapshot
        ) {
            Task { await refreshDashboard() }
        } insightAction: {
            Task { await refreshAI() }
        }
    }

    private var connectionSection: some View {
        SectionPanel(title: "服务连接", subtitle: "请填写当前可访问的数据服务地址。真机使用时建议填写局域网地址。") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("http://192.168.1.10:8008/", text: $settings.serverURLString)
                    .appURLTextEntry()
                    .focused($isEditingURL)
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(BrokerPalette.ink)

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

                if let refreshMessage {
                    Text(refreshMessage)
                        .font(.footnote)
                        .foregroundStyle(refreshMessage.contains("失败") || refreshMessage.contains("错误") ? BrokerPalette.red : BrokerPalette.teal)
                }
            }
        }
    }

    private var updateStatementSection: some View {
        SectionPanel(title: "更新结单", subtitle: "把新的 PDF 结单替换到指定账户，组合快照会立即重建。") {
            VStack(alignment: .leading, spacing: 14) {
                if let payload = dashboardPayload, !payload.accounts.isEmpty {
                    Picker("目标账户", selection: $selectedAccountID) {
                        ForEach(payload.accounts) { account in
                            Text("\(account.broker) · \(account.accountId)").tag(account.accountId)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 8) {
                        TagBadge(text: "PDF ≤ 40MB", tint: BrokerPalette.cyan)
                        TagBadge(text: "先校验后替换", tint: BrokerPalette.gold)
                    }

                    Button {
                        isImporting = true
                    } label: {
                        HStack {
                            if isUploading {
                                ProgressView()
                                    .tint(Color.black)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text(isUploading ? "正在上传" : "选择并上传新结单")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrokerPalette.cyan)
                    .foregroundStyle(Color.black)
                    .disabled(selectedAccountID.isEmpty || isUploading)

                    if let source = payload.statementSources.first(where: { $0.accountId == selectedAccountID }) {
                        VStack(alignment: .leading, spacing: 8) {
                            LabelValueRow(label: "当前源", value: source.fileName)
                            LabelValueRow(
                                label: "状态",
                                value: loadStatusLabel(source.loadStatus),
                                valueColor: BrokerPalette.sourceStatus(source.loadStatus)
                            )
                            if let uploadedAt = source.uploadedAt {
                                LabelValueRow(label: "最近上传", value: uploadedAt)
                            }
                        }
                    }
                } else {
                    Text("当前还没有可更新的账户。先连接服务并同步一次账户数据，再回来更新结单。")
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

    private var importCenterSection: some View {
        SectionPanel(title: "券商接入", subtitle: "当前版本以稳定同步为先，自动授权能力会按券商支持情况逐步补齐。") {
            VStack(alignment: .leading, spacing: 14) {
                if isLoadingImportCenter, importCenter == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(BrokerPalette.cyan)
                        Text("正在读取券商接入能力…")
                            .font(.subheadline)
                            .foregroundStyle(BrokerPalette.muted)
                    }
                }

                if let importCenter {
                    ForEach(importCenter.brokers) { broker in
                        brokerCard(broker)
                    }

                    if !importCenter.statementTemplates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("当前已支持的结单导入模板")
                                .font(.headline)
                                .foregroundStyle(BrokerPalette.ink)

                            ForEach(importCenter.statementTemplates) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.label)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BrokerPalette.ink)
                                    Text(item.description)
                                        .font(.footnote)
                                        .foregroundStyle(BrokerPalette.muted)
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("接入说明")
                            .font(.headline)
                            .foregroundStyle(BrokerPalette.ink)

                        ForEach(importCenter.notes, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(BrokerPalette.cyan)
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 6)
                                Text(item)
                                    .font(.subheadline)
                                    .foregroundStyle(BrokerPalette.ink)
                            }
                        }
                    }
                } else {
                    Text("当前还没拿到券商接入信息。确认服务地址可用后，再刷新一次。")
                        .font(.subheadline)
                        .foregroundStyle(BrokerPalette.muted)
                }
            }
        }
    }

    private func brokerCard(_ broker: BrokerCapability) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(broker.name)
                        .font(.headline)
                        .foregroundStyle(BrokerPalette.ink)
                    Text(broker.summary)
                        .font(.subheadline)
                        .foregroundStyle(BrokerPalette.muted)
                }

                Spacer()

                TagBadge(text: statusLabel(broker.status), tint: statusTint(broker.status))
            }

            LabelValueRow(label: "官方接入路径", value: broker.authPath)
            LabelValueRow(label: "下一步", value: broker.nextStep)

            HStack(spacing: 8) {
                TagBadge(text: broker.supportsPositions ? "支持持仓" : "不含持仓", tint: broker.supportsPositions ? BrokerPalette.teal : BrokerPalette.red)
                TagBadge(text: broker.supportsTrades ? "支持交易" : "不含交易", tint: broker.supportsTrades ? BrokerPalette.cyan : BrokerPalette.red)
                TagBadge(text: broker.connectableInApp ? "可 App 内直连" : "暂不可 App 内直连", tint: broker.connectableInApp ? BrokerPalette.green : BrokerPalette.gold)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(broker.requirements, id: \.self) { item in
                    Text("• \(item)")
                        .font(.footnote)
                        .foregroundStyle(BrokerPalette.muted)
                }
            }

            if let url = URL(string: broker.docsUrl) {
                Link(destination: url) {
                    Label("查看官方文档", systemImage: "arrow.up.forward.square")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrokerPalette.cyan)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var cacheSection: some View {
        SectionPanel(title: "同步状态") {
            VStack(alignment: .leading, spacing: 10) {
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
            }
        }
    }

    private func refreshNow() async {
        isRefreshing = true
        isEditingURL = false

        do {
            let client = try await settings.makeValidatedClient(forceSessionCheck: true)
            await dashboardStore.load(using: client, force: true)
            await loadImportCenter()
            refreshMessage = "已连接 \(settings.trimmedServerURLString)"
        } catch {
            refreshMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    private func refreshDashboard() async {
        do {
            let client = try await settings.makeValidatedClient()
            await dashboardStore.refreshVisible(using: client)
        } catch {
            dashboardStore.setError(error.localizedDescription)
        }
    }

    private func refreshAI() async {
        do {
            let client = try await settings.makeValidatedClient()
            await dashboardStore.refreshAI(using: client, force: true)
        } catch {
            dashboardStore.setError(error.localizedDescription)
        }
    }

    private func loadImportCenter() async {
        guard settings.isAuthenticated else {
            importCenter = nil
            return
        }

        isLoadingImportCenter = true
        defer { isLoadingImportCenter = false }

        do {
            let client = try await settings.makeValidatedClient()
            let payload = try await client.fetchImportCenter()
            importCenter = payload
        } catch {
            refreshMessage = error.localizedDescription
        }
    }

    private func logout() async {
        do {
            let client = try await settings.makeValidatedClient()
            _ = try await client.logout()
        } catch {
            refreshMessage = error.localizedDescription
        }
        importCenter = nil
        settings.clearAuthentication()
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

    private var dashboardPayload: MobileDashboardPayload? {
        dashboardStore.state.value
    }

    private var dashboardAccountSeed: String {
        dashboardPayload?.accounts.map(\.accountId).joined(separator: "|") ?? "empty"
    }

    private func syncSelectedAccountIfNeeded() {
        guard let payload = dashboardPayload, !payload.accounts.isEmpty else {
            selectedAccountID = ""
            return
        }
        if payload.accounts.contains(where: { $0.accountId == selectedAccountID }) {
            return
        }
        selectedAccountID = payload.accounts[0].accountId
    }

    private func upload(url: URL) async {
        guard !selectedAccountID.isEmpty else {
            refreshMessage = "请先选择目标账户。"
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
            let client = try await settings.makeValidatedClient()

            isUploading = true
            refreshMessage = "正在上传并校验结单…"
            let response = try await client.uploadStatement(
                accountID: selectedAccountID,
                fileName: fileName,
                mimeType: mimeType,
                fileData: fileData
            )
            refreshMessage = response.message
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
            await loadImportCenter()
        } catch {
            refreshMessage = error.localizedDescription
        }

        isUploading = false
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
        default:
            return provider
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "gateway_required":
            return "需额外服务"
        case "developer_credentials":
            return "需额外配置"
        case "approval_or_gateway":
            return "需审批或服务"
        case "oauth_or_token":
            return "OAuth/Token"
        case "developer_token":
            return "需额外授权"
        default:
            return status
        }
    }

    private func statusTint(_ status: String) -> Color {
        switch status {
        case "gateway_required":
            return BrokerPalette.gold
        case "developer_credentials":
            return BrokerPalette.orange
        case "approval_or_gateway":
            return BrokerPalette.red
        case "oauth_or_token":
            return BrokerPalette.green
        case "developer_token":
            return BrokerPalette.cyan
        default:
            return BrokerPalette.teal
        }
    }
}
