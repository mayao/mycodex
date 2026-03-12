import SwiftUI
import VitalCommandMobileCore

struct HealthPlanScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var viewModel = HealthPlanViewModel()
    @State private var acceptedPlanItem: HealthPlanItem?
    @State private var showPostAcceptOptions = false
    @State private var suggestionToCustomize: HealthSuggestion?
    @State private var planItemToEdit: HealthPlanItem?

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("正在加载计划")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case let .failed(message):
                    EmptyStateCard(
                        title: "计划加载失败",
                        message: message,
                        actionTitle: "重试"
                    ) {
                        Task { await reload() }
                    }
                    .padding()

                case let .loaded(dashboard):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            progressHeader(dashboard)
                            activePlanSection(dashboard)
                            pausedPlanSection(dashboard)
                            suggestionsSection(dashboard)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 28)
                    }
                    .refreshable { await reload() }
                    .background(Color.appGroupedBackground.ignoresSafeArea())
                }
            }
            .navigationTitle("健康计划")
            .appInlineNavigationTitle()
        }
        .task(id: settings.dashboardReloadKey) {
            await reload()
        }
        .onAppear {
            Task {
                await reload()
                // Schedule daily evening check reminder
                await LocalNotificationManager.scheduleDailyCheckReminder()
            }
        }
        .alert("操作失败", isPresented: .init(
            get: { viewModel.operationError != nil },
            set: { if !$0 { viewModel.clearOperationError() } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(viewModel.operationError ?? "")
        }
        .confirmationDialog(
            "计划已添加",
            isPresented: $showPostAcceptOptions,
            titleVisibility: .visible
        ) {
            Button("开启提醒通知") {
                if let item = acceptedPlanItem {
                    Task { await LocalNotificationManager.schedulePlanReminder(planItem: item) }
                }
            }
            Button("添加到日历") {
                if let item = acceptedPlanItem {
                    Task { await CalendarIntegration.createEvent(for: item) }
                }
            }
            Button("都要") {
                if let item = acceptedPlanItem {
                    Task {
                        await LocalNotificationManager.schedulePlanReminder(planItem: item)
                        await CalendarIntegration.createEvent(for: item)
                    }
                }
            }
            Button("跳过", role: .cancel) {}
        } message: {
            Text("是否需要设置提醒来帮助你坚持计划？")
        }
        .sheet(item: $suggestionToCustomize) { suggestion in
            PlanCustomizeSheet(suggestion: suggestion) { frequency, timeHint, targetValue, targetUnit in
                Task {
                    let client = try? settings.makeClient()
                    if let client {
                        let request = AcceptSuggestionRequest(
                            suggestionId: suggestion.id,
                            targetValue: targetValue,
                            targetUnit: targetUnit,
                            frequency: frequency,
                            timeHint: timeHint.isEmpty ? nil : timeHint
                        )
                        if let item = await viewModel.acceptSuggestion(request, using: client) {
                            acceptedPlanItem = item
                            showPostAcceptOptions = true
                        }
                    }
                }
            }
        }
        .sheet(item: $planItemToEdit) { planItem in
            PlanCustomizeSheet(planItem: planItem) { frequency, timeHint, targetValue, targetUnit in
                Task {
                    let client = try? settings.makeClient()
                    if let client {
                        let request = UpdatePlanItemRequest(
                            planItemId: planItem.id,
                            targetValue: targetValue,
                            targetUnit: targetUnit,
                            frequency: frequency,
                            timeHint: timeHint.isEmpty ? nil : timeHint
                        )
                        await viewModel.updatePlanItem(request, using: client)
                    }
                }
            }
        }
    }

    private func reload() async {
        do {
            let client = try settings.makeClient()
            await viewModel.load(using: client)
        } catch {
            viewModel.setError(error.localizedDescription)
        }
    }

    // MARK: - Progress Header

    @ViewBuilder
    private func progressHeader(_ dashboard: HealthPlanDashboard) -> some View {
        SectionCard(title: "今日进度", subtitle: "坚持就是胜利。") {
            HStack(spacing: 20) {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 8)

                    Circle()
                        .trim(from: 0, to: progressFraction(dashboard))
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#10b981") ?? .green, Color(hex: "#0d9488") ?? .teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: dashboard.stats.todayCompleted)

                    VStack(spacing: 2) {
                        Text("\(dashboard.stats.todayCompleted)")
                            .font(.title2.weight(.bold).monospacedDigit())
                        Text("/\(dashboard.stats.todayTotal)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("活跃计划 \(dashboard.stats.activeCount) 项")
                            .font(.subheadline.weight(.medium))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    Label {
                        Text("本周完成率 \(Int(dashboard.stats.weekCompletionRate * 100))%")
                            .font(.subheadline.weight(.medium))
                    } icon: {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.indigo)
                    }
                }

                Spacer()
            }
        }
    }

    private func progressFraction(_ dashboard: HealthPlanDashboard) -> Double {
        guard dashboard.stats.todayTotal > 0 else { return 0 }
        return Double(dashboard.stats.todayCompleted) / Double(dashboard.stats.todayTotal)
    }

    // MARK: - Active Plans

    @ViewBuilder
    private func activePlanSection(_ dashboard: HealthPlanDashboard) -> some View {
        if dashboard.planItems.isEmpty {
            SectionCard(title: "我的计划", subtitle: "还没有活跃计划。生成建议并接受后即可开始追踪。") {
                EmptyView()
            }
        } else {
            SectionCard(title: "我的计划", subtitle: "按维度分组的活跃计划项。") {
                VStack(spacing: 12) {
                    ForEach(PlanDimension.allCases) { dimension in
                        let items = dashboard.planItems.filter { $0.dimension == dimension }
                        if !items.isEmpty {
                            dimensionGroup(dimension: dimension, items: items, checks: dashboard.todayChecks)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dimensionGroup(dimension: PlanDimension, items: [HealthPlanItem], checks: [HealthPlanCheck]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: dimension.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: dimension.color) ?? .primary)
                Text(dimension.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: dimension.color) ?? .primary)
            }

            ForEach(items) { item in
                let check = checks.first { $0.planItemId == item.id && $0.completed }
                PlanItemCard(
                    item: item,
                    isChecked: check != nil,
                    actualValue: check?.actualValue,
                    targetValue: item.targetValue,
                    onCheckIn: {
                        Task {
                            let client = try? settings.makeClient()
                            if let client { await viewModel.checkIn(planItem: item, using: client) }
                        }
                    },
                    onPause: {
                        Task {
                            let client = try? settings.makeClient()
                            if let client {
                                await viewModel.updateStatus(planItem: item, status: .paused, using: client)
                            }
                        }
                    },
                    onEdit: {
                        planItemToEdit = item
                    }
                )
            }
        }
    }

    // MARK: - Paused Plans

    @ViewBuilder
    private func pausedPlanSection(_ dashboard: HealthPlanDashboard) -> some View {
        if !dashboard.pausedItems.isEmpty {
            SectionCard(title: "已暂停", subtitle: "这些计划已暂停，可以随时恢复。") {
                VStack(spacing: 10) {
                    ForEach(dashboard.pausedItems) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "pause.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(item.frequency.label)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Button {
                                planItemToEdit = item
                            } label: {
                                Text("编辑")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                Task {
                                    let client = try? settings.makeClient()
                                    if let client {
                                        await viewModel.updateStatus(planItem: item, status: .active, using: client)
                                    }
                                }
                            } label: {
                                Text("恢复")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(12)
                        .background(Color.appGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Suggestions

    @ViewBuilder
    private func suggestionsSection(_ dashboard: HealthPlanDashboard) -> some View {
        SectionCard(title: "AI 建议", subtitle: "基于您最近的健康数据生成的个性化建议。") {
            VStack(spacing: 12) {
                if dashboard.suggestions.isEmpty && dashboard.planItems.isEmpty {
                    Text("点击下方按钮，AI 将根据您的健康数据生成个性化建议。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(dashboard.suggestions) { suggestion in
                    SuggestionCard(
                        suggestion: suggestion,
                        onAccept: {
                            suggestionToCustomize = suggestion
                        }
                    )
                }

                Button {
                    Task {
                        do {
                            let client = try settings.makeClient()
                            await viewModel.generateSuggestions(using: client)
                        } catch {}
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(viewModel.isGenerating ? "正在生成..." : "生成新建议")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#0f766e") ?? .teal, Color(hex: "#0d5263") ?? .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(.white)
                }
                .disabled(viewModel.isGenerating)
            }
        }
    }
}
