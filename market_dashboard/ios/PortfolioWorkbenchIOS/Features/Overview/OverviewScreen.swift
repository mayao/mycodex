import SwiftUI
import Charts
import PortfolioWorkbenchMobileCore

private struct MarketPulseStockFocus: Identifiable {
    let id: String
    let title: String
    let selectionReason: String?
    let impactNote: String
    let advice: String
    let tone: MobileTone?
    let position: MobilePosition
}

struct OverviewScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var dashboardStore: PortfolioDashboardStore

    @State private var selectedDrilldown: OverviewDrilldownItem?
    @State private var aiChatContext: AIChatContext?

    var body: some View {
        NavigationStack {
            AppBackdrop {
                Group {
                    switch dashboardStore.state {
                    case .idle, .loading:
                        LoadingStageCard(
                            title: "正在进入 MyInvAI",
                            detail: "正在准备组合总览",
                            footnote: "很快就能查看关键指标、市场动态和持仓重点。"
                        )
                        .padding(16)

                    case let .failed(message):
                        ScrollView {
                            EmptyStateCard(
                                title: "总览暂不可用",
                                message: message,
                                actionTitle: "重新加载"
                            ) {
                                Task { await refresh(force: true) }
                            }
                            .padding(16)
                        }

                    case let .loaded(payload):
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                summarySection(payload)
                                marketPulseSection(payload)
                                spotlightSection(payload)
                                allocationSection(payload)
                                accountExposureSection(payload)
                                radarSection(payload)
                                macroSection(payload)
                                driversSection(payload)
                                actionSection(payload)
                                strategySection(payload)
                            }
                            .padding(16)
                            .padding(.bottom, 28)
                        }
                        .refreshable {
                            await refresh(force: true)
                        }
                    }
                }
            }
            .navigationTitle("总览")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    SensitiveToggleToolbarButton()
                    Button {
                        Task { await refresh(force: true) }
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
                        aiChatContext = .dashboard
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                    .tint(BrokerPalette.teal)
                }
            }
        }
        .sheet(item: $selectedDrilldown) { item in
            OverviewDrilldownScreen(item: item)
        }
        .sheet(item: $aiChatContext) { context in
            AIChatScreen(context: context)
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

    private func refreshAI(force: Bool) async {
        do {
            let client = try await settings.makeValidatedClient()
            await dashboardStore.refreshAI(using: client, force: force)
        } catch {
            dashboardStore.setError(error.localizedDescription)
        }
    }

    private func summarySection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "核心指标") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(payload.summaryCards) { card in
                        Button {
                            selectedDrilldown = summaryDrilldown(for: card)
                        } label: {
                            SummaryCardView(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func marketPulseSection(_ payload: MobileDashboardPayload) -> some View {
        let macroCatalysts = payload.marketPulse.catalysts.filter { $0.category != "个股" }
        let stockFocuses = marketPulseStockFocuses(payload)
        let focusPositions = stockFocuses.map(\.position)

        return SectionPanel(title: "市场脉冲", subtitle: payload.marketPulse.headline) {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    selectedDrilldown = marketPulseDigestDrilldown(payload.marketPulse)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TagBadge(text: payload.analysisDateCn, tint: BrokerPalette.gold)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(BrokerPalette.cyan)
                        }

                        Text(payload.marketPulse.summary)
                            .font(.subheadline)
                            .foregroundStyle(BrokerPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        if !payload.marketPulse.suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(payload.marketPulse.suggestions.prefix(5)), id: \.self) { suggestion in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(BrokerPalette.cyan)
                                            .frame(width: 6, height: 6)
                                            .padding(.top, 6)
                                        Text(suggestion)
                                            .font(.footnote)
                                            .foregroundStyle(BrokerPalette.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(BrokerPalette.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                if !macroCatalysts.isEmpty {
                    marketPulseSectionHeader(
                        title: "宏观变量",
                        detail: "先看哪些外部变量在驱动今天的组合"
                    )
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(macroCatalysts) { catalyst in
                                Button {
                                    selectedDrilldown = marketPulseCatalystDrilldown(for: catalyst)
                                } label: {
                                    marketPulseCatalystCard(catalyst)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !stockFocuses.isEmpty {
                    marketPulseSectionHeader(
                        title: "个股关注",
                        detail: "今日优先跟踪的重点标的"
                    )

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(stockFocuses) { focus in
                                NavigationLink {
                                    HoldingDetailScreen(symbol: focus.position.symbol)
                                } label: {
                                    marketPulseStockFocusCard(focus)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !focusPositions.isEmpty {
                    Chart(focusPositions) { position in
                        BarMark(
                            x: .value("变化", position.changePct ?? 0),
                            y: .value("标的", position.symbol)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle((position.changePct ?? 0) >= 0 ? BrokerPalette.green : BrokerPalette.red)
                    }
                    .chartXAxis {
                        AxisMarks(position: .bottom) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(BrokerPalette.line)
                            AxisValueLabel {
                                if let rawValue = value.as(Double.self) {
                                    Text(NumberFormatters.signedPercent(rawValue))
                                        .font(.caption2)
                                        .foregroundStyle(BrokerPalette.muted)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let symbol = value.as(String.self) {
                                    Text(symbol)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(BrokerPalette.ink)
                                }
                            }
                        }
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    private func spotlightSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "头部持仓") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array((payload.spotlightPositions.isEmpty ? payload.positions : payload.spotlightPositions).prefix(6))) { position in
                    NavigationLink {
                        HoldingDetailScreen(symbol: position.symbol)
                    } label: {
                        PositionCompactCard(position: position)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func allocationSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "仓位分布") {
            VStack(alignment: .leading, spacing: 14) {
                allocationRow(title: "主题", rows: Array(payload.allocationGroups.themes.prefix(4)), tint: BrokerPalette.cyan)
                allocationRow(title: "市场", rows: Array(payload.allocationGroups.markets.prefix(4)), tint: BrokerPalette.teal)
                allocationRow(title: "券商", rows: Array(payload.allocationGroups.brokers.prefix(4)), tint: BrokerPalette.gold)
            }
        }
    }

    private func accountExposureSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "账户资金视图") {
            VStack(alignment: .leading, spacing: 16) {
                Chart(payload.accounts.prefix(6)) { account in
                    BarMark(
                        x: .value("账户", "\(account.broker)-\(account.accountId.suffix(4))"),
                        y: .value("净资产", account.navHkd)
                    )
                    .foregroundStyle(BrokerPalette.cyan)

                    BarMark(
                        x: .value("账户", "\(account.broker)-\(account.accountId.suffix(4))"),
                        y: .value("融资", account.financingHkd)
                    )
                    .foregroundStyle(BrokerPalette.gold.opacity(0.75))
                }
                .chartLegend(position: .top, alignment: .leading)
                .chartForegroundStyleScale([
                    "净资产": BrokerPalette.cyan,
                    "融资": BrokerPalette.gold,
                ])
                .frame(height: 220)

                ForEach(payload.accounts.prefix(3)) { account in
                    HStack(spacing: 10) {
                        TagBadge(text: account.broker, tint: BrokerPalette.cyan)
                        TagBadge(
                            text: "NAV \(SensitiveValueMask.display(NumberFormatters.hkd(account.navHkd), hidden: settings.hideSensitiveAmounts))",
                            tint: BrokerPalette.teal
                        )
                        if account.financingHkd > 0 {
                            TagBadge(
                                text: "融资 \(SensitiveValueMask.display(NumberFormatters.hkd(account.financingHkd), hidden: settings.hideSensitiveAmounts))",
                                tint: BrokerPalette.gold
                            )
                        }
                    }
                }
            }
        }
    }

    private func radarSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "组合雷达") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(payload.healthRadar) { item in
                        Button {
                            selectedDrilldown = radarDrilldown(for: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(item.label)
                                        .font(.headline)
                                        .foregroundStyle(BrokerPalette.ink)
                                    Spacer()
                                    Text(String(format: "%.0f", item.value))
                                        .font(.system(.title3, design: .rounded, weight: .heavy))
                                        .foregroundStyle(radarScoreColor(item.value))
                                }

                                Text(item.summary)
                                    .font(.footnote)
                                    .foregroundStyle(BrokerPalette.muted)
                                    .lineLimit(3)
                            }
                            .padding(14)
                            .frame(width: 190, alignment: .leading)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func macroSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "宏观主题") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(payload.macroTopics) { item in
                        Button {
                            selectedDrilldown = macroDrilldown(for: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    TagBadge(text: item.severity, tint: BrokerPalette.severity(item.severity))
                                    Spacer()
                                    Text(NumberFormatters.percent(item.impactWeightPct))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(BrokerPalette.severity(item.severity))
                                        .monospacedDigit()
                                }

                                Text(item.name)
                                    .font(.headline)
                                    .foregroundStyle(BrokerPalette.ink)

                                Text(item.headline)
                                    .font(.subheadline)
                                    .foregroundStyle(BrokerPalette.ink.opacity(0.92))
                                    .lineLimit(3)

                                Text(item.summary)
                                    .font(.footnote)
                                    .foregroundStyle(BrokerPalette.muted)
                                    .lineLimit(4)
                            }
                            .padding(16)
                            .frame(width: 286, alignment: .leading)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func driversSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "驱动与风险") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(payload.keyDrivers.prefix(3))) { item in
                    Button {
                        selectedDrilldown = insightDrilldown(item, groupTitle: "核心驱动")
                    } label: {
                        InsightCardView(title: item.title, detail: item.detail, tone: item.tone)
                    }
                    .buttonStyle(.plain)
                }

                if !payload.riskFlags.isEmpty {
                    Divider().overlay(BrokerPalette.line)
                }

                ForEach(Array(payload.riskFlags.prefix(3))) { item in
                    Button {
                        selectedDrilldown = insightDrilldown(item, groupTitle: "风险提示")
                    } label: {
                        InsightCardView(title: item.title, detail: item.detail, tone: item.tone)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func actionSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "动作中心") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(payload.actionBlocks.prefix(4).indices), id: \.self) { index in
                    let block = payload.actionBlocks[index]
                    Button {
                        selectedDrilldown = actionDrilldown(for: block, index: index, payload: payload)
                    } label: {
                        ActionStreamCard(
                            index: index + 1,
                            label: block.label,
                            title: block.title,
                            detail: actionDetail(for: block, fallbackIndex: index, payload: payload),
                            badge: block.badge,
                            tone: block.tone,
                            isPriority: index == 0
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func strategySection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "策略视图") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(payload.strategyViews) { item in
                        Button {
                            selectedDrilldown = strategyDrilldown(for: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundStyle(BrokerPalette.ink)
                                    Spacer()
                                    ToneBadge(text: item.tag, tone: item.tone)
                                }

                                Text(item.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(BrokerPalette.muted)
                                    .lineLimit(4)
                            }
                            .padding(16)
                            .frame(width: 280, alignment: .leading)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func allocationRow(title: String, rows: [MobileAllocationBucket], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BrokerPalette.muted)

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrokerPalette.ink)
                        Spacer()
                        Text(NumberFormatters.percent(row.weightPct))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(tint)
                            .monospacedDigit()
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(tint.opacity(0.9))
                                .frame(width: max(18, proxy.size.width * CGFloat(min(max(row.weightPct, 0), 100) / 100)))
                        }
                    }
                    .frame(height: 8)

                    if let coreHoldings = row.coreHoldings, !coreHoldings.isEmpty {
                        Text(coreHoldings.joined(separator: "、"))
                            .font(.caption)
                            .foregroundStyle(BrokerPalette.muted)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func actionDetail(
        for block: MobileActionBlock,
        fallbackIndex index: Int,
        payload: MobileDashboardPayload
    ) -> String? {
        if let detail = block.detail, !detail.isEmpty {
            return detail
        }
        guard payload.actionCenter.priorityActions.indices.contains(index) else {
            return nil
        }
        let detail = payload.actionCenter.priorityActions[index].detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? nil : detail
    }

    private func marketPulseSectionHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrokerPalette.ink)

            Text(detail)
                .font(.caption)
                .foregroundStyle(BrokerPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func marketPulseStockFocusCard(_ focus: MarketPulseStockFocus) -> some View {
        let tone = pulseToneColor(focus.tone)
        let position = focus.position

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                TagBadge(text: "个股", tint: tone)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tone)
            }

            Text(position.symbol)
                .font(.headline)
                .foregroundStyle(BrokerPalette.ink)

            Text(position.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrokerPalette.ink.opacity(0.92))
                .lineLimit(1)

            if let selectionReason = focus.selectionReason, !selectionReason.isEmpty {
                Text(selectionReason)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text("权重 \(NumberFormatters.percent(position.weightPct))")
                    .font(.caption)
                    .foregroundStyle(BrokerPalette.muted)

                if let changePct = position.changePct {
                    Text("日内 \(NumberFormatters.signedPercent(changePct))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NumberFormatters.pnlColor(changePct))
                        .monospacedDigit()
                }
            }

            Text(focus.impactNote)
                .font(.caption)
                .foregroundStyle(BrokerPalette.muted)
                .lineLimit(3)

            Text(position.summary ?? focus.advice)
                .font(.caption)
                .foregroundStyle(BrokerPalette.ink.opacity(0.84))
                .lineLimit(3)
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tone.opacity(0.24), lineWidth: 1)
        )
    }

    private func marketPulseCatalystCard(_ catalyst: MobileMarketPulseCatalyst) -> some View {
        let tone = pulseToneColor(catalyst.tone)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                TagBadge(text: catalyst.category, tint: tone)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tone)
            }

            Text(catalyst.title)
                .font(.headline)
                .foregroundStyle(BrokerPalette.ink)
                .lineLimit(2)

            Text(catalyst.headline)
                .font(.footnote)
                .foregroundStyle(BrokerPalette.ink.opacity(0.9))
                .lineLimit(3)

            Text(catalyst.impactNote)
                .font(.caption)
                .foregroundStyle(BrokerPalette.muted)
                .lineLimit(3)
        }
        .padding(16)
        .frame(width: 262, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(tone.opacity(0.24), lineWidth: 1)
        )
    }

    private func summaryDrilldown(for card: MobileSummaryCard) -> OverviewDrilldownItem {
        OverviewDrilldownItem(
            title: card.label,
            subtitle: card.value,
            accent: toneColor(card.tone),
            tags: [
                OverviewDrilldownTag(text: summaryStatusText(card.tone), tint: toneColor(card.tone))
            ],
            sections: [
                OverviewDrilldownSection(title: "完整说明", body: card.detail),
            ],
            relatedSymbols: []
        )
    }

    private func marketPulseDigestDrilldown(_ pulse: MobileMarketPulse) -> OverviewDrilldownItem {
        let macroBullets = pulse.catalysts
            .filter { $0.category != "个股" }
            .map { "\($0.category)：\($0.title)" }
        let stockBullets = pulse.catalysts
            .filter { $0.category == "个股" }
            .map { catalyst in
                if let selectionReason = catalyst.selectionReason, !selectionReason.isEmpty {
                    return "\(selectionReason)：\(catalyst.title)"
                }
                return catalyst.title
            }

        var sections = [
            OverviewDrilldownSection(title: "概要", body: pulse.summary),
        ]
        sections.append(
            OverviewDrilldownSection(
                title: "执行建议",
                body: "",
                bullets: pulse.suggestions
            )
        )
        if !macroBullets.isEmpty {
            sections.append(
                OverviewDrilldownSection(
                    title: "宏观变量",
                    body: "",
                    bullets: macroBullets
                )
            )
        }
        if !stockBullets.isEmpty {
            sections.append(
                OverviewDrilldownSection(
                    title: "个股关注",
                    body: "",
                    bullets: stockBullets
                )
            )
        }

        return OverviewDrilldownItem(
            title: pulse.headline,
            subtitle: "市场脉冲完整摘要",
            accent: BrokerPalette.cyan,
            tags: [OverviewDrilldownTag(text: "今日摘要", tint: BrokerPalette.cyan)],
            sections: sections,
            relatedSymbols: []
        )
    }

    private func marketPulseCatalystDrilldown(for catalyst: MobileMarketPulseCatalyst) -> OverviewDrilldownItem {
        var tags = [
            OverviewDrilldownTag(text: catalyst.category, tint: pulseToneColor(catalyst.tone))
        ]
        if let source = catalyst.source, !source.isEmpty {
            tags.append(OverviewDrilldownTag(text: source, tint: BrokerPalette.gold))
        }
        var sections = [OverviewDrilldownSection(title: "事件概要", body: catalyst.summary)]
        if let selectionReason = catalyst.selectionReason, !selectionReason.isEmpty {
            sections.append(OverviewDrilldownSection(title: "入选逻辑", body: selectionReason))
        }
        sections.append(OverviewDrilldownSection(title: "影响持仓", body: catalyst.impactNote))
        sections.append(OverviewDrilldownSection(title: "建议动作", body: catalyst.advice))
        return OverviewDrilldownItem(
            title: catalyst.title,
            subtitle: catalyst.headline,
            accent: pulseToneColor(catalyst.tone),
            tags: tags,
            sections: sections,
            relatedSymbols: catalyst.relatedSymbols
        )
    }

    private func marketPulseStockFocuses(_ payload: MobileDashboardPayload) -> [MarketPulseStockFocus] {
        let positionsBySymbol = Dictionary(uniqueKeysWithValues: payload.positions.map { ($0.symbol, $0) })
        var focuses: [MarketPulseStockFocus] = payload.marketPulse.catalysts.compactMap { catalyst in
            guard catalyst.category == "个股",
                  let symbol = catalyst.relatedSymbols.first,
                  let position = positionsBySymbol[symbol] else {
                return nil
            }
            return MarketPulseStockFocus(
                id: catalyst.id + "::" + position.symbol,
                title: catalyst.title,
                selectionReason: catalyst.selectionReason,
                impactNote: catalyst.impactNote,
                advice: catalyst.advice,
                tone: catalyst.tone,
                position: position
            )
        }
        var seenSymbols = Set(focuses.map(\.position.symbol))
        let sortedPositions = payload.positions.sorted { $0.weightPct > $1.weightPct }

        func appendPosition(
            _ position: MobilePosition,
            selectionReason: String,
            impactNote: String,
            advice: String? = nil,
            tone: MobileTone? = nil
        ) {
            guard !seenSymbols.contains(position.symbol), focuses.count < 6 else {
                return
            }
            focuses.append(
                MarketPulseStockFocus(
                    id: "derived::" + position.symbol + "::" + selectionReason,
                    title: position.symbol + " · " + position.name,
                    selectionReason: selectionReason,
                    impactNote: impactNote,
                    advice: advice ?? position.action ?? position.summary ?? "围绕趋势、宏观和交易节奏继续跟踪。",
                    tone: tone,
                    position: position
                )
            )
            seenSymbols.insert(position.symbol)
        }

        for trade in payload.recentTrades.prefix(8) {
            guard let position = positionsBySymbol[trade.symbol] else {
                continue
            }
            appendPosition(
                position,
                selectionReason: "近期交易关注",
                impactNote: "最近成交 \(trade.side) · \(trade.date) · 权重 \(NumberFormatters.percent(position.weightPct))",
                tone: trade.side == "卖出" ? .warn : .neutral
            )
        }

        for position in sortedPositions where (position.macroSignal ?? "中性") != "中性" || (position.newsSignal ?? "中性") != "中性" {
            appendPosition(
                position,
                selectionReason: "宏观/新闻关注",
                impactNote: "宏观 \(position.macroSignal ?? "中性") / 新闻 \(position.newsSignal ?? "中性") · 权重 \(NumberFormatters.percent(position.weightPct))",
                tone: (position.macroSignal ?? "中性") == "逆风" || (position.newsSignal ?? "中性").contains("偏空") ? .down : .warn
            )
        }

        for position in sortedPositions where (position.trendState ?? "") == "强势上行" || (position.trendState ?? "") == "修复抬头" || (position.trendState ?? "") == "弱势下行" {
            appendPosition(
                position,
                selectionReason: "趋势影响关注",
                impactNote: "\(position.trendState ?? "无数据") / \(position.signalZone ?? "中性跟踪") · 日内 \(NumberFormatters.signedPercent(position.changePct ?? 0))",
                tone: (position.trendState ?? "") == "弱势下行" ? .down : .up
            )
        }

        for position in sortedPositions where position.fundamentalLabel == "强" || position.fundamentalLabel == "偏弱" || position.fundamentalLabel == "工具属性" {
            appendPosition(
                position,
                selectionReason: "基本面验证关注",
                impactNote: "\(position.fundamentalLabel) · \(position.stance) · 权重 \(NumberFormatters.percent(position.weightPct))",
                tone: position.fundamentalLabel == "偏弱" || position.fundamentalLabel == "工具属性" ? .warn : .up
            )
        }

        return focuses
    }

    private func radarDrilldown(for item: MobileRadarMetric) -> OverviewDrilldownItem {
        OverviewDrilldownItem(
            title: "组合雷达 · \(item.label)",
            subtitle: "当前分数 \(String(format: "%.0f", item.value))",
            accent: radarScoreColor(item.value),
            tags: [
                OverviewDrilldownTag(text: "分数 \(String(format: "%.0f", item.value))", tint: radarScoreColor(item.value))
            ],
            sections: [
                OverviewDrilldownSection(title: "指标说明", body: item.summary),
                OverviewDrilldownSection(title: "执行含义", body: radarGuidance(for: item)),
            ],
            relatedSymbols: []
        )
    }

    private func macroDrilldown(for item: MobileMacroTopic) -> OverviewDrilldownItem {
        var tags = [
            OverviewDrilldownTag(text: item.severity, tint: BrokerPalette.severity(item.severity)),
            OverviewDrilldownTag(text: "影响 \(NumberFormatters.percent(item.impactWeightPct))", tint: BrokerPalette.gold),
        ]
        if let source = item.source, !source.isEmpty {
            tags.append(OverviewDrilldownTag(text: source, tint: BrokerPalette.teal))
        }
        return OverviewDrilldownItem(
            title: item.name,
            subtitle: item.headline,
            accent: BrokerPalette.severity(item.severity),
            tags: tags,
            sections: [
                OverviewDrilldownSection(title: "完整摘要", body: item.summary),
                OverviewDrilldownSection(title: "影响映射", body: item.impactLabels),
                OverviewDrilldownSection(title: "执行提醒", body: macroGuidance(for: item)),
            ],
            relatedSymbols: []
        )
    }

    private func insightDrilldown(_ item: MobileInsightCard, groupTitle: String) -> OverviewDrilldownItem {
        OverviewDrilldownItem(
            title: item.title,
            subtitle: groupTitle,
            accent: toneColor(item.tone),
            tags: [
                OverviewDrilldownTag(text: groupTitle, tint: BrokerPalette.cyan),
                OverviewDrilldownTag(text: summaryStatusText(item.tone), tint: toneColor(item.tone)),
            ],
            sections: [
                OverviewDrilldownSection(title: "完整说明", body: item.detail),
                OverviewDrilldownSection(title: "处理方式", body: insightGuidance(for: item)),
            ],
            relatedSymbols: []
        )
    }

    private func actionDrilldown(
        for block: MobileActionBlock,
        index: Int,
        payload: MobileDashboardPayload
    ) -> OverviewDrilldownItem {
        var tags = [
            OverviewDrilldownTag(text: block.label, tint: BrokerPalette.cyan),
            OverviewDrilldownTag(text: index == 0 ? "首要动作" : "执行项", tint: BrokerPalette.orange),
        ]
        if let badge = block.badge, !badge.isEmpty {
            tags.append(OverviewDrilldownTag(text: badge, tint: toneColor(block.tone)))
        }
        return OverviewDrilldownItem(
            title: block.title,
            subtitle: "动作中心完整说明",
            accent: toneColor(block.tone),
            tags: tags,
            sections: [
                OverviewDrilldownSection(title: "动作说明", body: actionDetail(for: block, fallbackIndex: index, payload: payload) ?? payload.actionCenter.overview),
                OverviewDrilldownSection(title: "组合背景", body: payload.actionCenter.overview),
                OverviewDrilldownSection(title: "执行提醒", body: payload.actionCenter.disclaimer),
            ],
            relatedSymbols: relatedSymbolsForActionBlock(block, payload: payload)
        )
    }

    private func strategyDrilldown(for item: MobileStrategyCard) -> OverviewDrilldownItem {
        OverviewDrilldownItem(
            title: item.title,
            subtitle: item.tag,
            accent: toneColor(item.tone),
            tags: [
                OverviewDrilldownTag(text: item.tag, tint: toneColor(item.tone)),
                OverviewDrilldownTag(text: summaryStatusText(item.tone), tint: BrokerPalette.gold),
            ],
            sections: [
                OverviewDrilldownSection(title: "策略说明", body: item.summary),
                OverviewDrilldownSection(title: "适用场景", body: strategyGuidance(for: item)),
            ],
            relatedSymbols: []
        )
    }

    private func relatedSymbolsForActionBlock(_ block: MobileActionBlock, payload: MobileDashboardPayload) -> [String] {
        let catalog = payload.positions.map(\.symbol)
        let haystack = [block.label, block.title, block.detail ?? ""].joined(separator: " ")
        return catalog.filter { haystack.localizedCaseInsensitiveContains($0) }.prefix(3).map { $0 }
    }

    private func radarGuidance(for item: MobileRadarMetric) -> String {
        if item.value >= 70 {
            return "这一项当前不是组合的主要短板，可以把精力放在维持优势和防止过度放大风险上。"
        }
        if item.value >= 45 {
            return "这项处于可接受但不稳的区间，适合持续跟踪，不要让它变成新的组合拖累。"
        }
        return "这项已经是明显短板，应该优先拆解具体传导链和可执行的修正动作。"
    }

    private func macroGuidance(for item: MobileMacroTopic) -> String {
        if item.score < 0 {
            return "这条宏观线索对相关持仓偏逆风，处理上更应该先看仓位韧性和风险预算，而不是先讨论回本。"
        }
        if item.score > 0 {
            return "这条宏观线索偏顺风，但顺风只代表可以验证，不代表可以无条件追高放大。"
        }
        return "这条宏观线索目前更适合作为观察变量，等下一次数据或政策确认后再决定动作。"
    }

    private func insightGuidance(for item: MobileInsightCard) -> String {
        switch item.tone {
        case .up:
            return "这项更偏机会侧，适合继续验证并决定是否逐步放大。"
        case .warn:
            return "这项处在观察区间，需要把触发条件和失效条件写得更明确。"
        case .down:
            return "这项已经偏风险侧，应该优先考虑如何隔离或压缩暴露。"
        case .neutral, .none:
            return "这项暂时中性，适合维持跟踪，但不要忽略变化速度。"
        }
    }

    private func strategyGuidance(for item: MobileStrategyCard) -> String {
        switch item.title {
        case "自上而下宏观":
            return "适合先判断利率、贸易、政策和增长环境，再决定哪些主题值得放大仓位。"
        case "质量复利":
            return "适合承担底仓和净值稳定器角色，不适合用短线交易心态反复折腾。"
        case "估值修复":
            return "适合在盈利、竞争格局或政策确认改善时参与，不适合单纯为了摊平去加仓。"
        case "趋势动量":
            return "适合围绕趋势是否延续来决定加减仓节奏，弱势阶段不要只盯成本线。"
        case "事件/主题":
            return "更适合使用交易预算管理，避免让高波动主题变成组合核心风险源。"
        case "风险预算":
            return "适合独立于选股观点单独看杠杆、衍生品和集中度，优先管理生存空间。"
        default:
            return "把它当成组合的一种观察框架，用来约束动作节奏，而不是只看单一收益机会。"
        }
    }

    private func radarScoreColor(_ value: Double) -> Color {
        if value >= 70 { return BrokerPalette.green }
        if value >= 45 { return BrokerPalette.gold }
        return BrokerPalette.red
    }

    private func summaryStatusText(_ tone: MobileTone?) -> String {
        switch tone {
        case .up:
            return "稳态"
        case .warn:
            return "关注"
        case .down:
            return "风险"
        case .neutral, .none:
            return "跟踪"
        }
    }

    private func toneColor(_ tone: MobileTone?) -> Color {
        BrokerPalette.tone(tone)
    }

    private func pulseToneColor(_ tone: MobileTone?) -> Color {
        switch tone {
        case .up:
            return BrokerPalette.green
        case .down:
            return BrokerPalette.red
        case .warn:
            return BrokerPalette.orange
        case .neutral, .none:
            return BrokerPalette.cyan
        }
    }
}
