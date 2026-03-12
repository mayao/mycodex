import SwiftUI
import VitalCommandMobileCore

struct PlanItemCard: View {
    let item: HealthPlanItem
    let isChecked: Bool
    var actualValue: Double?
    var targetValue: Double?
    var onCheckIn: (() -> Void)?
    var onPause: (() -> Void)?
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Check button
            Button {
                if !isChecked { onCheckIn?() }
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(isChecked, color: .secondary)
                    .foregroundStyle(isChecked ? .secondary : .primary)

                if let actual = actualValue, let target = targetValue, target > 0 {
                    ProgressView(value: min(actual / target, 1.0))
                        .tint(actual >= target ? .green : .orange)
                        .frame(height: 4)
                }

                HStack(spacing: 6) {
                    if let target = targetLabel {
                        Text(target)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.frequency.label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                        .foregroundStyle(.secondary)

                    if let hint = item.timeHint, !hint.isEmpty {
                        Label(hint, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Context menu
            Menu {
                if !isChecked {
                    Button {
                        onCheckIn?()
                    } label: {
                        Label("完成打卡", systemImage: "checkmark")
                    }
                }

                Button {
                    onEdit?()
                } label: {
                    Label("编辑", systemImage: "pencil")
                }

                Button {
                    onPause?()
                } label: {
                    Label("暂停计划", systemImage: "pause.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(12)
        .background(Color.appGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var targetLabel: String? {
        guard let value = item.targetValue, let unit = item.targetUnit else { return nil }
        if value == value.rounded() {
            return "目标: \(Int(value)) \(unit)"
        }
        return "目标: \(String(format: "%.1f", value)) \(unit)"
    }
}
