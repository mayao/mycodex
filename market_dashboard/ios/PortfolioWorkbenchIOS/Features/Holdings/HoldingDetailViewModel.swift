import Foundation
import PortfolioWorkbenchMobileCore

private actor HoldingDetailPrefetchRegistry {
    static let shared = HoldingDetailPrefetchRegistry()

    private var inFlightSymbols = Set<String>()

    func begin(symbol: String) -> Bool {
        let key = symbol.uppercased()
        guard !inFlightSymbols.contains(key) else {
            return false
        }
        inFlightSymbols.insert(key)
        return true
    }

    func end(symbol: String) {
        inFlightSymbols.remove(symbol.uppercased())
    }
}

enum HoldingDetailRefreshIntent {
    case automatic
    case market
    case insight

    func loadingMessage(hasVisibleData: Bool) -> String {
        switch self {
        case .automatic:
            return hasVisibleData ? "正在后台同步最新价格与分析…" : "正在读取价格与分析…"
        case .market:
            return "正在刷新最新价格与走势…"
        case .insight:
            return "正在刷新 AI 洞察与判断…"
        }
    }

    var successMessage: String {
        switch self {
        case .automatic:
            return "价格与分析已同步"
        case .market:
            return "行情已更新"
        case .insight:
            return "AI 洞察已更新"
        }
    }
}

@MainActor
final class HoldingDetailViewModel: ObservableObject {
    @Published private(set) var state: LoadState<HoldingDetailPayload> = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var activityMessage: String?
    @Published private(set) var isShowingCachedSnapshot = false
    @Published private(set) var lastUpdatedAt: Date?

    nonisolated private static let refreshInterval: TimeInterval = 5 * 60
    nonisolated private static let cacheKeyPrefix = "portfolio-workbench-ios.holding-cache."

    private var currentSymbol: String?
    private var currentCacheNamespace = "anonymous"

    nonisolated static func prefetch(
        symbols: [String],
        using client: PortfolioWorkbenchAPIClient,
        cacheNamespace: String? = nil
    ) async {
        var seen = Set<String>()
        let uniqueSymbols = symbols.filter { seen.insert($0.uppercased()).inserted }
        guard !uniqueSymbols.isEmpty else {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            var iterator = uniqueSymbols.makeIterator()
            let concurrentJobs = min(4, uniqueSymbols.count)

            for _ in 0 ..< concurrentJobs {
                guard let symbol = iterator.next() else {
                    break
                }
                group.addTask(priority: .utility) {
                    await prefetchSymbol(symbol, using: client, cacheNamespace: cacheNamespace)
                }
            }

            while await group.next() != nil {
                guard let symbol = iterator.next() else {
                    continue
                }
                group.addTask(priority: .utility) {
                    await prefetchSymbol(symbol, using: client, cacheNamespace: cacheNamespace)
                }
            }
        }
    }

