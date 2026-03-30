import SwiftUI
import VitalCommandMobileCore

struct HealthPlanScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = HealthPlanViewModel()
    @State private var acceptedPlanItem: HealthPlanItem?
    @State private var showPostAcceptOptions = false
    @State private var suggestionToCustomize: HealthSuggestion?
    @State private var planItemToEdit: HealthPlanItem?
    @State private var enableReminder = true
    @State private var enableCalendar = true
    @State private var showAcceptToast = false

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
                            if viewModel.isUsingCache {
                                OfflineCacheBanner(
                                    title: "当前为离线缓存计划，暂时只读",
                                    cachedAt: viewModel.cacheDate
                                )
                            }
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
        .overlay(alignment: .top) {
            if showAcceptToast {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("计划已成功添加！")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
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
        .sheet(isPresented: $showPostAcceptOptions) {
            if let item = acceptedPlanItem {
                PostAcceptSheet(
                    planItem: item,
                    enableReminder: $enableReminder,
                    enableCalendar: $enableCalendar,
                    onConfirm: {
                        Task {
                            if enableReminder {
                                await LocalNotificationManager.schedulePlanReminder(planItem: item)
                            }
                            if enableCalendar {
                                await CalendarIntegration.createEvent(for: item)
                            }
                        }
                        showPostAcceptOptions = false
                    }
                )
            }
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
                            withAnimation { showAcceptToast = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation { showAcceptToast = false }
                            }
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
            await viewModel.load(
                using: client,
                cacheScope: settings.cacheScope(userID: authManager.currentUser?.id)
            )
        } catch {
            viewModel.setError(error.localizedDescription)
        }
    }

    // MARK: - Progress Header

    @ViewBuilder
    private func progressHeader(_ dashboard: HealthPlanDashboard) -> some View {
        VStack(spacing: 12) {
            SectionCard(title: "今日进度", subtitle: progressSubtitle(dashboard)) {
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

            // Weekly day dots row
            weeklyDayDotsRow(dashboard)
        }
    }

    private func progressSubtitle(_ dashboard: HealthPlanDashboard) -> String {
        let rate = Int(dashboard.stats.weekCompletionRate * 100)
        if dashboard.stats.todayCompleted == dashboard.stats.todayTotal && dashboard.stats.todayTotal > 0 {
            return "🎉 今日任务全部完成！"
        } else if rate >= 80 {
            return "本周表现优秀，继续保持！"
        } else if rate >= 50 {
            return "坚持就是胜利，加油！"
        } else {
            return "每天一小步，健康一大步。"
        }
    }

    @ViewBuilder
    private func weeklyDayDotsRow(_ dashboard: HealthPlanDashboard) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Generate last 7 days (Mon-Sun or last 7)
        let weekDays = (0..<7).compactMap { offset -> Date? in
            calendar.date(byAdding: .day, value: -6 + offset, to: today)
        }
        let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]

        SectionCard(title: "本周记录", subtitle: nil) {
            HStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                    let isToday = calendar.isDateInToday(day)
                    let dayOfWeek = calendar.component(.weekday, from: day) // 1=Sun
                    let label = dayOfWeek == 1 ? "日" : dayLabels[dayOfWeek - 2]
                    // Determine completion: use weekCompletionRate as proxy for past days
                    let isPast = day < today
                    let isCompleted = isPast && index < Int(dashboard.stats.weekCompletionRate * 6.0)

                    VStack(spacing: 4) {
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isToday ? Color(hex: "#0f766e") ?? .teal : .secondary)

                        ZStack {
                            Circle()
                                .fill(isToday ? (dashboard.stats.todayCompleted > 0 ? (Color(hex: "#10b981") ?? .green) : (Color(hex: "#0f766e") ?? .teal).opacity(0.15)) :
                                    isCompleted ? (Color(hex: "#10b981") ?? .green).opacity(0.8) :
                                    isPast ? Color.secondary.opacity(0.15) : Color.secondary.opacity(0.08))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .strokeBorder(isToday ? (Color(hex: "#0f766e") ?? .teal) : .clear, lineWidth: 2)
                                )

                            if isToday && dashboard.stats.todayCompleted > 0 {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            } else if isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            } else if isPast {
                                Image(systemName: "minus")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
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

// MARK: - Post Accept Sheet

private struct PostAcceptSheet: View {
    let planItem: HealthPlanItem
    @Binding var enableReminder: Bool
    @Binding var enableCalendar: Bool
    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Celebration header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#10b981") ?? .green, Color(hex: "#0d9488") ?? .teal],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 64, height: 64)
                            Image(systemName: "checkmark")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Text("计划已添加！")
                            .font(.title3.weight(.bold))
                        Text("「\(planItem.title)」已加入您的健康计划")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    // Plan details card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: planItem.dimension.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(hex: planItem.dimension.color) ?? .teal)
                                .frame(width: 32, height: 32)
                                .background((Color(hex: planItem.dimension.color) ?? .teal).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(planItem.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(planItem.dimension.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Divider()
                        HStack(spacing: 16) {
                            Label(planItem.frequency.label, systemImage: "repeat")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let hint = planItem.timeHint, !hint.isEmpty {
                                Label(hint, systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 2)

                    // Reminder options
                    VStack(spacing: 0) {
                        Text("设置跟进提醒")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)

                        VStack(spacing: 2) {
                            ReminderToggleRow(
                                icon: "bell.fill",
                                iconColor: .orange,
                                title: "本地通知提醒",
                                subtitle: "在计划时间前提醒你完成",
                                isOn: $enableReminder
                            )
                            Divider().padding(.leading, 52)
                            ReminderToggleRow(
                                icon: "calendar",
                                iconColor: .blue,
                                title: "添加到系统日历",
                                subtitle: "自动添加重复日历事件",
                                isOn: $enableCalendar
                            )
                        }
                        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 2)

                    // Confirm button
                    Button(action: onConfirm) {
                        Text((enableReminder || enableCalendar) ? "完成并开启提醒" : "完成")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#0f766e") ?? .teal, Color(hex: "#0d9488") ?? .teal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("🎯 计划已接受")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("跳过") { dismiss() }
                        .font(.subheadline)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ReminderToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.teal)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
