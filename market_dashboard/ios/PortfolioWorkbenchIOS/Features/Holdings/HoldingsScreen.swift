import SwiftUI
import PortfolioWorkbenchMobileCore

private enum HoldingSortMode: String, CaseIterable, Identifiable {
    case weight
    case pnl
    case signal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weight:
            return "按权重"
        case .pnl:
            return "按盈亏"
        case .signal:
            return "按信号"
        }
    }
}

struct HoldingsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var dashboardStore: PortfolioDashboardStore

    @State private var searchText = ""
    @State private var sortMode: HoldingSortMode = .weight

    var body: some View {
        NavigationStack {
            AppBackdrop {
                Group {
                    switch dashboardStore.state {
                    case .idle, .loading:
                        LoadingStageCard(
                            title: "正在读取持仓",
                            detail: "正在整理全部持仓",
                            footnote: "搜索、排序和个股详情会在数据准备好后立即可用。"
                        )
                        .padding(16)

                    case let .failed(message):
                        ScrollView {
                            EmptyStateCard(
                                title: "持仓页暂不可用",
                                message: message,
                                actionTitle: "重试"
                            ) {
                                Task { await refresh(force: true) }
                            }
                            .padding(16)
                        }

                    case let .loaded(payload):
                        let positions = filteredPositions(from: payload.positions)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                filterSection(payload)

                                if positions.isEmpty {
                                    EmptyStateCard(
                                        title: "没有匹配持仓",
                                        message: "试试代码、中文名、英文名或主题关键词。",
                                        actionTitle: "清空搜索"
                                    ) {
                                        searchText = ""
                                    }
                                } else {
                                    ForEach(positions) { position in
                                        NavigationLink {
                                            HoldingDetailScreen(symbol: position.symbol)
                                        } label: {
                                            PositionCompactCard(position: position)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(16)
                            .padding(.bottom, 24)
                        }
                        .refreshable {
                            await refresh(force: true)
                        }
                    }
                }
            }
            .navigationTitle("持仓")
            .appInlineNavigationTitle()
            .searchable(text: $searchText, prompt: "搜索代码 / 名称 / 主题")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    SensitiveToggleToolbarButton()
                    Button {
                        Task { await refresh(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(BrokerPalette.cyan)
                }
            }
        }
    }

    private func refresh(force: Bool) async {
        do {
            let client = try await settings.makeValidatedClient()
            await dashboardStore.refreshVisible(using: client)
        } catch {
            dashboardStore.setError(error.localizedDescription)
        }
    }

    private func filterSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(
            title: "组合视图",
            subtitle: "\(payload.positions.count) 个持仓"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("排序", selection: $sortMode) {
                    ForEach(HoldingSortMode.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if let top = filteredPositions(from: payload.positions).first {
                    HStack(spacing: 10) {
                        TagBadge(text: "头部仓 \(top.symbol)", tint: BrokerPalette.cyan)
                        TagBadge(text: top.stance, tint: BrokerPalette.gold)
                        if let score = top.signalScore {
                            TagBadge(text: "信号 \(score)", tint: BrokerPalette.teal)
                        }
                    }
                }
            }
        }
    }

    private func filteredPositions(from positions: [MobilePosition]) -> [MobilePosition] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = positions.filter { item in
            guard !trimmed.isEmpty else {
                return true
            }

            let haystack = [
                item.symbol,
                item.name,
                item.nameEn ?? "",
                item.categoryName,
                item.styleLabel,
                item.stance
            ]
                .joined(separator: " ")
                .lowercased()

            return haystack.contains(trimmed.lowercased())
        }

        switch sortMode {
        case .weight:
            return filtered.sorted { $0.weightPct > $1.weightPct }
        case .pnl:
            return filtered.sorted { ($0.statementPnlPct ?? -.infinity) > ($1.statementPnlPct ?? -.infinity) }
        case .signal:
            return filtered.sorted { ($0.signalScore ?? 0) > ($1.signalScore ?? 0) }
        }
    }
}
