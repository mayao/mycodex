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

                Section("频率") {
                    Picker("执行频率", selection: $frequency) {
                        Text("每天").tag(PlanFrequency.daily)
                        Text("每周").tag(PlanFrequency.weekly)
                        Text("一次性").tag(PlanFrequency.once)
                    }
                    .pickerStyle(.segmented)
                }

                Section("提醒时间") {
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
                    Button("确认") {
                        let tv = Double(targetValueText)
                        onConfirm(frequency, timeHint, tv, targetUnit.isEmpty ? nil : targetUnit)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
