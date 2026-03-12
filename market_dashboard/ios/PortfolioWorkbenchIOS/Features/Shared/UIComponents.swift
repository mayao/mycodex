import SwiftUI
import PortfolioWorkbenchMobileCore

#if canImport(UIKit)
import UIKit
#endif

enum BrokerPalette {
    static let ink = Color(red: 0.93, green: 0.96, blue: 1.0)
    static let muted = Color(red: 0.56, green: 0.65, blue: 0.78)
    static let silver = Color(red: 0.86, green: 0.89, blue: 0.94)
    static let cyan = Color(red: 0.38, green: 0.91, blue: 1.0)
    static let teal = Color(red: 0.24, green: 0.89, blue: 0.78)
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.51)
    static let orange = Color(red: 1.0, green: 0.61, blue: 0.39)
    static let red = Color(red: 1.0, green: 0.45, blue: 0.45)
    static let green = Color(red: 0.13, green: 0.90, blue: 0.64)
    static let panel = Color(red: 0.05, green: 0.13, blue: 0.24, opacity: 0.94)
    static let panelStrong = Color(red: 0.03, green: 0.09, blue: 0.17, opacity: 0.98)
    static let line = Color.white.opacity(0.08)

    static func tone(_ tone: MobileTone?) -> Color {
        switch tone {
        case .up:
            return green
        case .warn:
            return gold
        case .down:
            return red
        case .neutral, .none:
            return cyan
        }
    }

    static func severity(_ severity: String) -> Color {
        switch severity {
        case "高":
            return red
        case "中":
            return orange
        case "低":
            return teal
        default:
            return cyan
        }
    }

    static func sourceStatus(_ value: String?) -> Color {
        switch value {
        case "parsed":
            return green
        case "cache":
            return gold
        case "error":
            return red
        default:
            return cyan
        }
    }
}

func loadStatusLabel(_ status: String?) -> String {
    switch status {
    case "parsed":
        return "已更新"
    case "cache":
        return "最近结果"
    case "error":
        return "异常"
    default:
        return "待检查"
    }
}

struct AppBackdrop<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.04, blue: 0.09),
                    Color(red: 0.03, green: 0.08, blue: 0.15),
                    Color(red: 0.04, green: 0.10, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [BrokerPalette.cyan.opacity(0.26), .clear],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 280
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [BrokerPalette.teal.opacity(0.18), .clear],
                center: .bottomLeading,
                startRadius: 12,
                endRadius: 260
            )
            .ignoresSafeArea()

            content
        }
    }
}

struct SectionPanel<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(BrokerPalette.ink)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(BrokerPalette.muted)
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BrokerPalette.panel, BrokerPalette.panelStrong],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(BrokerPalette.line, lineWidth: 1)
        )
    }
}

struct ToneBadge: View {
    let text: String
    let tone: MobileTone?

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(BrokerPalette.tone(tone))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(BrokerPalette.tone(tone).opacity(0.14), in: Capsule())
    }
}

struct TagBadge: View {
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

enum SensitiveValueMask {
    private static let keywords = [
        "净资产",
        "总资产",
        "股票市值",
        "持仓市值",
        "NAV",
        "融资",
        "市值",
        "盈亏",
        "名义",
        "敞口",
        "本金"
    ]

    static func shouldHide(label: String) -> Bool {
        keywords.contains { label.localizedCaseInsensitiveContains($0) }
    }

    static func masked(_ text: String) -> String {
        let masked = text.replacingOccurrences(
            of: "[0-9.,]",
            with: "•",
            options: .regularExpression
        )
        return masked == text ? "••••" : masked
    }

    static func display(_ text: String, hidden: Bool) -> String {
        hidden ? masked(text) : text
    }
}

struct SensitiveToggleToolbarButton: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Button {
            settings.toggleSensitiveAmounts()
        } label: {
            Image(systemName: settings.hideSensitiveAmounts ? "eye.slash.fill" : "eye")
        }
        .tint(settings.hideSensitiveAmounts ? BrokerPalette.gold : BrokerPalette.cyan)
        .accessibilityLabel(settings.hideSensitiveAmounts ? "显示金额" : "隐藏金额")
    }
}

