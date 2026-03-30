import SwiftUI
import UIKit
import PortfolioWorkbenchMobileCore

private enum HoldingSortMode: String, CaseIterable, Identifiable {
    case value
    case pnl
    case signal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .value:
            return "按市值"
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
    @State private var sortMode: HoldingSortMode = .value
    @State private var exportingFormat: HoldingsExportFormat?
    @State private var exportMessage: String?
    @State private var exportedDocument: ShareDocument?

    var body: some View {
        NavigationStack {
            AppBackdrop {
                Group {
                    switch dashboardStore.state {
                    case .idle, .loading:
                        LoadingStageCard(
                            title: "正在整理资产",
                            detail: "正在汇总组合、账户与持仓",
                            footnote: "很快就能查看总资产、结构分布和各个股票的最新金额。"
                        )
                        .padding(16)

                    case let .failed(message):
                        ScrollView {
                            EmptyStateCard(
                                title: "资产页暂不可用",
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
                                summarySection(payload)
                                structureSection(payload)
                                holdingsSection(payload, positions: positions)
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
            .navigationTitle("资产")
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
            .sheet(item: $exportedDocument) { item in
                ActivityView(activityItems: [item.url])
            }
        }
    }

    private func refresh(force: Bool) async {
        if settings.canAccessRemoteData {
            do {
                let client = try settings.makeClient()
                await dashboardStore.refreshVisible(using: client)
            } catch {
                dashboardStore.setError(error.localizedDescription)
            }
            return
        }
        if settings.canUseLongbridgeSession {
            await dashboardStore.refreshLocalFirst(using: settings)
        } else {
            dashboardStore.setNotice("当前没有可用服务器，先展示手机缓存。")
        }
    }

    private func summarySection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(
            title: "总体资产与持仓",
            subtitle: "数量来自结单，金额与盈亏会随最新价格自动更新。"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SectionStatusRow(
                    lastUpdatedAt: dashboardStore.lastUpdatedAt,
                    isRefreshing: dashboardStore.isRefreshing,
                    isShowingCachedSnapshot: dashboardStore.isShowingCachedSnapshot
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(payload.summaryCards.prefix(6))) { card in
                            SummaryCardView(card: card)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        exportButton(.pdf, label: "导出 PDF")
                        exportButton(.xlsx, label: "导出 Excel")
                    }

                    Text("导出内容包含当前持仓汇总与最近交易记录，便于分享或归档。")
                        .font(.footnote)
                        .foregroundStyle(BrokerPalette.muted)

                    if let exportMessage, !exportMessage.isEmpty {
                        Text(exportMessage)
                            .font(.footnote)
                            .foregroundStyle(exportMessage.contains("失败") ? BrokerPalette.red : BrokerPalette.teal)
                    }
                }
            }
        }
    }

    private func exportButton(_ format: HoldingsExportFormat, label: String) -> some View {
        let isExportingThis = exportingFormat == format
        return Button {
            Task { await exportHoldings(format: format) }
        } label: {
            HStack(spacing: 8) {
                if isExportingThis {
                    ProgressView()
                        .tint(BrokerPalette.cyan)
                } else {
                    Image(systemName: format == .pdf ? "doc.richtext" : "tablecells")
                }
                Text(label)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(format == .pdf ? BrokerPalette.gold : BrokerPalette.cyan)
        .disabled(exportingFormat != nil)
    }

    private func exportHoldings(format: HoldingsExportFormat) async {
        do {
            exportingFormat = format
            exportMessage = "正在生成\(format == .pdf ? " PDF" : " Excel")…"
            let client = try settings.makeClient()
            let file = try await client.downloadHoldingsExport(format: format)
            exportedDocument = ShareDocument(url: file.fileURL)
            exportMessage = "\(file.fileName) 已生成，可直接分享。"
        } catch {
            exportMessage = "导出失败：\(error.localizedDescription)"
        }
        exportingFormat = nil
    }

    private func structureSection(_ payload: MobileDashboardPayload) -> some View {
        SectionPanel(
            title: "结构分布",
            subtitle: "先看分账户，再看分主题和分市场。"
        ) {
            VStack(alignment: .leading, spacing: 18) {
                assetSubsectionTitle("分账户")

                ForEach(payload.accounts) { account in
                    accountRow(account)
                }

                assetSubsectionTitle("分主题")
                bucketCarousel(payload.allocationGroups.themes)

                assetSubsectionTitle("分市场")
                bucketCarousel(payload.allocationGroups.markets)
            }
        }
    }

    private func holdingsSection(_ payload: MobileDashboardPayload, positions: [MobilePosition]) -> some View {
        SectionPanel(
            title: "股票总览",
            subtitle: "\(payload.positions.count) 个持仓，可继续进入单股详情。"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("排序", selection: $sortMode) {
                    ForEach(HoldingSortMode.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if let top = positions.first {
                    HStack(spacing: 10) {
                        TagBadge(text: "头部仓 \(top.symbol)", tint: BrokerPalette.cyan)
                        TagBadge(text: "权重 \(NumberFormatters.percent(top.weightPct))", tint: BrokerPalette.teal)
                        TagBadge(text: top.stance, tint: BrokerPalette.gold)
                    }
                }

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("当前匹配 \(positions.count) 个结果")
                        .font(.footnote)
                        .foregroundStyle(BrokerPalette.muted)
                }

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
        case .value:
            return filtered.sorted { $0.statementValueHkd > $1.statementValueHkd }
        case .pnl:
            return filtered.sorted { ($0.statementPnlHkd ?? -.infinity) > ($1.statementPnlHkd ?? -.infinity) }
        case .signal:
            return filtered.sorted { ($0.signalScore ?? 0) > ($1.signalScore ?? 0) }
        }
    }

    private func assetSubsectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(BrokerPalette.muted)
    }

    private func bucketCarousel(_ buckets: [MobileAllocationBucket]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(buckets) { bucket in
                    bucketCard(bucket)
                }
            }
        }
    }

    private func bucketCard(_ bucket: MobileAllocationBucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bucket.label)
                .font(.headline)
                .foregroundStyle(BrokerPalette.ink)
                .lineLimit(1)

            if let valueHkd = bucket.valueHkd {
                Text(SensitiveValueMask.display(NumberFormatters.hkd(valueHkd), hidden: settings.hideSensitiveAmounts))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrokerPalette.cyan)
                    .monospacedDigit()
            }

            Text("权重 \(NumberFormatters.percent(bucket.weightPct))")
                .font(.footnote)
                .foregroundStyle(BrokerPalette.muted)

            if let count = bucket.count {
                Text("\(count) 个标的")
                    .font(.caption)
                    .foregroundStyle(BrokerPalette.muted)
            }

            if let coreHoldings = bucket.coreHoldings, !coreHoldings.isEmpty {
                Text(coreHoldings.prefix(3).joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(BrokerPalette.silver)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(width: 188, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrokerPalette.line, lineWidth: 1)
        )
    }

    private func accountRow(_ account: MobileAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.broker)
                        .font(.headline)
                        .foregroundStyle(BrokerPalette.ink)
                    Text(account.accountId)
                        .font(.caption.monospaced())
                        .foregroundStyle(BrokerPalette.muted)
                }

                Spacer()

                TagBadge(
                    text: loadStatusLabel(account.loadStatus),
                    tint: BrokerPalette.sourceStatus(account.loadStatus)
                )
            }

            LabelValueRow(label: "总资产", value: NumberFormatters.hkd(account.navHkd))
            LabelValueRow(label: "持仓金额", value: NumberFormatters.hkd(account.holdingsValueHkd))
            LabelValueRow(
                label: "融资占用",
                value: NumberFormatters.hkd(account.financingHkd),
                valueColor: account.financingHkd > 0 ? BrokerPalette.gold : BrokerPalette.ink
            )

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
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrokerPalette.line, lineWidth: 1)
        )
    }
}

private struct ShareDocument: Identifiable {
    let url: URL

    var id: String { url.absoluteString }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
