import SwiftUI
import PortfolioWorkbenchMobileCore

private enum AppTab: String, Hashable {
    case ai
    case overview
    case holdings
    case settings
}

private enum AppBootPhase: Equatable {
    case prewarming
    case failed
    case ready
}

private enum AppLaunchOptions {
    static let initialTabEnvironmentKey = "PORTFOLIO_WORKBENCH_INITIAL_TAB"

    static var initialTab: AppTab {
        guard let rawValue = ProcessInfo.processInfo.environment[initialTabEnvironmentKey]?.lowercased() else {
            return .overview
        }
        if rawValue == "accounts" {
            return .holdings
        }
        if rawValue == "insight" {
            return .ai
        }
        return AppTab(rawValue: rawValue) ?? .overview
    }
}

struct MainTabView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var dashboardStore: PortfolioDashboardStore
    @State private var selectedTab = AppLaunchOptions.initialTab
    @State private var bootPhase: AppBootPhase = .prewarming
    @State private var bootStatusText = "正在加载最新行情与资讯…"
    @State private var bootActionHint = "如果当前服务器不可用，你可以先去配置服务器。"
    @State private var hasStartedBootstrap = false
    @State private var bootStartedAt: Date = .now
    @State private var bootOverlayReleased = false
    @State private var isShowingServerConfig = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                AITabScreen()
                    .tag(AppTab.ai)
                    .tabItem {
                        Label("AI", systemImage: "sparkles")
                    }

                OverviewScreen()
                    .tag(AppTab.overview)
                    .tabItem {
                        Label("总览", systemImage: "chart.pie.fill")
                    }

                HoldingsScreen()
                    .tag(AppTab.holdings)
                    .tabItem {
                        Label("资产", systemImage: "chart.line.uptrend.xyaxis")
                    }

                SettingsScreen()
                    .tag(AppTab.settings)
                    .tabItem {
                        Label("设置", systemImage: "slider.horizontal.3")
                    }
            }
            .toolbarBackground(BrokerPalette.panelStrong.opacity(0.96), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            if shouldShowBootOverlay {
                BootOverlayView(
                    phase: bootPhase,
                    statusText: bootStatusText,
                    actionHint: bootActionHint,
                    onConfigureServer: {
                        selectedTab = .settings
                        isShowingServerConfig = true
                    },
                    onRetry: {
                        Task { await bootstrap(force: true) }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .transientSyncBanner(
            message: dashboardStore.activityMessage,
            isRefreshing: dashboardStore.isRefreshing,
            isStale: dashboardStore.isShowingCachedSnapshot
        )
        .task {
            guard !hasStartedBootstrap else { return }
            hasStartedBootstrap = true
            if settings.shouldPreferAITabOnLaunch {
                selectedTab = .ai
            }
            await settings.ensureLaunchSessionIfPossible()
            dashboardStore.setSessionUserID(settings.cacheNamespace)
            await bootstrap()
        }
        .onChange(of: settings.cacheNamespace) { _, _ in
            dashboardStore.setSessionUserID(settings.cacheNamespace)
            Task { await bootstrap(force: true) }
        }
        .onChange(of: settings.canAccessRemoteData) { _, _ in
            Task { await bootstrap(force: true) }
        }
        .onChange(of: settings.longbridgeSessionState) { _, _ in
            Task { await bootstrap(force: true) }
        }
        .onChange(of: settings.shouldPreferAITabOnLaunch) { _, shouldPreferAITabOnLaunch in
            if shouldPreferAITabOnLaunch {
                selectedTab = .ai
            }
        }
        .sheet(isPresented: $isShowingServerConfig) {
            ServerConnectionConfigSheet()
                .presentationDetents([.medium, .large])
                .environmentObject(settings)
        }
        .task(id: holdingPrefetchSignature) {
            await prefetchHoldingDetails()
        }
    }

    private var shouldShowBootOverlay: Bool {
        guard settings.canAccessRemoteData else {
            return false
        }
        if case .ready = bootPhase {
            return false
        }
        return true
    }

    private func bootstrap() async {
        await bootstrap(force: false)
    }

    private func bootstrap(force: Bool) async {
        if force {
            bootOverlayReleased = false
        }
        dashboardStore.setSessionUserID(settings.cacheNamespace)
        bootPhase = .prewarming
        bootStatusText = "正在加载最新行情与资讯…"
        bootActionHint = "如果当前服务器不可用，你可以先去配置服务器。"
        bootStartedAt = .now
        bootOverlayReleased = false

        let fallbackReleaseTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await releaseBootOverlayIfNeeded(minimumVisibleDuration: 0.9)
        }

        Task {
            await runBootstrapDataFlow()
        }

        _ = await fallbackReleaseTask.value
    }

    private var holdingPrefetchSignature: String {
        orderedHoldingSymbols.joined(separator: "|")
    }

    private func prefetchHoldingDetails() async {
        guard settings.canAccessRemoteData else {
            return
        }
        guard !orderedHoldingSymbols.isEmpty else {
            return
        }

        do {
            let client = try settings.makeClient()
            await HoldingDetailViewModel.prefetch(
                symbols: orderedHoldingSymbols,
                using: client,
                cacheNamespace: settings.cacheNamespace
            )
        } catch {
            // Keep prefetch silent; on-demand loading still handles failures.
        }
    }

    private var orderedHoldingSymbols: [String] {
        guard let payload = dashboardStore.state.value else {
            return []
        }
        return payload.positions
            .sorted { $0.weightPct > $1.weightPct }
            .map(\.symbol)
    }

    private func prewarmBootData(
        using client: PortfolioWorkbenchAPIClient,
        payload: MobileDashboardPayload
    ) async {
        let symbols = payload.positions
            .sorted { $0.weightPct > $1.weightPct }
            .prefix(8)
            .map(\.symbol)
        guard !symbols.isEmpty else {
            return
        }
        await HoldingDetailViewModel.prefetch(
            symbols: symbols,
            using: client,
            cacheNamespace: settings.cacheNamespace
        )
    }

    private func runBootstrapDataFlow() async {
        if !settings.canAccessRemoteData {
            if settings.canUseLongbridgeSession {
                bootStatusText = "正在同步 Longbridge 本地快照…"
                await dashboardStore.refreshLocalFirst(using: settings)
            } else {
                dashboardStore.setNotice("当前为本机身份或未连接服务器，手机缓存会优先展示。")
            }
            await releaseBootOverlayIfNeeded(minimumVisibleDuration: 0)
            return
        }
        do {
            bootStatusText = "正在连接数据服务…"
            let client = try settings.makeClient()
            bootStatusText = "正在拉取核心行情…"
            await dashboardStore.refreshVisible(using: client)

            if settings.canUseLongbridgeSession {
                bootStatusText = "正在切换到 Longbridge 直连快照…"
                await dashboardStore.refreshLocalFirst(using: settings)
            }

            guard let payload = dashboardStore.state.value else {
                let message = dashboardStore.activityMessage ?? "服务暂时不可用，请稍后重试。"
                bootStatusText = message
                if isConnectionAvailabilityFailure(message) {
                    bootPhase = .failed
                    bootActionHint = "没有可用服务器时，请点击“配置服务器”后再重试。"
                } else {
                    await releaseBootOverlayIfNeeded(minimumVisibleDuration: 1.0)
                }
                return
            }

            bootStatusText = payload.summaryCards.isEmpty
                ? "核心信息已就绪，正在补齐洞察…"
                : "行情与洞察已同步到 \(payload.analysisDateCn)"
            await prewarmBootData(using: client, payload: payload)
            await releaseBootOverlayIfNeeded(minimumVisibleDuration: 1.0)
        } catch {
            if error.localizedDescription.contains("请先登录") {
                settings.clearAuthentication()
                await releaseBootOverlayIfNeeded(minimumVisibleDuration: 0.8)
                return
            }
            let message = friendlyBootErrorMessage(error)
            bootStatusText = message
            if isConnectionAvailabilityFailure(message) {
                bootPhase = .failed
                bootActionHint = "没有可用服务器时，请点击“配置服务器”后再重试。"
            } else {
                if dashboardStore.state.value == nil {
                    dashboardStore.setError(message)
                } else {
                    dashboardStore.setNotice(message)
                }
                await releaseBootOverlayIfNeeded(minimumVisibleDuration: 0.8)
            }
        }
    }

    private func releaseBootOverlayIfNeeded(minimumVisibleDuration: TimeInterval) async {
        guard !bootOverlayReleased else {
            return
        }
        guard case .failed = bootPhase else {
            bootOverlayReleased = true
            let elapsed = Date().timeIntervalSince(bootStartedAt)
            let remaining = max(0, minimumVisibleDuration - elapsed)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }

            withAnimation(.easeOut(duration: 0.28)) {
                bootPhase = .ready
            }
            return
        }
        bootOverlayReleased = true

        return
    }

    private func friendlyBootErrorMessage(_ error: Error) -> String {
        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("timed out") || lowered.contains("timeout") {
            return "连接超时，已为你回退到本地缓存。"
        }
        if lowered.contains("could not connect")
            || lowered.contains("offline")
            || lowered.contains("network")
            || lowered.contains("connection") {
            return "网络连接异常，已为你回退到最近缓存。"
        }
        return error.localizedDescription
    }

    private func isConnectionAvailabilityFailure(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("未找到可连接的服务器")
            || lowered.contains("暂未发现可用服务器")
            || lowered.contains("暂无可探测服务器地址")
            || lowered.contains("网络连接异常")
            || lowered.contains("连接超时")
            || lowered.contains("服务器")
    }
}

private struct BootOverlayView: View {
    let phase: AppBootPhase
    let statusText: String
    let actionHint: String
    let onConfigureServer: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            BootBrandBackdrop()

            VStack(spacing: 15) {
                BootBrandWordmark(logoSize: 88, titleSize: 35, subtitleSize: 11)

                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 7, height: 7)
                            .scaleEffect(phase == .prewarming ? 1 : 0.6)
                    }
                }
            }
            .offset(y: -112)

            Color.black.opacity(phase == .prewarming ? 0.02 : 0)
                .ignoresSafeArea()

            VStack {
                Spacer()
                if case .failed = phase {
                    VStack(spacing: 12) {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.82))
                            .multilineTextAlignment(.center)

                        Text(actionHint)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button {
                                onConfigureServer()
                            } label: {
                                Text("配置服务器")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BrokerPalette.gold)
                            .foregroundStyle(Color.black)

                            Button {
                                onRetry()
                            } label: {
                                Text("重新探测")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(BrokerPalette.cyan)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                } else if case .prewarming = phase {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.74))
                        .padding(.bottom, 10)
                    Spacer().frame(height: 18)
                }
            }
            .padding(.horizontal, 18)
        }
    }
}