struct SummaryCardView: View {
    let card: MobileSummaryCard
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(card.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrokerPalette.muted)
                    .textCase(.uppercase)
                Spacer()
                ToneBadge(text: statusText, tone: card.tone)
            }

            Text(displayValue)
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(BrokerPalette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Capsule()
                .fill(BrokerPalette.tone(card.tone).opacity(0.16))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(BrokerPalette.tone(card.tone))
                        .frame(width: 56)
                }
        }
        .padding(16)
        .frame(width: 184, alignment: .leading)
        .background(BrokerPalette.tone(card.tone).opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrokerPalette.tone(card.tone).opacity(0.16), lineWidth: 1)
        )
    }

    private var displayValue: String {
        guard settings.hideSensitiveAmounts, SensitiveValueMask.shouldHide(label: card.label) else {
            return card.value
        }
        return SensitiveValueMask.masked(card.value)
    }

    private var statusText: String {
        switch card.tone {
        case .up:
            return "稳态"
        case .warn:
            return "关注"
        case .down:
            return "风险"
        case .neutral:
            return "跟踪"
        }
    }
}

struct InsightCardView: View {
    let title: String
    let detail: String
    let tone: MobileTone?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrokerPalette.tone(tone))
                    .frame(width: 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(BrokerPalette.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(BrokerPalette.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        SectionPanel(title: title, subtitle: nil) {
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(BrokerPalette.muted)

                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(BrokerPalette.cyan)
                    .foregroundStyle(Color.black)
            }
        }
    }
}

struct SyncStatusBanner: View {
    let message: String
    let isRefreshing: Bool
    let isStale: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isRefreshing {
                ProgressView()
                    .tint(BrokerPalette.cyan)
            } else {
                Image(systemName: isStale ? "clock.arrow.circlepath" : "checkmark.circle.fill")
                    .foregroundStyle(isStale ? BrokerPalette.gold : BrokerPalette.green)
            }

            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BrokerPalette.ink)

            Spacer()

            if isStale {
                TagBadge(text: "同步中", tint: BrokerPalette.gold)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BrokerPalette.panelStrong.opacity(0.94), in: Capsule())
        .overlay(
            Capsule()
                .stroke(BrokerPalette.line, lineWidth: 1)
        )
    }
}

private struct SyncBannerSnapshot: Equatable {
    let message: String
    let isRefreshing: Bool
    let isStale: Bool
}

private struct TransientSyncBannerModifier: ViewModifier {
    let message: String?
    let isRefreshing: Bool
    let isStale: Bool

    @State private var visibleBanner: SyncBannerSnapshot?
    @State private var hasRefreshCycle = false
    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top) {
                if let visibleBanner {
                    SyncStatusBanner(
                        message: visibleBanner.message,
                        isRefreshing: visibleBanner.isRefreshing,
                        isStale: visibleBanner.isStale
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear {
                if isRefreshing {
                    hasRefreshCycle = true
                    presentBanner(autoHide: false)
                }
            }
            .onChange(of: isRefreshing, initial: false) { _, refreshing in
                if refreshing {
                    hasRefreshCycle = true
                    presentBanner(autoHide: false)
                } else if hasRefreshCycle {
                    presentBanner(autoHide: true)
                    hasRefreshCycle = false
                }
            }
            .onChange(of: message, initial: false) { _, _ in
                if isRefreshing || hasRefreshCycle {
                    presentBanner(autoHide: !isRefreshing)
                }
            }
            .onDisappear {
                hideTask?.cancel()
            }
    }

    private func presentBanner(autoHide: Bool) {
        guard let message, !message.isEmpty else {
            hideTask?.cancel()
            withAnimation(.easeOut(duration: 0.2)) {
                visibleBanner = nil
            }
            return
        }

        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            visibleBanner = SyncBannerSnapshot(
                message: message,
                isRefreshing: isRefreshing,
                isStale: isStale
            )
        }

        guard autoHide else {
            return
        }

        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    visibleBanner = nil
                }
            }
        }
    }
}

