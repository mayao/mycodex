import SwiftUI
import VitalCommandMobileCore

struct TrendDetailScreen: View {
    let chart: HealthTrendChartModel
    var highlightedLineKey: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                heroSection
                latestValuesSection
                TrendChartCard(chart: chart)
            }
            .padding(16)
        }
        .background(Color.appGroupedBackground)
        .navigationTitle(chart.title.replacingOccurrences(of: "图", with: ""))
        .appInlineNavigationTitle()
    }

    private var heroSection: some View {
        SectionCard(title: chart.title, subtitle: chart.description) {
            HStack(spacing: 12) {
                ForEach(chart.lines.prefix(3)) { line in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(line.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color(for: line.color))

                        Text(latestValueText(for: line))
                            .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var latestValuesSection: some View {
        SectionCard(title: "最新值", subtitle: "查看每条指标线的当前数值和阶段变化。") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(chart.lines) { line in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(color(for: line.color))
                                .frame(width: 10, height: 10)
                            Text(line.label)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }

                        Text(latestValueText(for: line))
                            .font(.title3.weight(.bold))

                        Text(deltaText(for: line))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(backgroundColor(for: line), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }

    private func latestValueText(for line: HealthTrendLine) -> String {
        let value = chart.data.compactMap { $0.values[line.key] }.last
        guard let value else {
            return "--"
        }

        if line.key == "sleepMinutes" {
            return "\(formatDecimal(value / 60, fractionDigits: 1)) h"
        }

        if line.key == "steps" {
            return "\(Int(value.rounded())) 步"
        }

        if line.unit == "mmol/L" {
            return "\(formatDecimal(value, fractionDigits: 2)) \(line.unit)"
        }

        if line.unit == "kg" || line.unit == "%" || line.unit == "kg/m2" {
            return "\(formatDecimal(value, fractionDigits: 1)) \(line.unit)"
        }

        return "\(Int(value.rounded())) \(line.unit)"
    }

    private func deltaText(for line: HealthTrendLine) -> String {
        let values = chart.data.compactMap { $0.values[line.key] }
        guard values.count > 1 else {
            return "暂无对比"
        }

        let delta = values.last! - values.first!
        let sign = delta > 0 ? "+" : ""

        if line.key == "sleepMinutes" {
            return "阶段变化 \(sign)\(formatDecimal(delta / 60, fractionDigits: 1)) h"
        }

        if line.key == "steps" {
            return "阶段变化 \(sign)\(Int(delta.rounded())) 步"
        }

        let digits = line.unit == "mmol/L" ? 2 : 1
        return "阶段变化 \(sign)\(formatDecimal(delta, fractionDigits: digits)) \(line.unit)"
    }

    private func color(for hex: String) -> Color {
        Color(hex: hex) ?? .accentColor
    }

    private func backgroundColor(for line: HealthTrendLine) -> Color {
        if line.key == highlightedLineKey {
            return color(for: line.color).opacity(0.16)
        }

        return color(for: line.color).opacity(0.08)
    }
}
