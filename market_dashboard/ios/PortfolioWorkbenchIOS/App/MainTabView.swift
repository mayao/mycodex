import SwiftUI

private enum AppTab: String, Hashable {
    case overview
    case holdings
    case accounts
    case settings
}

private enum AppLaunchOptions {
    static let initialTabEnvironmentKey = "PORTFOLIO_WORKBENCH_INITIAL_TAB"

    static var initialTab: AppTab {
        guard let rawValue = ProcessInfo.processInfo.environment[initialTabEnvironmentKey]?.lowercased(),
              let tab = AppTab(rawValue: rawValue) else {
            return .overview
        }
        return tab
    }
}

struct MainTabView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var dashboardStore: PortfolioDashboardStore
    @State private var selectedTab = AppLaunchOptions.initialTab

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewScreen()
                .tag(AppTab.overview)
                .tabItem {
                    Label("总览", systemImage: "chart.pie.fill")
                }

            HoldingsScreen()
                .tag(AppTab.holdings)
                .tabItem {
                    Label("持仓", systemImage: "chart.line.uptrend.xyaxis")
                }

            AccountsScreen()
                .tag(AppTab.accounts)
                .tabItem {
                    Label("账户", systemImage: "building.columns.fill")
                }

            SettingsScreen()
                .tag(AppTab.settings)
                .tabItem {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
        }
        .transientSyncBanner(
            message: dashboardStore.activityMessage,
            isRefreshing: dashboardStore.isRefreshing,
            isStale: dashboardStore.isShowingCachedSnapshot
        )
        .task {
            await bootstrap()
        }
        .task(id: holdingPrefetchSignature) {
            await prefetchHoldingDetails()
        }
    }

    private func bootstrap() async {
        dashboardStore.setSessionUserID(settings.cacheNamespace)
        do {
            let client = try await settings.makeValidatedClient()
            await dashboardStore.prime(using: client)
            if case let .failed(message) = dashboardStore.state,
               message.contains("请先登录") {
                settings.clearAuthentication()
            }
        } catch {
            dashboardStore.setError(error.localizedDescription)
        }
    }

    private func refresh(force: Bool) async {
        do {
            let client = try await settings.makeValidatedClient()
            await dashboardStore.load(
                using: client,
                force: force,
                fast: false,
                allowLoadedRefresh: true
            )
        } catch {
            dashboardStore.setError(error.localizedDescription)
        }
    }

    private var holdingPrefetchSignature: String {
        orderedHoldingSymbols.joined(separator: "|")
    }

    private func prefetchHoldingDetails() async {
        guard !orderedHoldingSymbols.isEmpty else {
            return
        }

        do {
            let client = try await settings.makeValidatedClient()
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
}
