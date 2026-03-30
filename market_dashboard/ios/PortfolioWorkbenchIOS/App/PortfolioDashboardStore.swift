import Foundation
import PortfolioWorkbenchMobileCore

@MainActor
final class PortfolioDashboardStore: ObservableObject {
    @Published private(set) var state: LoadState<MobileDashboardPayload>
    @Published private(set) var isRefreshing = false
    @Published private(set) var activityMessage: String?
    @Published private(set) var isShowingCachedSnapshot = false
    @Published private(set) var lastUpdatedAt: Date?

    private static let dashboardCacheKeyPrefix = "portfolio-workbench-ios.dashboard-cache"
    private static let dashboardGlobalCacheKey = "portfolio-workbench-ios.dashboard-cache.global"
    private static let refreshInterval: TimeInterval = 3 * 60
    private var cacheKey = "portfolio-workbench-ios.dashboard-cache.anonymous"

    init() {
        state = .idle
        activityMessage = nil
    }

    func setSessionUserID(_ userID: String?) {
        let normalizedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextKey = Self.cacheKey(for: normalizedUserID)
        guard nextKey != cacheKey else {
            return
        }

        cacheKey = nextKey
        if let cachedSnapshot = Self.restoreCachedPayload(cacheKey: cacheKey) {
            state = .loaded(cachedSnapshot.payload)
            lastUpdatedAt = cachedSnapshot.cachedAt
            activityMessage = "已载入最近一次同步结果"
            isShowingCachedSnapshot = true
        } else if let cachedSnapshot = Self.restoreCachedPayload(cacheKey: Self.dashboardGlobalCacheKey) {
            state = .loaded(cachedSnapshot.payload)
            lastUpdatedAt = cachedSnapshot.cachedAt
            activityMessage = "已载入最近一次同步结果"
            isShowingCachedSnapshot = true
        } else if let cachedSnapshot = Self.restoreMostRecentCachedPayload() {
            state = .loaded(cachedSnapshot.payload)
            lastUpdatedAt = cachedSnapshot.cachedAt
            activityMessage = "已载入最近一次同步结果"
            isShowingCachedSnapshot = true
        } else {
            state = .idle
            lastUpdatedAt = nil
            activityMessage = nil
            isShowingCachedSnapshot = false
        }
    }

    func setError(_ message: String) {
        isRefreshing = false
        if state.value != nil {
            activityMessage = message
            isShowingCachedSnapshot = true
        } else {
            state = .failed(message)
            activityMessage = nil
        }
    }

    func setNotice(_ message: String) {
        isRefreshing = false
        activityMessage = message
        isShowingCachedSnapshot = state.value != nil
    }

    func prime(using client: PortfolioWorkbenchAPIClient) async {
        if state.value != nil, isCacheFresh {
            activityMessage = "已显示最近一次同步结果"
            isShowingCachedSnapshot = true
            return
        }

        if state.value != nil {
            await load(
                using: client,
                force: false,
                fast: false,
                allowLoadedRefresh: true,
                loadingMessage: "已载入最近结果，正在更新最新数据…"
            )
            return
        }

        await load(
            using: client,
            force: false,
            fast: true,
            allowLoadedRefresh: true,
            loadingMessage: "正在准备核心指标与持仓…"
        )

        guard state.value != nil else {
            return
        }

        await load(
            using: client,
            force: false,
            fast: false,
            allowLoadedRefresh: true,
            loadingMessage: "核心数据已到，继续更新市场与组合提示…"
        )
    }

    func apply(_ payload: MobileDashboardPayload, message: String? = nil) {
        state = .loaded(payload)
        isRefreshing = false
        isShowingCachedSnapshot = false
        activityMessage = message ?? "组合已更新"
        lastUpdatedAt = .now
        Self.storeCachedPayload(payload, cacheKey: cacheKey)
        Self.storeCachedPayload(payload, cacheKey: Self.dashboardGlobalCacheKey)
    }