extension View {
    func transientSyncBanner(message: String?, isRefreshing: Bool, isStale: Bool) -> some View {
        modifier(
            TransientSyncBannerModifier(
                message: message,
                isRefreshing: isRefreshing,
                isStale: isStale
            )
        )
    }
}

struct LoadingStageCard: View {
    let title: String
    let detail: String
    let footnote: String

    var body: some View {
        SectionPanel(title: title, subtitle: detail) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(BrokerPalette.cyan)
                    Text(footnote)
                        .font(.subheadline)
                        .foregroundStyle(BrokerPalette.muted)
                }

                HStack(spacing: 8) {
                    TagBadge(text: "关键数据优先", tint: BrokerPalette.cyan)
                    TagBadge(text: "其余内容继续更新", tint: BrokerPalette.gold)
                }
            }
        }
    }
}

struct SectionStatusRow: View {
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let isShowingCachedSnapshot: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isRefreshing {
                ProgressView()
                    .tint(BrokerPalette.cyan)
            } else {
                Image(systemName: isShowingCachedSnapshot ? "clock.arrow.circlepath" : "bolt.circle.fill")
                    .foregroundStyle(isShowingCachedSnapshot ? BrokerPalette.gold : BrokerPalette.green)
            }

            Text(statusText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BrokerPalette.ink)

            Spacer()

            TagBadge(text: isShowingCachedSnapshot ? "已载入" : "最新", tint: isShowingCachedSnapshot ? BrokerPalette.gold : BrokerPalette.teal)
        }
    }

    private var statusText: String {
        let suffix = NumberFormatters.relativeTimestamp(lastUpdatedAt)
        if isRefreshing {
            return suffix == "刚刚" ? "正在同步…" : "正在同步，当前数据 \(suffix)"
        }
        if isShowingCachedSnapshot {
            return suffix == "刚刚" ? "已载入最近一次结果" : "已载入 \(suffix) 的最近结果"
        }
        return suffix == "刚刚" ? "最新数据已就绪" : "最新数据更新于 \(suffix)"
    }
}

struct ActionChipButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RefreshActionStrip: View {
    let title: String
    let subtitle: String
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let isShowingCachedSnapshot: Bool
    let marketAction: () -> Void
    let insightAction: () -> Void

    var body: some View {
        SectionPanel(title: title, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 14) {
                SectionStatusRow(
                    lastUpdatedAt: lastUpdatedAt,
                    isRefreshing: isRefreshing,
                    isShowingCachedSnapshot: isShowingCachedSnapshot
                )

                HStack(spacing: 10) {
                    ActionChipButton(
                        title: "刷新行情",
                        systemImage: "arrow.clockwise.circle",
                        tint: BrokerPalette.cyan,
                        action: marketAction
                    )
                    ActionChipButton(
                        title: "刷新 AI 洞察",
                        systemImage: "sparkles",
                        tint: BrokerPalette.gold,
                        action: insightAction
                    )
                }
            }
        }
    }
}

struct ActionStreamCard: View {
    let index: Int
    let label: String
    let title: String
    let detail: String?
    let badge: String?
    let tone: MobileTone?
    let isPriority: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(BrokerPalette.tone(tone).opacity(0.16))
                        .frame(width: 34, height: 34)
                    Text("\(index)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(BrokerPalette.tone(tone))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if isPriority {
                            TagBadge(text: "首要动作", tint: BrokerPalette.orange)
                        }
                        TagBadge(text: label, tint: BrokerPalette.cyan)
                        if let badge, !badge.isEmpty {
                            ToneBadge(text: badge, tone: tone)
                        }
                    }

                    Text(title)
                        .font(.system(isPriority ? .title3 : .headline, design: .rounded, weight: .bold))
                        .foregroundStyle(BrokerPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(isPriority ? BrokerPalette.ink.opacity(0.9) : BrokerPalette.muted)
                    .lineLimit(isPriority ? 4 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrokerPalette.tone(tone).opacity(isPriority ? 0.34 : 0.2), lineWidth: isPriority ? 1.4 : 1)
        )
    }

    private var backgroundFill: LinearGradient {
        LinearGradient(
            colors: isPriority
                ? [BrokerPalette.tone(tone).opacity(0.16), Color.white.opacity(0.05)]
                : [Color.white.opacity(0.05), Color.white.opacity(0.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

struct SparklineView: View {
    let points: [Double]
    let color: Color

    var body: some View {
        if points.count > 1 {
            SparklineShape(values: points)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 96, height: 34)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.16))
                .frame(width: 96, height: 34)
                .overlay(
                    Text("NO HIST")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color.opacity(0.8))
                )
        }
    }
}

