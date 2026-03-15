import SwiftUI
import VitalCommandMobileCore

struct PlanCustomizeSheet: View {
    let suggestion: HealthSuggestion?
    let planItem: HealthPlanItem?
    let onConfirm: (PlanFrequency, String, Double?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var frequency: PlanFrequency
    @State private var timeHint: String
    @State private var targetValueText: String
    @State private var targetUnit: String
    @State private var isConfirming = false

    private let timePresets = ["早晨", "午间", "傍晚", "晚间", "自定义"]

    init(suggestion: HealthSuggestion? = nil, planItem: HealthPlanItem? = nil, onConfirm: @escaping (PlanFrequency, String, Double?, String?) -> Void) {
        self.suggestion = suggestion
        self.planItem = planItem
        self.onConfirm = onConfirm
        let freq = planItem?.frequency ?? suggestion?.frequency ?? .daily
        let hint = planItem?.timeHint ?? suggestion?.timeHint ?? ""
        let tv = planItem?.targetValue ?? suggestion?.targetValue
        let tu = planItem?.targetUnit ?? suggestion?.targetUnit
        _frequency = State(initialValue: freq)
        _timeHint = State(initialValue: hint)
        _targetValueText = State(initialValue: tv != nil ? String(format: "%.0f", tv!) : "")
        _targetUnit = State(initialValue: tu ?? "")
    }

    private var title: String {
        planItem?.title ?? suggestion?.title ?? "自定义计划"
    }

    private var description: String {
        planItem?.description ?? suggestion?.description ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("计划详情") {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("执行频率") {
                    HStack(spacing: 8) {
                        ForEach([PlanFrequency.daily, .weekly, .once], id: \.self) { freq in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    frequency = freq
                                }
                            } label: {
                                Text(freq.label)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        frequency == freq ? Color.teal : Color(UIColor.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .foregroundStyle(frequency == freq ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("提醒时间") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(timePresets, id: \.self) { preset in
                                Button {
                                    if preset == "自定义" {
                                        // leave timeHint for manual entry
                                    } else {
                                        timeHint = preset
                                    }
                                } label: {
                                    Text(preset)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            timeHint == preset ? Color.teal : Color(UIColor.secondarySystemBackground),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(timeHint == preset ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    TextField("如 07:00 或 morning / evening", text: $timeHint)
                }

                if suggestion?.targetValue != nil || planItem?.targetValue != nil {
                    Section("目标值") {
                        HStack {
                            TextField("目标值", text: $targetValueText)
                                .keyboardType(.decimalPad)
                            if !targetUnit.isEmpty {
                                Text(targetUnit)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(planItem != nil ? "编辑计划" : "自定义计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            isConfirming = true
                        }
                        let tv = Double(targetValueText)
                        onConfirm(frequency, timeHint, tv, targetUnit.isEmpty ? nil : targetUnit)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isConfirming {
                                ProgressView().controlSize(.small)
                            }
                            Text("确认")
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isConfirming)
                }
            }
        }
    }
}