    func refreshLocalFirst(using settings: AppSettingsStore) async {
        if isRefreshing {
            return
        }

        isRefreshing = true
        isShowingCachedSnapshot = state.value != nil
        activityMessage = "正在同步 Longbridge 本地快照…"
        LongbridgeDiagnosticsStore.shared.append("Dashboard 开始应用 Longbridge 本地快照。")

        do {
            let orchestrator = MarketDataOrchestrator(settings: settings)
            let loadedSnapshot = try await orchestrator.loadSnapshot()
            let referenceSnapshot = state.value.map(ServiceDashboardSnapshotFactory.makeSnapshot(from:))
            var snapshot = loadedSnapshot.fillingMissingFields(from: referenceSnapshot)

            guard snapshot.isMeaningful else {
                LongbridgeDiagnosticsStore.shared.append("Longbridge 新快照无有效数据，保留当前结果。")
                isRefreshing = false
                if state.value != nil {
                    activityMessage = "Longbridge 当前没有可覆盖的新数据，已保留现有快照"
                    isShowingCachedSnapshot = true
                } else {
                    state = .failed("Longbridge 当前没有返回可用数据，请先确认授权或切换到可达的服务器后重试。")
                    activityMessage = nil
                }
                return
            }

            if snapshot.isSafeReplacement(for: referenceSnapshot) == false {
                LongbridgeDiagnosticsStore.shared.append("Longbridge 新快照不完整，尝试用稳定快照补齐。")
                let recoveredSnapshot = snapshot.recoveringMissingCoreData(from: referenceSnapshot)
                if recoveredSnapshot.isSafeReplacement(for: referenceSnapshot) {
                    snapshot = recoveredSnapshot
                    LongbridgeDiagnosticsStore.shared.append("Longbridge 稳定快照补齐成功，继续应用。")
                } else {
                    LongbridgeDiagnosticsStore.shared.append("Longbridge 补齐后仍不完整，保留当前结果。")
                    isRefreshing = false
                    if state.value != nil {
                        activityMessage = "Longbridge 新快照不完整，已保留当前结果"
                        isShowingCachedSnapshot = true
                    } else {
                        state = .failed("Longbridge 新快照不完整，请稍后重试。")
                        activityMessage = nil
                    }
                    return
                }
            }

            let payload = LongbridgeDashboardSnapshotFactory.makePayload(from: snapshot)
            apply(
                payload,
                message: snapshot.fallbackUsage.isEmpty
                    ? "Longbridge 数据已同步到本机"
                    : "Longbridge 数据已同步，部分字段已回退"
            )
            LongbridgeDiagnosticsStore.shared.append(
                "Dashboard 已应用 Longbridge 快照: positions=\(snapshot.positions.count), news=\(snapshot.topNews.count), fallback=\(snapshot.fallbackUsage.isEmpty ? "none" : snapshot.fallbackUsage.joined(separator: "、"))"
            )
        } catch {
            LongbridgeDiagnosticsStore.shared.append("Dashboard 刷新 Longbridge 快照失败: \(error.localizedDescription)")
            isRefreshing = false
            if state.value != nil {
                activityMessage = "Longbridge 快照暂时不可用，先保留当前结果"
                isShowingCachedSnapshot = true
            } else {
                state = .failed(error.localizedDescription)
                activityMessage = nil
            }
        }
    }

    func refreshVisible(using client: PortfolioWorkbenchAPIClient) async {
        await load(
            using: client,
            force: true,
            fast: true,
            allowLoadedRefresh: true,
            loadingMessage: "先同步核心行情与持仓…"
        )

        guard state.value != nil else {
            return
        }

        await load(
            using: client,
            force: true,
            fast: false,
            allowLoadedRefresh: true,
            loadingMessage: "核心数据已更新，继续补齐市场与宏观洞察…"
        )
    }

    func refreshAI(using client: PortfolioWorkbenchAPIClient, force: Bool = true) async {
        guard let currentPayload = state.value else {
            await load(using: client, force: force, fast: false, allowLoadedRefresh: true)
            return
        }

        if isRefreshing {
            return
        }

        isRefreshing = true
        isShowingCachedSnapshot = true
        activityMessage = "正在刷新 AI 洞察…"

        do {
            let overlay = try await client.fetchDashboardAI(refresh: force)
            let mergedPayload = MobileDashboardPayload(
                generatedAt: currentPayload.generatedAt,
                analysisDateCn: currentPayload.analysisDateCn,
                snapshotDate: currentPayload.snapshotDate,
                hero: currentPayload.hero,
                summaryCards: currentPayload.summaryCards,
                marketPulse: currentPayload.marketPulse,
                sourceHealth: currentPayload.sourceHealth,
                keyDrivers: currentPayload.keyDrivers,
                riskFlags: currentPayload.riskFlags,
                actionCenter: currentPayload.actionCenter,
                actionBlocks: overlay.actionBlocks,
                aiUpdatedAt: overlay.aiUpdatedAt,
                aiEngineLabel: overlay.aiEngineLabel,
                healthRadar: currentPayload.healthRadar,
                allocationGroups: currentPayload.allocationGroups,
                macroTopics: currentPayload.macroTopics,
                strategyViews: currentPayload.strategyViews,
                positions: currentPayload.positions,
                spotlightPositions: currentPayload.spotlightPositions,
                accounts: currentPayload.accounts,
                recentTrades: currentPayload.recentTrades,
                derivatives: currentPayload.derivatives,
                statementSources: currentPayload.statementSources,
                referenceSources: currentPayload.referenceSources,
                updateGuide: currentPayload.updateGuide
            )
            state = .loaded(mergedPayload)
            isShowingCachedSnapshot = false
            isRefreshing = false
            activityMessage = overlay.aiStatusMessage
            Self.storeCachedPayload(mergedPayload, cacheKey: cacheKey)
        } catch {
            isRefreshing = false
            isShowingCachedSnapshot = true
            activityMessage = "AI 洞察暂时无法更新，先保留当前结果"
        }
    }

