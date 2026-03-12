import SwiftUI
import VitalCommandMobileCore

struct SuggestionCard: View {
    let suggestion: HealthSuggestion
    var onAccept: (() -> Void)?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: suggestion.dimension.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: suggestion.dimension.color) ?? .primary)
                    .frame(width: 24, height: 24)
                    .background(
                        (Color(hex: suggestion.dimension.color) ?? .primary).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer()

                priorityBadge
            }

            // Description (expandable)
            Text(suggestion.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 2)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }

            // Metadata
            HStack(spacing: 10) {
                if let target = targetLabel {
                    Label(target, systemImage: "target")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                }

                Label(suggestion.frequency.label, systemImage: "repeat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let hint = suggestion.timeHint, !hint.isEmpty {
                    Label(hint, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Accept button
                Button {
                    onAccept?()
                } label: {
                    Text("接受计划")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            (Color(hex: suggestion.dimension.color) ?? .teal),
                            in: Capsule()
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.appGroupedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            (Color(hex: suggestion.dimension.color) ?? .teal).opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
    }

    private var priorityBadge: some View {
        HStack(spacing: 2) {
            ForEach(0..<min(suggestion.priority, 5), id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: 6))
            }
        }
        .foregroundStyle(.orange)
    }

    private var targetLabel: String? {
        guard let value = suggestion.targetValue, let unit = suggestion.targetUnit else { return nil }
        if value == value.rounded() {
            return "\(Int(value)) \(unit)"
        }
        return "\(String(format: "%.1f", value)) \(unit)"
    }
}
