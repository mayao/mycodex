import SwiftUI
import VitalCommandMobileCore

struct ReportsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = ReportsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("正在加载报告")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case let .failed(message):
                    EmptyStateCard(
                        title: "报告列表暂时不可用",
                        message: message,
                        actionTitle: "重试"
                    ) {
                        Task { await reload() }
                    }
                    .padding()

                case .loaded:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if viewModel.isUsingCache {
                                OfflineCacheBanner(
                                    title: "当前为离线缓存报告",
                                    cachedAt: viewModel.cacheDate
                                )
                            }
                            reportHeader
                            planProgressSection

                            ForEach(viewModel.visibleReports) { report in
                                NavigationLink {
                                    ReportDetailScreen(reportID: report.id)
                                } label: {
                                    ReportSnapshotCard(report: report)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                    .background(Color.appGroupedBackground)
                }
            }
            .navigationTitle("报告")
        }
        .task(id: settings.dashboardReloadKey) {
            await reload()
        }
    }

    /// Convert "2026-03-10" → "2026-03-16" into "3月10日–16日"
    private func shortPeriodLabel(start: String, end: String) -> String {
        let parts = end.split(separator: "-")
        let startParts = start.split(separator: "-")
        guard parts.count == 3, startParts.count == 3,
              let m = Int(parts[1]), let d2 = Int(parts[2]), let d1 = Int(startParts[2]) else {
            return "本周"
        }
        if startParts[1] == parts[1] {
            return "\(m)月\(d1)日–\(d2)日"
        }
        let m1 = Int(startParts[1]) ?? m
        return "\(m1)月\(d1)日–\(m)月\(d2)日"
    }

    private func reload() async {
        do {
            let client = try settings.makeClient()
            let cacheScope = settings.cacheScope(userID: authManager.currentUser?.id)
            await viewModel.load(using: client, cacheScope: cacheScope)
            await viewModel.loadPlanProgress(using: client, cacheScope: cacheScope)
        } catch {
            viewModel.setError(error.localizedDescription)
        }
    }

    @ViewBuilder
    private var planProgressSection: some View {
        if viewModel.isLoadingPlanProgress {
            SectionCard(title: "本周计划进度", subtitle: nil) {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        } else if let progress = viewModel.planProgress {
            SectionCard(title: "本周计划进度", subtitle: shortPeriodLabel(start: progress.periodStart, end: progress.periodEnd)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("整体完成率")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(progress.overallRate * 100))%")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(progress.overallRate >= 0.8 ? .green : progress.overallRate >= 0.5 ? .orange : .red)
                    }

                    ProgressView(value: progress.overallRate)
                        .tint(progress.overallRate >= 0.8 ? .green : progress.overallRate >= 0.5 ? .orange : .red)

                    if !progress.aiNudge.isEmpty {
                        Text(progress.aiNudge)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }

                    if !progress.items.isEmpty {
                        Divider()
                        ForEach(progress.items) { item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(item.dataBackedNote)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(item.completedDays)/\(item.expectedDays)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(item.completionRate >= 0.8 ? .green : item.completionRate >= 0.5 ? .orange : .red)
                            }
                        }
                    }
                }
            }
        }
    }

    private var reportHeader: some View {
        let reports = viewModel.visibleReports
        let insights = reports.flatMap(\.structuredInsights.insights)
        let positiveCount = insights.filter { $0.severity == .positive }.count
        let attentionCount = insights.filter { $0.severity == .medium || $0.severity == .high }.count

        return SectionCard(title: "报告总览", subtitle: "周报与月报摘要，先看重点再进入详情。") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("报告类型", selection: $viewModel.selectedKind) {
                    Text("周报").tag(ReportKind.weekly)
                    Text("月报").tag(ReportKind.monthly)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    ReportSummaryBadge(
                        title: "当前列表",
                        value: "\(reports.count)",
                        tint: .teal
                    )
                    ReportSummaryBadge(
                        title: "积极洞察",
                        value: "\(positiveCount)",
                        tint: .green
                    )
                    ReportSummaryBadge(
                        title: "需关注",
                        value: "\(attentionCount)",
                        tint: .orange
                    )
                }
            }
        }
    }
}

private struct ReportSummaryBadge: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ReportSnapshotCard: View {
    let report: HealthReportSnapshotRecord

    /// Compact period label: "3月10日–16日" or "2月28日–3月5日"
    private var periodLabel: String {
        let startParts = report.periodStart.split(separator: "-")
        let endParts = report.periodEnd.split(separator: "-")
        guard startParts.count == 3, endParts.count == 3,
              let m1 = Int(startParts[1]), let d1 = Int(startParts[2]),
              let m2 = Int(endParts[1]), let d2 = Int(endParts[2]) else {
            return report.periodEnd
        }
        if m1 == m2 {
            return "\(m1)月\(d1)日–\(d2)日"
        }
        return "\(m1)月\(d1)日–\(m2)月\(d2)日"
    }

    /// Simple type label without dates
    private var typeLabel: String {
        report.reportType == .weekly ? "健康周报" : "健康月报"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                StatusBadge(
                    text: report.reportType == .weekly ? "周报" : "月报",
                    tint: report.reportType == .weekly ? .teal : .indigo
                )
                Text(periodLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(typeLabel)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(report.summary.output.headline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(report.structuredInsights.metricSummaries.prefix(4)) { metric in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metric.metricName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(metricValue(metric))
                            .font(.subheadline.weight(.bold))
                        Text(metricDelta(metric))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(metricTint(metric).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(report.structuredInsights.insights.prefix(4)) { insight in
                        Text(insight.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(insightColor(insight.severity))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(insightColor(insight.severity).opacity(0.10), in: Capsule())
                            .lineLimit(1)
                    }
                    if let review = report.planReview {
                        Text("计划 \(Int(review.overallCompletionRate * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.purple.opacity(0.10), in: Capsule())
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    (report.reportType == .weekly ? Color.teal : Color.indigo).opacity(0.12),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private func metricValue(_ metric: MetricSummary) -> String {
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

    private func metricDelta(_ metric: MetricSummary) -> String {
        guard let delta = metric.latestVsMean else {
            return "暂无基线对比"
        }
        let sign = delta > 0 ? "+" : ""
        if metric.unit == "mmol/L" || metric.unit == "%" {
            return "较均值 \(sign)\(formatDecimal(delta, fractionDigits: 2)) \(metric.unit)"
        }
        return "较均值 \(sign)\(Int(delta.rounded())) \(metric.unit)"
    }

    private func metricTint(_ metric: MetricSummary) -> Color {
        if metric.abnormalFlag == "high" || metric.abnormalFlag == "low" {
            return .orange
        }
        return metric.trendDirection == "down" ? .teal : .blue
    }

    private func insightColor(_ severity: StructuredInsightSeverity) -> Color {
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
}