struct PositionCompactCard: View {
    let position: MobilePosition
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(position.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrokerPalette.cyan)
                    Text(position.name)
                        .font(.headline)
                        .foregroundStyle(BrokerPalette.ink)
                        .lineLimit(1)
                    Text(position.categoryName)
                        .font(.caption)
                        .foregroundStyle(BrokerPalette.muted)
                        .lineLimit(1)
                }

                Spacer()

                SparklineView(points: position.sparklinePoints, color: toneColor)
            }

            HStack(spacing: 8) {
                TagBadge(text: position.signalZone ?? "中性跟踪", tint: toneColor)
                TagBadge(text: position.stance, tint: BrokerPalette.gold)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(SensitiveValueMask.display(NumberFormatters.hkd(position.statementValueHkd), hidden: settings.hideSensitiveAmounts))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(BrokerPalette.ink)
                        .monospacedDigit()
                    Text("权重 \(NumberFormatters.percent(position.weightPct))")
                        .font(.footnote)
                        .foregroundStyle(BrokerPalette.muted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(NumberFormatters.signedPercent(position.statementPnlPct))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(NumberFormatters.pnlColor(position.statementPnlPct))
                        .monospacedDigit()

                    if let dayChange = position.changePct {
                        Text("日内 \(NumberFormatters.signedPercent(dayChange))")
                            .font(.footnote)
                            .foregroundStyle(NumberFormatters.pnlColor(dayChange))
                            .monospacedDigit()
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

    private var toneColor: Color {
        switch position.signalZone {
        case "积极进攻":
            return BrokerPalette.green
        case "防守处理":
            return BrokerPalette.red
        case "中性跟踪":
            return BrokerPalette.cyan
        default:
            return BrokerPalette.gold
        }
    }
}

struct LabelValueRow: View {
    let label: String
    let value: String
    let valueColor: Color
    @EnvironmentObject private var settings: AppSettingsStore

    init(label: String, value: String, valueColor: Color = BrokerPalette.ink) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(BrokerPalette.muted)
            Spacer()
            Text(displayValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private var displayValue: String {
        guard settings.hideSensitiveAmounts, SensitiveValueMask.shouldHide(label: label) else {
            return value
        }
        return SensitiveValueMask.masked(value)
    }
}

enum NumberFormatters {
    static func hkd(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return "HK$" + grouped(value)
    }

    static func currency(_ value: Double?, code: String) -> String {
        guard let value else { return "N/A" }
        if code.contains("$") {
            return code + grouped(value)
        }
        return "\(code) " + grouped(value)
    }

    static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = abs(value) >= 1000 ? 0 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func grouped(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return grouped(value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "%.2f%%", value)
    }

    static func signedPercent(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: value >= 0 ? "+%.2f%%" : "%.2f%%", value)
    }

    static func pnlColor(_ value: Double?) -> Color {
        guard let value else { return BrokerPalette.muted }
        if value > 0 { return BrokerPalette.green }
        if value < 0 { return BrokerPalette.red }
        return BrokerPalette.muted
    }

    static func relativeTimestamp(_ value: Date?) -> String {
        guard let value else { return "未记录" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: value, relativeTo: .now)
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
