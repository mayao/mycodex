import Foundation
import SwiftUI
import VitalCommandMobileCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

func formatDecimal(_ value: Double, fractionDigits: Int) -> String {
    value.formatted(.number.precision(.fractionLength(fractionDigits)))
}

struct StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 0.96, green: 0.98, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [
                        Color(red: 0.06, green: 0.49, blue: 0.43).opacity(0.05),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 200
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(red: 0.06, green: 0.49, blue: 0.43).opacity(0.1), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
    }
}

struct KeyValueTile: View {
    let label: String
    let value: String
    let detail: String
    let tone: HealthTone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                StatusBadge(text: toneText, tint: toneColor)
            }

            Text(value)
                .font(.headline.weight(.semibold))

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 180, alignment: .leading)
        .background(toneColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var toneColor: Color {
        switch tone {
        case .positive:
            return .green
        case .attention:
            return .orange
        case .neutral:
            return .blue
        }
    }

    private var toneText: String {
        switch tone {
        case .positive:
            return "积极"
        case .attention:
            return "关注"
        case .neutral:
            return "稳定"
        }
    }
}

struct ReminderRow: View {
    let item: HealthReminderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.title)
                    .font(.headline)
                Spacer()
                StatusBadge(text: severityText, tint: severityColor)
            }

            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("建议: \(item.suggestedAction)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }

    private var severityColor: Color {
        switch item.severity {
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

    private var severityText: String {
        switch item.severity {
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

struct DimensionChip: View {
    let dimension: HealthSourceDimensionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dimension.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if dimension.insightSummary != nil {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(.teal)
                }
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            Text(dimension.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dimension.insightSummary != nil ? 4 : 3)
                .lineSpacing(2)

            Text(dimension.highlight)
                .font(.subheadline.weight(.medium))
        }
        .padding(16)
        .frame(width: 200, alignment: .leading)
        .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusColor: Color {
        switch dimension.status {
        case .ready:
            return .green
        case .attention:
            return .orange
        case .background:
            return .blue
        }
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct OfflineCacheBanner: View {
    let title: String
    let cachedAt: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.orange)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let cachedAt {
                    Text("缓存时间：\(cachedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("当前显示的是最近一次成功获取的数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct InsightListSection: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .padding(.top, 8)
                    Text(item)
                        .font(.body)
                        .lineSpacing(3)
                }
            }
        }
    }
}

struct SparklineShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, let minValue = values.min(), let maxValue = values.max() else {
            return path
        }

        let span = max(maxValue - minValue, 0.0001)

        for (index, value) in values.enumerated() {
            let x = rect.minX + CGFloat(index) / CGFloat(values.count - 1) * rect.width
            let normalized = (value - minValue) / span
            let y = rect.maxY - CGFloat(normalized) * rect.height

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

struct TrendChartCard: View {
    let chart: HealthTrendChartModel

    var body: some View {
        SectionCard(title: chart.title, subtitle: chart.description) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(chart.lines) { line in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(line.label)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let latest = latestValue(for: line.key) {
                                Text(formattedLatestValue(latest, line: line))
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        SparklineShape(values: values(for: line.key))
                            .stroke(lineColor(line.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .frame(height: 54)
                    }
                }
            }
        }
    }

    private func values(for key: String) -> [Double] {
        chart.data.compactMap { $0.values[key] }
    }

    private func latestValue(for key: String) -> Double? {
        values(for: key).last
    }

    private func formattedLatestValue(_ value: Double, line: HealthTrendLine) -> String {
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

    private func lineColor(_ hex: String) -> Color {
        Color(hex: hex) ?? .accentColor
    }
}

extension Color {
    init?(hex: String) {
        let normalized = hex.replacingOccurrences(of: "#", with: "")
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

extension Color {
    static var appGroupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.gray.opacity(0.08)
        #endif
    }
}

extension View {
    @ViewBuilder
    func appInlineNavigationTitle() -> some View {
        #if canImport(UIKit)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func appInsetGroupedListStyle() -> some View {
        #if canImport(UIKit)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func appURLTextEntry() -> some View {
        #if canImport(UIKit)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        #else
        self
        #endif
    }
}
