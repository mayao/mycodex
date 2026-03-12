import SwiftUI
import Charts
import PortfolioWorkbenchMobileCore

struct AccountsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var dashboardStore: PortfolioDashboardStore

    var body: some View {
        NavigationStack {
            AppBackdrop {
                Group {
                    switch dashboardStore.state {
                    case .idle, .loading:
                        LoadingStageCard(
                            title: "正在读取账户",
                            detail: "正在整理账户与交易信息",
                            footnote: "很快即可查看账户、交易和结单更新。"
                        )
                        .padding(16)

                    case let .failed(message):
                        ScrollView {
                            EmptyStateCard(
                                title: "账户页暂不可用",
                                message: message,
                                actionTitle: "重试"
                            ) {
                                Task { await refresh(force: true) }
                            }
                            .padding(16)
                        }

                    case let .loaded(payload):
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                if payload.accounts.isEmpty {
                                    emptyPortfolioSection(payload)
                                } else {
                                    accountsSection(payload)
                                    tradesSection(payload)
                                    derivativesSection(payload)
                                }
                                updateGuideSection(payload)
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
            .navigationTitle("账户")
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
                }
            }
        }
    }

    private func emptyPortfolioSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "还没有账户数据", subtitle: "先接入你的账户数据后，这里就会展示账户与交易信息。") {
            VStack(alignment: .leading, spacing: 12) {
                Text("可以先到设置页的“更新结单”上传第一份 PDF，后续再逐步补齐更多账户。")
                    .font(.subheadline)
                    .foregroundStyle(BrokerPalette.muted)

                HStack(spacing: 8) {
                    TagBadge(text: "支持结单导入", tint: BrokerPalette.cyan)
                    TagBadge(text: "支持后续扩展", tint: BrokerPalette.teal)
                }

                if let firstAction = payload.actionCenter.priorityActions.first {
                    InsightCardView(
                        title: firstAction.title,
                        detail: firstAction.detail,
                        tone: .neutral
                    )
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

    private func accountsSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "账户总览") {
            VStack(alignment: .leading, spacing: 12) {
                Chart(payload.accounts.prefix(6)) { account in
                    BarMark(
                        x: .value("账户", "\(account.broker)-\(account.accountId.suffix(4))"),
                        y: .value("净资产", account.navHkd)
                    )
                    .foregroundStyle(BrokerPalette.cyan)
                }
                .frame(height: 180)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(BrokerPalette.line)
                        AxisValueLabel {
                            if let rawValue = value.as(Double.self) {
                                Text(settings.hideSensitiveAmounts ? "•••" : NumberFormatters.grouped(rawValue))
                                    .font(.caption2)
                                    .foregroundStyle(BrokerPalette.muted)
                            }
                        }
                    }
                }

                ForEach(payload.accounts) { account in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.broker)
                                    .font(.headline)
                                    .foregroundStyle(BrokerPalette.ink)
                                Text(account.accountId)
                                    .font(.caption)
                                    .foregroundStyle(BrokerPalette.muted)
                            }

                            Spacer()

                            TagBadge(
                                text: loadStatusLabel(account.loadStatus),
                                tint: BrokerPalette.sourceStatus(account.loadStatus)
                            )
                        }

                        LabelValueRow(label: "净资产", value: NumberFormatters.hkd(account.navHkd))
                        LabelValueRow(label: "持仓市值", value: NumberFormatters.hkd(account.holdingsValueHkd))
                        LabelValueRow(
                            label: "融资占用",
                            value: NumberFormatters.hkd(account.financingHkd),
                            valueColor: account.financingHkd > 0 ? BrokerPalette.gold : BrokerPalette.ink
                        )
                        LabelValueRow(label: "头部标的", value: account.topNames ?? "暂无")

                        HStack(spacing: 8) {
                            TagBadge(text: "持仓 \(account.holdingCount)", tint: BrokerPalette.cyan)
                            TagBadge(text: "交易 \(account.tradeCount)", tint: BrokerPalette.teal)
                            TagBadge(text: "衍生品 \(account.derivativeCount)", tint: BrokerPalette.orange)
                        }

                        if let issue = account.issue, !issue.isEmpty {
                            Text(issue)
                                .font(.footnote)
                                .foregroundStyle(BrokerPalette.red)
                        } else if let fileName = account.fileName {
                            Text(fileName)
                                .font(.footnote)
                                .foregroundStyle(BrokerPalette.muted)
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
        }
    }

    private func tradesSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "最近交易") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(payload.recentTrades.prefix(8)) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(item.side) \(item.name)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrokerPalette.ink)
                            Spacer()
                            Text(item.date)
                                .font(.caption)
                                .foregroundStyle(BrokerPalette.muted)
                        }

                        Text("\(item.broker) · \(item.symbol) · \(item.currency) \(NumberFormatters.grouped(item.price)) × \(NumberFormatters.grouped(item.quantity))")
                            .font(.footnote)
                            .foregroundStyle(BrokerPalette.muted)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }

    private func derivativesSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "衍生品 / 结构化敞口") {
            VStack(alignment: .leading, spacing: 12) {
                if payload.derivatives.isEmpty {
                    Text("当前没有衍生品或结构化头寸。")
                        .font(.footnote)
                        .foregroundStyle(BrokerPalette.muted)
                } else {
                    ForEach(payload.derivatives.prefix(8)) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.description)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrokerPalette.ink)

                            LabelValueRow(label: "券商", value: item.broker)
                            LabelValueRow(label: "数量", value: NumberFormatters.grouped(item.quantity))
                            LabelValueRow(label: "名义 HKD", value: NumberFormatters.grouped(item.estimatedNotionalHkd ?? 0))
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        }
    }

    private func updateGuideSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(title: "操作提示") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(payload.updateGuide, id: \.self) { item in
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
        }
    }
}