    func load(
        using client: PortfolioWorkbenchAPIClient,
        force: Bool = false,
        fast: Bool = false,
        allowLoadedRefresh: Bool = false,
        loadingMessage: String? = nil
    ) async {
        if isRefreshing && !force {
            return
        }

        let currentValue = state.value
        if currentValue != nil, !force, !allowLoadedRefresh {
            return
        }

        if currentValue != nil, !force, isCacheFresh {
            isRefreshing = false
            isShowingCachedSnapshot = true
            activityMessage = "已显示最近一次同步结果"
            return
        }

        let hasVisibleData = currentValue != nil
        isRefreshing = true
        isShowingCachedSnapshot = hasVisibleData
        activityMessage = loadingMessage ?? defaultLoadingMessage(hasVisibleData: hasVisibleData, force: force, fast: fast)

        if !hasVisibleData {
            state = .loading
        }

        do {
            let payload = try await client.fetchDashboard(refresh: force, fast: fast)
            guard payload.isMeaningful else {
                isRefreshing = false
                if hasVisibleData {
                    activityMessage = "服务返回了空快照，已保留当前结果"
                    isShowingCachedSnapshot = true
                } else {
                    state = .failed("服务返回了空快照，请稍后重试或切换可用服务器。")
                    activityMessage = nil
                }
                return
            }
            state = .loaded(payload)
            isShowingCachedSnapshot = false
            activityMessage = fast ? "核心数据已就绪" : "行情与洞察已同步到 \(payload.analysisDateCn)"
            lastUpdatedAt = .now
            Self.storeCachedPayload(payload, cacheKey: cacheKey)
        } catch {
            if hasVisibleData {
                activityMessage = force ? "刷新失败，先保留当前结果" : "暂时无法更新，先保留当前结果"
                isShowingCachedSnapshot = true
            } else {
                state = .failed(error.localizedDescription)
                activityMessage = nil
            }
        }

        isRefreshing = false
    }

    private func defaultLoadingMessage(hasVisibleData: Bool, force: Bool, fast: Bool) -> String {
        if force {
            return "正在刷新最新行情与洞察…"
        }
        if hasVisibleData {
            return "正在后台同步最新行情与洞察…"
        }
        if fast {
            return "正在准备核心指标与持仓…"
        }
        return "正在同步组合数据…"
    }

    private var isCacheFresh: Bool {
        guard let lastUpdatedAt else {
            return false
        }
        return Date().timeIntervalSince(lastUpdatedAt) < Self.refreshInterval
    }

    private static func cacheKey(for userID: String?) -> String {
        let sanitized = (userID?.isEmpty == false ? userID : "anonymous") ?? "anonymous"
        return dashboardCacheKeyPrefix + "." + sanitized
    }

    private static func restoreCachedPayload(cacheKey: String) -> CachedSnapshot<MobileDashboardPayload>? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        if let snapshot = try? JSONDecoder().decode(CachedSnapshot<MobileDashboardPayload>.self, from: data) {
            return snapshot
        }
        guard let payload = try? JSONDecoder().decode(MobileDashboardPayload.self, from: data) else {
            return nil
        }
        return CachedSnapshot(cachedAt: .distantPast, payload: payload)
    }

    private static func storeCachedPayload(_ payload: MobileDashboardPayload, cacheKey: String) {
        let snapshot = CachedSnapshot(cachedAt: .now, payload: payload)
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private static func restoreMostRecentCachedPayload() -> CachedSnapshot<MobileDashboardPayload>? {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(dashboardCacheKeyPrefix) }
        var best: CachedSnapshot<MobileDashboardPayload>?
        for key in keys {
            guard let snapshot = restoreCachedPayload(cacheKey: key) else {
                continue
            }
            if let current = best {
                if snapshot.cachedAt > current.cachedAt {
                    best = snapshot
                }
            } else {
                best = snapshot
            }
        }
        return best
    }
}