    private nonisolated static func prefetchSymbol(
        _ symbol: String,
        using client: PortfolioWorkbenchAPIClient,
        cacheNamespace: String? = nil
    ) async {
        guard await HoldingDetailPrefetchRegistry.shared.begin(symbol: symbol) else {
            return
        }

        if let snapshot = restoreCachedPayload(for: symbol, cacheNamespace: cacheNamespace),
           Date().timeIntervalSince(snapshot.cachedAt) < refreshInterval {
            await HoldingDetailPrefetchRegistry.shared.end(symbol: symbol)
            return
        }

        do {
            let payload = try await client.fetchHoldingDetail(symbol: symbol, refresh: false)
            storeCachedPayload(payload, for: symbol, cacheNamespace: cacheNamespace)
        } catch {
            await HoldingDetailPrefetchRegistry.shared.end(symbol: symbol)
            return
        }

        await HoldingDetailPrefetchRegistry.shared.end(symbol: symbol)
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

    func load(
        symbol: String,
        using client: PortfolioWorkbenchAPIClient,
        cacheNamespace: String? = nil,
        force: Bool = false,
        intent: HoldingDetailRefreshIntent = .automatic
    ) async {
        prepareStateIfNeeded(for: symbol, cacheNamespace: cacheNamespace)

        if isRefreshing && !force {
            return
        }

        if state.value != nil, !force, isCacheFresh {
            activityMessage = "已载入最近一次结果"
            isShowingCachedSnapshot = true
            return
        }

        let hasVisibleData = state.value != nil
        isRefreshing = true
        isShowingCachedSnapshot = hasVisibleData
        activityMessage = intent.loadingMessage(hasVisibleData: hasVisibleData)

        if !hasVisibleData {
            state = .loading
        }

        do {
            let payload = try await client.fetchHoldingDetail(symbol: symbol, refresh: force)
            state = .loaded(payload)
            isRefreshing = false
            isShowingCachedSnapshot = false
            lastUpdatedAt = .now
            activityMessage = intent.successMessage
            Self.storeCachedPayload(payload, for: symbol, cacheNamespace: cacheNamespace)
        } catch {
            isRefreshing = false
            if hasVisibleData {
                activityMessage = force ? "刷新失败，先保留当前结果" : "暂时无法更新，先保留当前结果"
                isShowingCachedSnapshot = true
            } else {
                state = .failed(error.localizedDescription)
                activityMessage = nil
            }
        }
    }

    func refreshAI(
        symbol: String,
        using client: PortfolioWorkbenchAPIClient,
        cacheNamespace: String? = nil,
        force: Bool = true
    ) async {
        prepareStateIfNeeded(for: symbol, cacheNamespace: cacheNamespace)
        guard let currentPayload = state.value else {
            await load(symbol: symbol, using: client, cacheNamespace: cacheNamespace, force: force, intent: .automatic)
            return
        }

        if isRefreshing {
            return
        }

        isRefreshing = true
        isShowingCachedSnapshot = true
        activityMessage = "正在刷新 AI 洞察…"

        do {
            let overlay = try await client.fetchHoldingDetailAI(symbol: symbol, refresh: force)
            let mergedPayload = HoldingDetailPayload(
                generatedAt: currentPayload.generatedAt,
                analysisDateCn: currentPayload.analysisDateCn,
                shareMode: currentPayload.shareMode,
                hero: currentPayload.hero,
                sourceMeta: currentPayload.sourceMeta,
                executiveSummary: overlay.executiveSummary,
                focusCards: currentPayload.focusCards,
                signalRows: currentPayload.signalRows,
                signalMatrix: currentPayload.signalMatrix,
                portfolioContext: currentPayload.portfolioContext,
                priceCards: currentPayload.priceCards,
                accountRows: currentPayload.accountRows,
                relatedTrades: currentPayload.relatedTrades,
                derivativeRows: currentPayload.derivativeRows,
                bullCase: overlay.bullCase,
                bearCase: overlay.bearCase,
                watchlist: overlay.watchlist,
                actionPlan: overlay.actionPlan,
                peers: currentPayload.peers,
                history: currentPayload.history,
                comparisonHistory: currentPayload.comparisonHistory,
                holdingNote: currentPayload.holdingNote
            )
            state = .loaded(mergedPayload)
            isRefreshing = false
            isShowingCachedSnapshot = false
            activityMessage = overlay.aiStatusMessage
            Self.storeCachedPayload(mergedPayload, for: symbol, cacheNamespace: cacheNamespace)
        } catch {
            isRefreshing = false
            isShowingCachedSnapshot = true
            activityMessage = "AI 洞察暂时无法更新，先保留当前结果"
        }
    }

    private var isCacheFresh: Bool {
        guard let lastUpdatedAt else {
            return false
        }
        return Date().timeIntervalSince(lastUpdatedAt) < Self.refreshInterval
    }

    private func prepareStateIfNeeded(for symbol: String, cacheNamespace: String? = nil) {
        let normalizedNamespace = Self.normalizedCacheNamespace(cacheNamespace)
        guard currentSymbol != symbol || currentCacheNamespace != normalizedNamespace else {
            return
        }

        currentSymbol = symbol
        currentCacheNamespace = normalizedNamespace

        guard let snapshot = Self.restoreCachedPayload(for: symbol, cacheNamespace: normalizedNamespace) else {
            state = .idle
            activityMessage = nil
            isShowingCachedSnapshot = false
            lastUpdatedAt = nil
            return
        }

        state = .loaded(snapshot.payload)
        activityMessage = "已载入 \(symbol) 的最近结果"
        isShowingCachedSnapshot = true
        lastUpdatedAt = snapshot.cachedAt
    }

    private nonisolated static func normalizedCacheNamespace(_ namespace: String?) -> String {
        let trimmed = namespace?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : "anonymous"
    }

    private nonisolated static func cacheKey(for symbol: String, cacheNamespace: String? = nil) -> String {
        cacheKeyPrefix + normalizedCacheNamespace(cacheNamespace) + "." + symbol.uppercased()
    }

    private nonisolated static func restoreCachedPayload(
        for symbol: String,
        cacheNamespace: String? = nil
    ) -> CachedSnapshot<HoldingDetailPayload>? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: symbol, cacheNamespace: cacheNamespace)) else {
            return nil
        }
        return try? JSONDecoder().decode(CachedSnapshot<HoldingDetailPayload>.self, from: data)
    }

    private nonisolated static func storeCachedPayload(
        _ payload: HoldingDetailPayload,
        for symbol: String,
        cacheNamespace: String? = nil
    ) {
        let snapshot = CachedSnapshot(cachedAt: .now, payload: payload)
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        UserDefaults.standard.set(data, forKey: cacheKey(for: symbol, cacheNamespace: cacheNamespace))
    }
}
