import SwiftUI
import Charts
import PortfolioWorkbenchMobileCore

struct HoldingDetailScreen: View {
    let symbol: String

    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var viewModel = HoldingDetailViewModel()
    @State private var aiChatContext: AIChatContext?

    var body: some View {
        AppBackdrop {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    LoadingStageCard(
                        title: "正在加载 \(symbol)",
                        detail: "正在准备价格与分析",
                        footnote: "稍后即可查看走势、信号和操作要点。"
                    )
                    .padding(16)

                case let .failed(message):
                    ScrollView {
                        EmptyStateCard(
                            title: "个股详情暂不可用",
                            message: message,
                            actionTitle: "重试"
                        ) {
                            Task { await load(force: true, intent: .market) }
                        }
                        .padding(16)
                    }

                case let .loaded(payload):
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            heroSection(payload)
                            focusSection(payload)
                            priceTrendSection(payload)
                            signalSection(payload)
                            signalMatrixSection(payload)
                            actionPlanSection(payload)
                            noteSection(payload)
                            accountSection(payload)
                            tradeSection(payload)
                            peerSection(payload)
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                    .refreshable {
                        await load(force: true, intent: .market)
                    }
                }
            }
        }
        .navigationTitle(symbol)
        .appInlineNavigationTitle()
        .transientSyncBanner(
            message: viewModel.activityMessage,
            isRefreshing: viewModel.isRefreshing,
            isStale: viewModel.isShowingCachedSnapshot
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SensitiveToggleToolbarButton()
                Button {
                    Task { await load(force: true, intent: .market) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .tint(BrokerPalette.cyan)
                Button {
                    Task { await refreshAI(force: true) }
                } label: {
                    Image(systemName: "sparkles")
                }
                .tint(BrokerPalette.gold)
                Button {
                    aiChatContext = .holding(symbol: symbol, title: detailChatTitle)
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .tint(BrokerPalette.teal)
            }
        }
        .task {
            await load(force: false, intent: .automatic)
        }
        .sheet(item: $aiChatContext) { context in
            AIChatScreen(context: context)
        }
    }

    private func load(force: Bool, intent: HoldingDetailRefreshIntent) async {
        do {
            let client = try await settings.makeValidatedClient()
            await viewModel.load(
                symbol: symbol,
                using: client,
                cacheNamespace: settings.cacheNamespace,
                force: force,
                intent: intent
            )
        } catch {
            viewModel.setError(error.localizedDescription)
        }
    }

    private func refreshAI(force: Bool) async {
        do {
            let client = try await settings.makeValidatedClient()
            await viewModel.refreshAI(
                symbol: symbol,
                using: client,
                cacheNamespace: settings.cacheNamespace,
                force: force
            )
        } catch {
            viewModel.setError(error.localizedDescription)
        }
    }

    private var detailChatTitle: String {
        viewModel.state.value?.hero.name ?? symbol
    }

    private func heroSection(_ payload: HoldingDetailPayload) -> some View {
        SectionPanel(title: payload.hero.name, subtitle: payload.hero.symbol) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    TagBadge(text: payload.hero.styleLabel, tint: BrokerPalette.cyan)
                    TagBadge(text: payload.hero.fundamentalLabel, tint: BrokerPalette.teal)
                    TagBadge(text: payload.hero.signalZone, tint: signalScoreColor(payload.hero.signalScore))
                }

                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NumberFormatters.currency(payload.hero.currentPrice, code: payload.hero.symbol.hasSuffix(".HK") ? "HK$" : "USD"))
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(BrokerPalette.ink)
                            .monospacedDigit()

                        Text(payload.hero.categoryName)
                            .font(.subheadline)
                            .foregroundStyle(BrokerPalette.muted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(NumberFormatters.signedPercent(payload.hero.changePct))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(NumberFormatters.pnlColor(payload.hero.changePct))
                            .monospacedDigit()
                        Text("5D \(NumberFormatters.signedPercent(payload.hero.changePct5d))")
                            .font(.footnote)
                            .foregroundStyle(NumberFormatters.pnlColor(payload.hero.changePct5d))
                            .monospacedDigit()
                    }
                }

                HStack(spacing: 8) {
                    TagBadge(text: payload.sourceMeta.priceSourceLabel, tint: BrokerPalette.teal)
                    TagBadge(text: payload.sourceMeta.tradeDate, tint: BrokerPalette.gold)
                }

                if let newsHeadline = payload.hero.newsHeadline, !newsHeadline.isEmpty {
                    Text(newsHeadline)
                        .font(.subheadline)
                        .foregroundStyle(BrokerPalette.ink)
                }
            }
        }
    }

    private func focusSection(_ payload: HoldingDetailPayload) -> some View {
        SectionPanel(title: "执行摘要") {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(payload.focusCards) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrokerPalette.muted)
                                Text(displayFocusValue(item.value, label: item.label))
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(BrokerPalette.ink)
                            }
                            .padding(14)
                            .frame(width: 156, alignment: .leading)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                }

                bulletList(payload.executiveSummary, tint: BrokerPalette.cyan)
            }
        }
    }

    private func priceTrendSection(_ payload: HoldingDetailPayload) -> some View {
        SectionPanel(title: "价格轨迹") {
            VStack(alignment: .leading, spacing: 16) {
                Chart {
                    ForEach(payload.history.compactMap(chartPoint(for:)), id: \.date) { point in
                        AreaMark(
                            x: .value("日期", point.date),
                            y: .value("价格", point.value)
                        )
                        .foregroundStyle(BrokerPalette.cyan.opacity(0.18))

                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("价格", point.value)
                        )
                        .foregroundStyle(BrokerPalette.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(height: 220)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(BrokerPalette.line)
                        AxisValueLabel {
                            if let rawValue = value.as(Double.self) {
                                Text(NumberFormatters.grouped(rawValue))
                                    .font(.caption2)
                                    .foregroundStyle(BrokerPalette.muted)
                            }
                        }
                    }
                }

                if !payload.comparisonHistory.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(payload.comparisonHistory.prefix(4)) { row in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(row.symbol)
                                            .font(.headline)
                                            .foregroundStyle(BrokerPalette.ink)
                                        if row.isTarget {
                                            TagBadge(text: "当前持仓", tint: BrokerPalette.cyan)
                                        }
                                    }

                                    Chart {
                                        ForEach(row.points.compactMap(chartPoint(for:)), id: \.date) { point in
                                            LineMark(
                                                x: .value("日期", point.date),
                                                y: .value("价格", point.value)
                                            )
                                            .foregroundStyle(row.isTarget ? BrokerPalette.cyan : BrokerPalette.gold)
                                        }
                                    }
                                    .frame(height: 80)
                                    .chartXAxis(.hidden)
                                    .chartYAxis(.hidden)

                                    Text(row.name)
                                        .font(.caption)
                                        .foregroundStyle(BrokerPalette.muted)
                                        .lineLimit(2)
                                }
                                .padding(14)
                                .frame(width: 180, alignment: .leading)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }

    private func signalSection(_ payload: HoldingDetailPayload) -> some View {
        SectionPanel(title: "信号拆解") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(payload.signalRows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(row.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrokerPalette.ink)
                            Spacer()
                            Text("\(row.score)")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(factorToneColor(row.score))
                                .monospacedDigit()
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(factorToneColor(row.score))
                                    .frame(width: proxy.size.width * CGFloat(min(max(Double(row.score + 2) / 4.0, 0.0), 1.0)))
                            }
                        }
                        .frame(height: 8)

                        Text(row.comment)
                            .font(.footnote)
                            .foregroundStyle(BrokerPalette.muted)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(payload.priceCards) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrokerPalette.muted)
                                Text(item.value)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(BrokerPalette.ink)
                                if let delta = item.delta {
                                    Text(delta)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(delta.contains("-") ? BrokerPalette.red : BrokerPalette.green)
                                }
                            }
                            .padding(14)
                            .frame(width: 156, alignment: .leading)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func signalMatrixSection(_ payload: HoldingDetailPayload) -> some View {
        SectionPanel(title: "同组信号矩阵") {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("标的")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BrokerPalette.muted)
                                .frame(width: 88, alignment: .leading)

                            ForEach(payload.signalMatrix.columns) { column in
                                Text(column.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(BrokerPalette.muted)
                                    .frame(width: 52)
                            }
                        }

                        ForEach(payload.signalMatrix.rows.prefix(5)) { row in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.symbol)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BrokerPalette.ink)
                                    Text(row.signalZone)
                                        .font(.caption2)
                                        .foregroundStyle(signalScoreColor(row.signalScore))
                                }
                                .frame(width: 88, alignment: .leading)

                                ForEach(row.cells) { cell in
                                    Text("\(cell.score)")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(BrokerPalette.ink)
                                        .frame(width: 52, height: 34)
                                        .background(factorToneColor(cell.score).opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func actionPlanSection(_ payload: HoldingDetailPayload) -> some View {
        SectionPanel(title: "行动计划") {
            bulletList(payload.actionPlan, tint: BrokerPalette.gold)
        }
    }

    private func noteSection(_ payload: HoldingDetailPayload) -> some View {
        SectionPanel(title: "定位与动作", subtitle: payload.holdingNote.categoryName) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    TagBadge(text: payload.holdingNote.role, tint: BrokerPalette.cyan)
                    TagBadge(text: payload.holdingNote.stance, tint: BrokerPalette.gold)
                    TagBadge(text: "权重 \(NumberFormatters.percent(payload.holdingNote.weightPct))", tint: BrokerPalette.teal)
                }

                LabelValueRow(label: "逻辑", value: payload.holdingNote.thesis)
                LabelValueRow(label: "风险", value: payload.holdingNote.risk, valueColor: BrokerPalette.gold)
                LabelValueRow(label: "动作", value: payload.holdingNote.action)
                LabelValueRow(label: "跟踪", value: payload.holdingNote.watchItems)

                Divider().overlay(BrokerPalette.line)

                Text("看多情形")
                    .font(.headline)
                    .foregroundStyle(BrokerPalette.ink)
                bulletList(payload.bullCase, tint: BrokerPalette.green)

                Text("看空情形")
                    .font(.headline)
                    .foregroundStyle(BrokerPalette.ink)
                bulletList(payload.bearCase, tint: BrokerPalette.red)

                Text("观察清单")
                    .font(.headline)
                    .foregroundStyle(BrokerPalette.ink)
                bulletList(payload.watchlist, tint: BrokerPalette.gold)
            }
        }
    }

    private func accountSection(_ payload: HoldingDetailPayload) -> some View {
        SectionPanel(title: "组合映射", subtitle: payload.accountRows.isEmpty ? nil : "\(payload.accountRows.count) 个账户") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(payload.portfolioContext) { row in
                    LabelValueRow(label: row.label, value: row.value)
                }

                Divider().overlay(BrokerPalette.line)

                ForEach(payload.accountRows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(row.label)
                                .font(.headline)
                                .foregroundStyle(BrokerPalette.ink)
                            Spacer()
                            Text(row.accountId)
                                .font(.caption)
                                .foregroundStyle(BrokerPalette.muted)
                        }

                        LabelValueRow(label: "数量", value: NumberFormatters.grouped(row.quantity))
                        LabelValueRow(label: "市值", value: NumberFormatters.hkd(row.statementValue))
                        LabelValueRow(
                            label: "盈亏率",
                            value: NumberFormatters.signedPercent(row.statementPnlPct),
                            valueColor: NumberFormatters.pnlColor(row.statementPnlPct)
                        )
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }

    private func tradeSection(_ payload: HoldingDetailPayload) -> some View {
        SectionPanel(title: "交易与衍生品") {
            VStack(alignment: .leading, spacing: 12) {
                if payload.relatedTrades.isEmpty {
                    Text("最近没有与该标的直接相关的交易。")
                        .font(.footnote)
                        .foregroundStyle(BrokerPalette.muted)
                } else {
                    ForEach(payload.relatedTrades) { trade in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(trade.side) \(NumberFormatters.grouped(trade.quantity ?? 0))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrokerPalette.ink)
                                Spacer()
                                Text(trade.date)
                                    .font(.caption)
                                    .foregroundStyle(BrokerPalette.muted)
                            }

                            Text("\(trade.broker) · \(trade.currency) \(NumberFormatters.grouped(trade.price ?? 0))")
                                .font(.footnote)
                                .foregroundStyle(BrokerPalette.muted)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }

                if !payload.derivativeRows.isEmpty {
                    Divider().overlay(BrokerPalette.line)

                    ForEach(payload.derivativeRows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.description)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrokerPalette.ink)
                            Text(
                                "名义 HKD \(SensitiveValueMask.display(NumberFormatters.grouped(row.estimatedNotionalHkd ?? 0), hidden: settings.hideSensitiveAmounts))"
                            )
                                .font(.footnote)
                                .foregroundStyle(BrokerPalette.muted)
                        }
                    }
                }
            }
        }
    }

    private func peerSection(_ payload: HoldingDetailPayload) -> some View {
        SectionPanel(title: "同组对比", subtitle: payload.peers.isEmpty ? nil : "\(payload.peers.count) 个同组标的") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(payload.peers) { peer in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(peer.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BrokerPalette.cyan)
                            Text(peer.name)
                                .font(.headline)
                                .foregroundStyle(BrokerPalette.ink)
                            SparklineView(points: peer.normalizedHistory.compactMap(\.price), color: signalScoreColor(peer.signalScore))
                            Text(peer.signalZone)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(signalScoreColor(peer.signalScore))
                            Text(NumberFormatters.signedPercent(peer.changePct))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(NumberFormatters.pnlColor(peer.changePct))
                        }
                        .padding(14)
                        .frame(width: 170, alignment: .leading)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            }
        }
    }

    private func bulletList(_ items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(BrokerPalette.ink)
                }
            }
        }
    }

    private func displayFocusValue(_ value: String, label: String) -> String {
        guard settings.hideSensitiveAmounts, SensitiveValueMask.shouldHide(label: label) else {
            return value
        }
        return SensitiveValueMask.masked(value)
    }

    private func factorToneColor(_ score: Int) -> Color {
        if score >= 1 { return BrokerPalette.green }
        if score == 0 { return BrokerPalette.cyan }
        if score == -1 { return BrokerPalette.gold }
        return BrokerPalette.red
    }

    private func signalScoreColor(_ score: Int) -> Color {
        if score >= 62 { return BrokerPalette.green }
        if score >= 48 { return BrokerPalette.cyan }
        if score >= 36 { return BrokerPalette.gold }
        return BrokerPalette.red
    }

    private func chartPoint(for point: HoldingDetailSeriesPoint) -> (date: String, value: Double)? {
        guard let value = point.price else {
            return nil
        }
        return (point.date, value)
    }
}
