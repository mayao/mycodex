import SwiftUI
import VitalCommandMobileCore

struct ReportDetailScreen: View {
    let reportID: String

    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = ReportDetailViewModel()
    @State private var expandedInsightID: String? = nil

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("正在加载报告详情")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case let .failed(message):
                EmptyStateCard(
                    title: "报告详情暂时不可用",
                    message: message,
                    actionTitle: "重试"
                ) {
                    Task { await reload() }
                }
                .padding()

            case let .loaded(report):
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if viewModel.isUsingCache {
                            OfflineCacheBanner(
                                title: "当前为离线缓存报告详情",
                                cachedAt: viewModel.cacheDate
                            )
                        }
                        reportHero(report)
                        metricsSection(report)
                        planReviewSection(report)
                        insightSection(report)
                        aiActionSection(report)
                    }
                    .padding(16)
                }
                .background(Color.appGroupedBackground)
            }
        }
        .navigationTitle("报告详情")
        .appInlineNavigationTitle()
        .task(id: settings.dashboardReloadKey + reportID) {
            await reload()
        }
    }

    private func reload() async {
        do {
            let client = try settings.makeClient()
            await viewModel.load(
                reportID: reportID,
                using: client,
                cacheScope: settings.cacheScope(userID: authManager.currentUser?.id)
            )
        } catch {
            viewModel.setError(error.localizedDescription)
        }
    }

    /// "3月10日–16日" or "2月28日–3月5日"
    private func periodLabel(start: String, end: String) -> String {
        let s = start.split(separator: "-")
        let e = end.split(separator: "-")
        guard s.count == 3, e.count == 3,
              let m1 = Int(s[1]), let d1 = Int(s[2]),
              let m2 = Int(e[1]), let d2 = Int(e[2]) else { return end }
        return m1 == m2 ? "\(m1)月\(d1)日–\(d2)日" : "\(m1)月\(d1)日–\(m2)月\(d2)日"
    }

    private func reportHero(_ report: HealthReportSnapshotRecord) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            (report.reportType == .weekly ? Color.teal : Color.indigo),
                            Color(hex: "#2563eb") ?? .blue
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    StatusBadge(
                        text: report.reportType == .weekly ? "周报" : "月报",
                        tint: .white
                    )
                    Text(periodLabel(start: report.periodStart, end: report.periodEnd))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.80))
                    Spacer()
                }

                Text(report.reportType == .weekly ? "健康周报" : "健康月报")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text(report.summary.output.headline)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(3)

                HStack(spacing: 12) {
                    SummaryChip(
                        title: "积极洞察",
                        value: "\(report.structuredInsights.insights.filter { $0.severity == .positive }.count)",
                        tint: .green
                    )
                    SummaryChip(
                        title: "需关注",
                        value: "\(report.structuredInsights.insights.filter { $0.severity == .medium || $0.severity == .high }.count)",
                        tint: .orange
                    )
                    SummaryChip(
                        title: "建议数",
                        value: "\(report.summary.output.priorityActions.count)",
                        tint: .blue
                    )
                }
            }
            .padding(20)
        }
    }

    private func metricsSection(_ report: HealthReportSnapshotRecord) -> some View {
        SectionCard(title: "关键指标", subtitle: "快速对比这份报告里的重点指标。") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(report.structuredInsights.metricSummaries.prefix(6)) { metric in
                    ReportMetricTile(metric: metric)
                }
            }
        }
    }

    @ViewBuilder
    private func planReviewSection(_ report: HealthReportSnapshotRecord) -> some View {
        if let review = report.planReview, !review.items.isEmpty {
            SectionCard(title: "计划回顾", subtitle: "本期健康计划的执行情况。") {
                VStack(spacing: 16) {
                    // Overall completion ring
                    ZStack {
                        Circle()
                            .stroke(Color.purple.opacity(0.15), lineWidth: 10)
                            .frame(width: 90, height: 90)
                        Circle()
                            .trim(from: 0, to: review.overallCompletionRate)
                            .stroke(Color.purple, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 90, height: 90)
                        VStack(spacing: 2) {
                            Text("\(Int(review.overallCompletionRate * 100))%")
                                .font(.title3.weight(.bold))
                            Text("总完成率")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)

                    // Individual items
                    ForEach(review.items) { item in
                        PlanReviewItemRow(item: item)
                    }

                    // AI comment
                    if !review.aiComment.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.blue)
                                .font(.subheadline)
                            Text(review.aiComment)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func insightSection(_ report: HealthReportSnapshotRecord) -> some View {
        let sorted = report.structuredInsights.insights.sorted { lhs, rhs in
            let order: [StructuredInsightSeverity] = [.high, .medium, .low, .positive]
            let li = order.firstIndex(of: lhs.severity) ?? 4
            let ri = order.firstIndex(of: rhs.severity) ?? 4
            return li < ri
        }
        return SectionCard(title: "结构化洞察", subtitle: "点击每条查看证据与建议，按严重度排序。") {
            VStack(spacing: 10) {
                ForEach(sorted) { insight in
                    InsightExpandRow(
                        insight: insight,
                        isExpanded: expandedInsightID == insight.id,
                        severityColor: severityColor(insight.severity),
                        severityText: severityText(insight.severity)
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            expandedInsightID = expandedInsightID == insight.id ? nil : insight.id
                        }
                    }
                }
            }
        }
    }

    private func aiActionSection(_ report: HealthReportSnapshotRecord) -> some View {
        SectionCard(title: "AI 解析", subtitle: "基于最新数据的重点变化、可能原因和建议。") {
            VStack(spacing: 12) {
                InsightBlockCard(
                    title: "重点变化",
                    icon: "waveform.path.ecg",
                    color: .teal,
                    items: report.summary.output.mostImportantChanges
                )
                InsightBlockCard(
                    title: "原因推断",
                    icon: "brain.head.profile",
                    color: .indigo,
                    items: report.summary.output.possibleReasons
                )
                InsightBlockCard(
                    title: "行动建议",
                    icon: "sparkles",
                    color: .blue,
                    items: report.summary.output.priorityActions
                )
                InsightBlockCard(
                    title: "继续观察",
                    icon: "eye.fill",
                    color: .orange,
                    items: report.summary.output.continueObserving
                )
            }
        }
    }

    private func severityColor(_ severity: StructuredInsightSeverity) -> Color {
        switch severity {
        case .positive:
            return .green
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private func severityText(_ severity: StructuredInsightSeverity) -> String {
        switch severity {
        case .positive:
            return "积极"
        case .low:
            return "低"
        case .medium:
            return "中"
        case .high:
            return "高"
        }
    }
}

private struct SummaryChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ReportMetricTile: View {
    let metric: MetricSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(metric.metricName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                StatusBadge(text: statusText, tint: tint)
            }

            Text(valueText)
                .font(.title3.weight(.bold))

            Text(deltaText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var tint: Color {
        if metric.abnormalFlag == "high" || metric.abnormalFlag == "low" {
            return .orange
        }
        return metric.trendDirection == "down" ? .teal : .blue
    }

    private var valueText: String {
        if metric.unit == "mmol/L" {
            return "\(formatDecimal(metric.latestValue, fractionDigits: 2)) \(metric.unit)"
        }
        if metric.unit == "%" {
            return "\(formatDecimal(metric.latestValue, fractionDigits: 1)) \(metric.unit)"
        }
        if metric.unit == "min" && metric.metricCode.contains("sleep") {
            return "\(formatDecimal(metric.latestValue / 60, fractionDigits: 1)) h"
        }
        return "\(Int(metric.latestValue.rounded())) \(metric.unit)"
    }

    private var deltaText: String {
        guard let latestVsMean = metric.latestVsMean else {
            return "暂无均值对比"
        }
        let sign = latestVsMean > 0 ? "+" : ""
        if metric.unit == "mmol/L" || metric.unit == "%" {
            return "较均值 \(sign)\(formatDecimal(latestVsMean, fractionDigits: 2)) \(metric.unit)"
        }
        return "较均值 \(sign)\(Int(latestVsMean.rounded())) \(metric.unit)"
    }

    private var statusText: String {
        if metric.abnormalFlag == "high" || metric.abnormalFlag == "low" {
            return "关注"
        }
        return metric.trendDirection == "down" ? "改善" : "稳定"
    }
}

private struct InsightBlockCard: View {
    let title: String
    let icon: String
    let color: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.headline)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(items.count)条")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(color)
                            .frame(width: 20, height: 20)
                            .background(color.opacity(0.12), in: Circle())
                            .padding(.top, 1)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct PlanReviewItemRow: View {
    let item: PlanItemReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: dimensionIcon)
                    .foregroundStyle(dimensionColor)
                    .font(.subheadline)
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("\(item.actualCompleted)/\(item.expectedChecks)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(item.completionRate >= 0.8 ? .green : (item.completionRate >= 0.5 ? .orange : .red))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(dimensionColor.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(dimensionColor)
                        .frame(width: geo.size.width * item.completionRate, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(dimensionColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dimensionIcon: String {
        switch item.dimension {
        case "exercise": return "figure.run"
        case "sleep": return "moon.zzz.fill"
        case "diet": return "fork.knife"
        case "checkup": return "stethoscope"
        default: return "heart.fill"
        }
    }

    private var dimensionColor: Color {
        switch item.dimension {
        case "exercise": return .green
        case "sleep": return .indigo
        case "diet": return .orange
        case "checkup": return .teal
        default: return .blue
        }
    }
}

private struct InsightExpandRow: View {
    let insight: StructuredInsight
    let isExpanded: Bool
    let severityColor: Color
    let severityText: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row — always visible
                HStack(spacing: 10) {
                    Circle()
                        .fill(severityColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 2)

                    Text(insight.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    StatusBadge(text: severityText, tint: severityColor)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)

                // Expanded content
                if isExpanded {
                    Divider()
                        .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 14) {
                        if !insight.evidence.summary.isEmpty {
                            Label {
                                Text(insight.evidence.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(3)
                            } icon: {
                                Image(systemName: "chart.xyaxis.line")
                                    .foregroundStyle(severityColor)
                                    .font(.subheadline)
                            }
                        }

                        if !insight.possibleReason.isEmpty {
                            Label {
                                Text(insight.possibleReason)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(3)
                            } icon: {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(.indigo)
                                    .font(.subheadline)
                            }
                        }

                        Label {
                            Text(insight.suggestedAction)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(3)
                        } icon: {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
        .buttonStyle(.plain)
        .background(severityColor.opacity(isExpanded ? 0.06 : 0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}
