import SwiftUI
import Speech
import AVFoundation
import VitalCommandMobileCore

struct HomeScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var viewModel = HomeViewModel()
    @State private var activeSheet: HomeSheetDestination?
    @State private var showMedicalExamInsight = false
    @State private var showGeneticInsight = false

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("正在加载首页")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case let .failed(message):
                    EmptyStateCard(
                        title: "首页暂时不可用",
                        message: message,
                        actionTitle: "重试"
                    ) {
                        Task { await reload() }
                    }
                    .padding()

                case let .loaded(payload):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if viewModel.isUsingCache {
                                offlineBanner
                            }
                            heroSection(payload)

                            // — 有数据的模块优先展示 —
                            let hasAIOverview = !payload.overviewDigest.goodSignals.isEmpty
                                || !payload.overviewDigest.needsAttention.isEmpty
                                || !payload.overviewDigest.actionPlan.isEmpty
                            let hasPulse = !payload.charts.lipid.lines.isEmpty
                                || !payload.charts.bodyComposition.lines.isEmpty
                            let hasTrend = hasPulse
                            let hasGene = !payload.geneticFindings.isEmpty
                            let hasBody = compositionBars(from: payload).count > 0
                            let hasReminders = !payload.keyReminders.isEmpty
                            let hasReports = !payload.latestReports.isEmpty
                            let hasAnnualExam = payload.annualExam != nil

                            // 1. 有数据的核心模块
                            if hasAIOverview { aiOverviewSection(payload) }
                            if hasPulse { pulseSection(payload) }
                            if hasTrend { trendBoardSection(payload) }
                            if hasGene { geneInsightsSection(payload) }
                            if hasBody { bodyCompositionSection(payload) }
                            if hasReminders { remindersSection(payload) }
                            sourceDimensionsSection(payload)
                            if hasReports { reportsSection(payload) }

                            // 2. 无数据的模块 → 引导上传
                            if !hasAIOverview && !hasPulse {
                                uploadPromptCard(
                                    title: "暂无健康数据",
                                    message: "上传体检报告或连接 Apple 健康，即可获取 AI 健康分析和趋势追踪。",
                                    icon: "doc.text.magnifyingglass"
                                )
                            }
                            if !hasGene {
                                Button { showGeneticInsight = true } label: {
                                    uploadPromptCard(
                                        title: "基因健康维度",
                                        message: "上传基因检测报告后，可解锁遗传背景分析和个性化健康建议。",
                                        icon: "allergens"
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button { showGeneticInsight = true } label: {
                                    HStack {
                                        Image(systemName: "allergens")
                                            .font(.subheadline)
                                            .foregroundStyle(.teal)
                                        Text("查看基因健康洞察分析")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.teal)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.teal.opacity(0.6))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            if !hasAnnualExam && hasAIOverview {
                                Button { showMedicalExamInsight = true } label: {
                                    uploadPromptCard(
                                        title: "年度体检报告",
                                        message: "上传体检报告可追踪关键指标的年度变化趋势。",
                                        icon: "heart.text.clipboard"
                                    )
                                }
                                .buttonStyle(.plain)
                            } else if hasAnnualExam {
                                Button { showMedicalExamInsight = true } label: {
                                    HStack {
                                        Image(systemName: "heart.text.clipboard")
                                            .font(.subheadline)
                                            .foregroundStyle(.teal)
                                        Text("查看体检报告 AI 洞察分析")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.teal)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.teal.opacity(0.6))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            if !hasReports && hasAIOverview {
                                uploadPromptCard(
                                    title: "健康报告",
                                    message: "数据积累一周后将自动生成 AI 健康周报和月报。",
                                    icon: "chart.bar.doc.horizontal"
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 28)
                    }
                    .refreshable { await reload() }
                    .background(DashboardBackground().ignoresSafeArea())
                }
            }
            .navigationTitle("HealthAI")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsScreen()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.headline)
                    }

                    NavigationLink {
                        AIChatScreen(payload: viewModel.loadedPayload)
                    } label: {
                        AIToolbarButton()
                    }
                }
            }
        }
        .task(id: settings.dashboardReloadKey) {
            await reload()
        }
        .onAppear {
            Task {
                await reload()
            }
        }
        .sheet(item: $activeSheet) { destination in
            detailSheet(for: destination)
        }
        .sheet(isPresented: $showMedicalExamInsight) {
            DocumentInsightSheet(
                title: "体检报告洞察分析",
                insightType: "medical_exam",
                settings: settings
            )
        }
        .sheet(isPresented: $showGeneticInsight) {
            DocumentInsightSheet(
                title: "基因健康洞察分析",
                insightType: "genetic",
                settings: settings
            )
        }
    }

    @ViewBuilder
    private func detailSheet(for destination: HomeSheetDestination) -> some View {
        switch destination {
        case let .overview(block):
            AIOverviewDetailSheet(block: block)
        case let .gene(finding):
            GeneFindingDetailSheet(finding: finding)
        case let .reminder(reminder):
            ReminderDetailSheet(reminder: reminder)
        case let .sourceDimension(detail):
            SourceDimensionDetailSheet(detail: detail)
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("离线模式 · 显示缓存数据")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.7))
                if let date = viewModel.cacheDate {
                    Text("更新于 \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await reload() }
            } label: {
                Text("重试")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.15), lineWidth: 1)
        )
    }

    private func uploadPromptCard(title: String, message: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer()
            Image(systemName: "arrow.up.doc")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)
        }
        .padding(16)
        .background(Color.appGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func reload() async {
        do {
            let client = try settings.makeClient()
            await viewModel.load(using: client)
        } catch {
            viewModel.setError(error.localizedDescription)
        }
    }

    private func heroSection(_ payload: HealthHomePageData) -> some View {
        let scores = scoreItems(from: payload)

        return ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#0f766e") ?? .teal,
                            Color(hex: "#1d4ed8") ?? .blue,
                            Color(hex: "#34d399") ?? .mint
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.white.opacity(0.08))
                .blur(radius: 40)
                .offset(x: 50, y: -10)

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HealthAI")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("个人健康仪表盘")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))

                        Label("最近更新 \(formattedDate(payload.generatedAt))", systemImage: "sparkles")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }

                    Spacer()

                    StatusBadge(text: "AI 总览", tint: .white)
                }

                HStack(alignment: .center, spacing: 18) {
                    ScoreRingCluster(scores: scores)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(payload.latestNarrative.output.headline)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(3)

                        ForEach(scores) { item in
                            ScoreLegendRow(item: item)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("核心结论")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))

                    Text(payload.overviewDigest.summary)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if let action = payload.overviewDigest.actionPlan.first {
                        Label(action, systemImage: "sparkles")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(payload.overviewFocusAreas.prefix(5), id: \.self) { area in
                            Text(area)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.white.opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private func pulseSection(_ payload: HealthHomePageData) -> some View {
        SectionCard(title: "核心指标", subtitle: "快速查看关键数值和近期变化。") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(metricPulseCards(from: payload)) { item in
                    NavigationLink {
                        TrendDetailScreen(chart: item.chart, highlightedLineKey: item.primaryKey)
                    } label: {
                        MetricPulseCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func aiOverviewSection(_ payload: HealthHomePageData) -> some View {
        SectionCard(title: "AI 总览", subtitle: "结论、关注点和下一步建议。") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(aiOverviewBlocks(from: payload)) { block in
                    if block.lines.isEmpty || block.lines.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                        AIOverviewBlockCard(block: block)
                            .opacity(0.45)
                    } else {
                        Button {
                            activeSheet = .overview(block)
                        } label: {
                            AIOverviewBlockCard(block: block)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func trendBoardSection(_ payload: HealthHomePageData) -> some View {
        SectionCard(title: "趋势板", subtitle: "四个核心趋势，点击进入详细图表。") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(trendBoards(from: payload)) { board in
                    NavigationLink {
                        TrendDetailScreen(chart: board.chart)
                    } label: {
                        MiniTrendBoardCard(board: board)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func geneInsightsSection(_ payload: HealthHomePageData) -> some View {
        SectionCard(title: "基因健康维度", subtitle: "长期背景和相关指标。") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    SummaryBadge(
                        title: "背景数",
                        value: "\(payload.geneticFindings.count)",
                        tint: Color(hex: "#0f766e") ?? .teal
                    )
                    SummaryBadge(
                        title: "维度数",
                        value: "\(Set(payload.geneticFindings.map(\.dimension)).count)",
                        tint: Color(hex: "#2563eb") ?? .blue
                    )
                    SummaryBadge(
                        title: "高关注",
                        value: "\(payload.geneticFindings.filter { $0.riskLevel == "high" }.count)",
                        tint: Color(hex: "#dc2626") ?? .red
                    )
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(geneDimensionCards(from: payload)) { item in
                        Button {
                            activeSheet = .gene(item.finding)
                        } label: {
                            GeneDimensionCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func bodyCompositionSection(_ payload: HealthHomePageData) -> some View {
        SectionCard(title: "身体组成", subtitle: "体重、BMI、体脂和训练状态的趋势。") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(compositionBars(from: payload)) { metric in
                        NavigationLink {
                            TrendDetailScreen(chart: metric.chart, highlightedLineKey: metric.highlightedLineKey)
                        } label: {
                            CompositionBarCard(metric: metric)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sourceDimensionsSection(_ payload: HealthHomePageData) -> some View {
        SectionCard(title: "数据拼图", subtitle: "数据来源、最近记录和覆盖维度。") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(payload.sourceDimensions) { dimension in
                        Button {
                            activeSheet = .sourceDimension(sourceDimensionDetail(for: dimension, in: payload))
                        } label: {
                            DimensionChip(dimension: dimension)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func remindersSection(_ payload: HealthHomePageData) -> some View {
        SectionCard(title: "行动提示", subtitle: "当前优先处理的事项。") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(payload.keyReminders.prefix(4)) { item in
                        Button {
                            activeSheet = .reminder(item)
                        } label: {
                            ReminderCapsuleCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func reportsSection(_ payload: HealthHomePageData) -> some View {
        SectionCard(title: "最近报告", subtitle: "最近的周报与月报。") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(payload.latestReports) { report in
                        NavigationLink {
                            ReportDetailScreen(reportID: report.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    StatusBadge(
                                        text: report.reportType == .weekly ? "周报" : "月报",
                                        tint: report.reportType == .weekly ? .teal : .indigo
                                    )
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }

                                Text(report.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                Text(report.summary.output.headline)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(16)
                            .frame(width: 240, alignment: .leading)
                            .background(Color.appGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func metricPulseCards(from payload: HealthHomePageData) -> [MetricPulseCardModel] {
        [
            makePulseCard(
                title: "体重",
                subtitle: "当前体态",
                icon: "scalemass.fill",
                chart: payload.charts.bodyComposition,
                key: "weight",
                colorHex: "#0f766e",
                unitFormatter: { value in "\(numberString(value, digits: 1)) kg" },
                tone: .positive
            ),
            makePulseCard(
                title: "体脂率",
                subtitle: "减脂质量",
                icon: "drop.circle.fill",
                chart: payload.charts.bodyComposition,
                key: "bodyFat",
                colorHex: "#be123c",
                unitFormatter: { value in "\(numberString(value, digits: 1))%" },
                tone: toneForOverviewCard(payload, metricCode: "body.body_fat_pct")
            ),
            makePulseCard(
                title: "LDL-C",
                subtitle: "代谢压力",
                icon: "waveform.path.ecg.rectangle.fill",
                chart: payload.charts.lipid,
                key: "ldl",
                colorHex: "#0f766e",
                unitFormatter: { value in "\(numberString(value, digits: 2)) mmol/L" },
                tone: toneForOverviewCard(payload, metricCode: "lipid.ldl_c")
            ),
            makePulseCard(
                title: "步数",
                subtitle: "日常活动",
                icon: "figure.walk.circle.fill",
                chart: payload.charts.activity,
                key: "steps",
                colorHex: "#ea580c",
                unitFormatter: { value in "\(Int(value.rounded())) 步" },
                tone: .positive
            ),
            makePulseCard(
                title: "睡眠",
                subtitle: "恢复质量",
                icon: "moon.stars.fill",
                chart: payload.charts.recovery,
                key: "sleepMinutes",
                colorHex: "#2563eb",
                unitFormatter: { value in "\(numberString(value / 60, digits: 1)) h" },
                tone: recoveryTone(payload)
            ),
            makePulseCard(
                title: "Lp(a) 维度",
                subtitle: "基因背景",
                icon: "aqi.medium",
                chart: payload.charts.lipid,
                key: "lpa",
                colorHex: "#7c3aed",
                unitFormatter: { value in "\(Int(value.rounded())) mg/dL" },
                tone: geneTone(payload)
            )
        ]
    }

    private func trendBoards(from payload: HealthHomePageData) -> [MiniTrendBoardModel] {
        [
            makeTrendBoard(chart: payload.charts.lipid, primaryKey: "ldl"),
            makeTrendBoard(chart: payload.charts.bodyComposition, primaryKey: "bodyFat"),
            makeTrendBoard(chart: payload.charts.activity, primaryKey: "steps"),
            makeTrendBoard(chart: payload.charts.recovery, primaryKey: "sleepMinutes")
        ]
    }

    private func aiOverviewBlocks(from payload: HealthHomePageData) -> [AIOverviewBlock] {
        [
            AIOverviewBlock(
                title: "综合结论",
                icon: "brain.head.profile",
                color: Color(hex: "#0f766e") ?? .teal,
                lines: [payload.overviewDigest.headline]
            ),
            AIOverviewBlock(
                title: "好信号",
                icon: "checkmark.circle.fill",
                color: Color(hex: "#22c55e") ?? .green,
                lines: Array(payload.overviewDigest.goodSignals.prefix(2))
            ),
            AIOverviewBlock(
                title: "关注点",
                icon: "exclamationmark.triangle.fill",
                color: Color(hex: "#f59e0b") ?? .orange,
                lines: Array(payload.overviewDigest.needsAttention.prefix(2))
            ),
            AIOverviewBlock(
                title: "建议",
                icon: "sparkles",
                color: Color(hex: "#2563eb") ?? .blue,
                lines: Array(payload.overviewDigest.actionPlan.prefix(2))
            )
        ]
    }

    private func geneDimensionCards(from payload: HealthHomePageData) -> [GeneDimensionCardModel] {
        payload.geneticFindings.prefix(4).map { finding in
            GeneDimensionCardModel(
                title: finding.traitLabel,
                dimension: finding.dimension,
                riskText: riskText(finding.riskLevel),
                metricText: [finding.linkedMetricLabel, finding.linkedMetricValue].compactMap { $0 }.joined(separator: " · "),
                insight: finding.plainMeaning ?? finding.summary,
                color: geneRiskColor(finding.riskLevel),
                finding: finding
            )
        }
    }

    private func compositionBars(from payload: HealthHomePageData) -> [CompositionBarModel] {
        let annualMetricMap = Dictionary(uniqueKeysWithValues: (payload.annualExam?.metrics ?? []).map { ($0.metricCode, $0) })
        let candidates: [(String, String, String, String, ClosedRange<Double>)] = [
            ("体重", "body.weight", "weight", "#0f766e", 60 ... 95),
            ("BMI", "body.bmi", "bmi", "#2563eb", 18 ... 32),
            ("体脂率", "body.body_fat_pct", "bodyFat", "#be123c", 10 ... 32),
            ("训练分钟", "activity.exercise_minutes", "exerciseMinutes", "#ea580c", 0 ... 90)
        ]

        return candidates.compactMap { item in
            let latest: Double?
            let unit: String

            if let annualMetric = annualMetricMap[item.1] {
                latest = annualMetric.latestValue
                unit = annualMetric.unit
            } else if let chartValue = latestValue(in: chart(for: payload, alias: item.2), key: item.2) {
                latest = chartValue
                unit = chart(for: payload, alias: item.2).lines.first(where: { $0.key == item.2 })?.unit ?? ""
            } else {
                latest = nil
                unit = ""
            }

            guard let latest else {
                return nil
            }

            let progress = normalized(value: latest, in: item.4)
            return CompositionBarModel(
                title: item.0,
                valueText: formattedMetricValue(latest, key: item.2, unit: unit),
                progress: progress,
                color: Color(hex: item.3) ?? .accentColor,
                chart: chart(for: payload, alias: item.2),
                highlightedLineKey: item.2
            )
        }
    }

    private func sourceDimensionDetail(
        for dimension: HealthSourceDimensionCard,
        in payload: HealthHomePageData
    ) -> SourceDimensionDetailModel {
        let analyses = payload.dimensionAnalyses.filter { analysis in
            switch dimension.key {
            case "annual_exam", "lipid", "body":
                return analysis.key.contains("lipid") || analysis.key.contains("body")
            case "activity":
                return analysis.key.contains("activity") || analysis.key.contains("recovery")
            case "genetic":
                return true
            default:
                return false
            }
        }
        let relatedFindings = payload.geneticFindings.filter { finding in
            switch dimension.key {
            case "genetic":
                return true
            case "lipid":
                return finding.dimension.contains("血脂")
            case "activity":
                return finding.dimension.contains("运动") || finding.dimension.contains("恢复")
            case "body":
                return finding.dimension.contains("代谢") || finding.dimension.contains("运动")
            default:
                return false
            }
        }
        let highlights = uniqueLines(
            [
                dimension.summary,
                dimension.highlight,
                analyses.first?.summary,
                payload.annualExam?.highlightSummary,
                payload.annualExam?.actionSummary,
                relatedFindings.first.map { $0.plainMeaning ?? $0.summary }
            ]
        )

        return SourceDimensionDetailModel(
            card: dimension,
            highlights: highlights,
            analyses: analyses,
            relatedFindings: Array(relatedFindings.prefix(3))
        )
    }

    private func chart(for payload: HealthHomePageData, alias: String) -> HealthTrendChartModel {
        switch alias {
        case "weight", "bodyFat", "bmi":
            return payload.charts.bodyComposition
        case "exerciseMinutes":
            return payload.charts.activity
        case "sleepMinutes":
            return payload.charts.recovery
        default:
            return payload.charts.lipid
        }
    }

    private func makePulseCard(
        title: String,
        subtitle: String,
        icon: String,
        chart: HealthTrendChartModel,
        key: String,
        colorHex: String,
        unitFormatter: (Double) -> String,
        tone: DashboardTone
    ) -> MetricPulseCardModel {
        let values = series(in: chart, key: key)
        let latest = values.last ?? 0
        let delta = trendDeltaText(values: values, key: key, chart: chart)

        return MetricPulseCardModel(
            title: title,
            subtitle: subtitle,
            icon: icon,
            valueText: unitFormatter(latest),
            deltaText: delta,
            values: values,
            color: Color(hex: colorHex) ?? .accentColor,
            tone: tone,
            chart: chart,
            primaryKey: key
        )
    }

    private func makeTrendBoard(chart: HealthTrendChartModel, primaryKey: String) -> MiniTrendBoardModel {
        let primaryLine = chart.lines.first(where: { $0.key == primaryKey }) ?? chart.lines.first
        let values = series(in: chart, key: primaryLine?.key ?? primaryKey)
        let latest = values.last
        let latestText = latest.map { formattedMetricValue($0, key: primaryLine?.key ?? primaryKey, unit: primaryLine?.unit ?? "") } ?? "--"

        return MiniTrendBoardModel(
            title: chart.title.replacingOccurrences(of: "图", with: ""),
            valueText: latestText,
            detailText: primaryLine?.label ?? chart.title,
            values: values,
            color: Color(hex: primaryLine?.color ?? "#0f766e") ?? .accentColor,
            chart: chart
        )
    }

    private func toneForOverviewCard(_ payload: HealthHomePageData, metricCode: String) -> DashboardTone {
        guard let card = payload.overviewCards.first(where: { $0.metricCode == metricCode }) else {
            return .neutral
        }

        switch card.status {
        case .improving:
            return .positive
        case .watch:
            return .attention
        case .stable:
            return .neutral
        }
    }

    private func activityTone(_ payload: HealthHomePageData) -> DashboardTone {
        let average = averageValue(in: payload.charts.activity, key: "exerciseMinutes") ?? 0
        if average >= 45 {
            return .positive
        }
        if average >= 25 {
            return .neutral
        }
        return .attention
    }

    private func recoveryTone(_ payload: HealthHomePageData) -> DashboardTone {
        let average = averageValue(in: payload.charts.recovery, key: "sleepMinutes") ?? 0
        if average >= 420 {
            return .positive
        }
        if average >= 390 {
            return .neutral
        }
        return .attention
    }

    private func geneTone(_ payload: HealthHomePageData) -> DashboardTone {
        if payload.geneticFindings.contains(where: { $0.riskLevel == "high" }) {
            return .attention
        }
        if payload.geneticFindings.isEmpty {
            return .neutral
        }
        return .positive
    }

    private func scoreItems(from payload: HealthHomePageData) -> [DashboardScoreItem] {
        let metabolicValues = payload.overviewCards
            .filter { ["lipid.ldl_c", "lipid.total_cholesterol", "body.body_fat_pct"].contains($0.metricCode) }
            .map(\.status)
        let metabolicScore = metabolicValues.isEmpty ? 70 : metabolicValues.map(score(for:)).reduce(0, +) / Double(metabolicValues.count)
        let activityScore = min(max((averageValue(in: payload.charts.activity, key: "exerciseMinutes") ?? 0) / 60 * 100, 22), 100)
        let recoveryScore = min(max((averageValue(in: payload.charts.recovery, key: "sleepMinutes") ?? 0) / 480 * 100, 18), 100)

        return [
            DashboardScoreItem(label: "代谢", value: metabolicScore, color: Color(hex: "#34d399") ?? .mint),
            DashboardScoreItem(label: "执行", value: activityScore, color: Color(hex: "#fb923c") ?? .orange),
            DashboardScoreItem(label: "恢复", value: recoveryScore, color: Color(hex: "#60a5fa") ?? .blue)
        ]
    }

    private func score(for status: HealthStatus) -> Double {
        switch status {
        case .improving:
            return 88
        case .stable:
            return 72
        case .watch:
            return 45
        }
    }

    private func averageValue(in chart: HealthTrendChartModel, key: String) -> Double? {
        let values = series(in: chart, key: key)
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
    }

    private func series(in chart: HealthTrendChartModel, key: String) -> [Double] {
        chart.data.compactMap { $0.values[key] }
    }

    private func latestValue(in chart: HealthTrendChartModel, key: String) -> Double? {
        series(in: chart, key: key).last
    }

    private func trendDeltaText(values: [Double], key: String, chart: HealthTrendChartModel) -> String {
        guard values.count > 1 else {
            return "暂无对比"
        }

        let delta = values.last! - values.first!
        let sign = delta > 0 ? "+" : ""
        let unit = chart.lines.first(where: { $0.key == key })?.unit ?? ""
        let digits = unit == "kg" || unit == "%" || unit == "h" ? 1 : (unit == "mmol/L" ? 2 : 0)
        let format = "%.\(digits)f"
        let deltaText = String(format: format, delta)

        return unit.isEmpty ? "阶段变化 \(sign)\(deltaText)" : "阶段变化 \(sign)\(deltaText) \(unit)"
    }

    private func normalized(value: Double, in range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else {
            return 0
        }

        let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return min(max(progress, 0.08), 1)
    }

    private func formattedMetricValue(_ value: Double, key: String, unit: String) -> String {
        if key == "sleepMinutes" {
            return "\(numberString(value / 60, digits: 1)) h"
        }

        if key == "steps" {
            return "\(Int(value.rounded())) 步"
        }

        switch unit {
        case "kg", "%", "kg/m2":
            return "\(numberString(value, digits: 1)) \(unit)"
        case "mmol/L":
            return "\(numberString(value, digits: 2)) \(unit)"
        case "min":
            return "\(Int(value.rounded())) \(unit)"
        default:
            return unit.isEmpty ? numberString(value, digits: 1) : "\(numberString(value, digits: 1)) \(unit)"
        }
    }

    private func numberString(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    private func compactLine(_ line: String) -> String {
        let separators = ["；", "，", "。", ":", "："]

        for separator in separators {
            if let index = line.firstIndex(of: Character(separator)) {
                let candidate = String(line[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.count >= 8 {
                    return candidate
                }
            }
        }

        if line.count <= 26 {
            return line
        }

        return "\(line.prefix(24))..."
    }

    private func uniqueLines(_ items: [String?], limit: Int = 5) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for item in items {
            let trimmed = item?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard trimmed.isEmpty == false, seen.insert(trimmed).inserted else {
                continue
            }

            result.append(trimmed)

            if result.count >= limit {
                break
            }
        }

        return result
    }

    private func riskText(_ riskLevel: String) -> String {
        switch riskLevel {
        case "high":
            return "高关注"
        case "medium":
            return "中关注"
        default:
            return "低关注"
        }
    }

    private func geneRiskColor(_ riskLevel: String) -> Color {
        switch riskLevel {
        case "high":
            return Color(hex: "#dc2626") ?? .red
        case "medium":
            return Color(hex: "#f59e0b") ?? .orange
        default:
            return Color(hex: "#0f766e") ?? .teal
        }
    }

    private func formattedDate(_ rawValue: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: rawValue) else {
            return rawValue.prefix(10).description
        }

        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct DashboardBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#effcf8") ?? Color.green.opacity(0.08),
                    Color(hex: "#f7fbff") ?? Color.blue.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill((Color(hex: "#99f6e4") ?? .mint).opacity(0.24))
                .frame(width: 240, height: 240)
                .blur(radius: 36)
                .offset(x: -120, y: -280)

            Circle()
                .fill((Color(hex: "#93c5fd") ?? .blue).opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .offset(x: 120, y: -120)
        }
    }
}

private enum DashboardTone {
    case positive
    case neutral
    case attention

    var color: Color {
        switch self {
        case .positive:
            return Color(hex: "#0f766e") ?? .teal
        case .neutral:
            return Color(hex: "#2563eb") ?? .blue
        case .attention:
            return Color(hex: "#dc2626") ?? .red
        }
    }
}

private struct DashboardScoreItem: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

private struct MetricPulseCardModel: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let valueText: String
    let deltaText: String
    let values: [Double]
    let color: Color
    let tone: DashboardTone
    let chart: HealthTrendChartModel
    let primaryKey: String
}

private struct MiniTrendBoardModel: Identifiable {
    let id = UUID()
    let title: String
    let valueText: String
    let detailText: String
    let values: [Double]
    let color: Color
    let chart: HealthTrendChartModel
}

private struct CompositionBarModel: Identifiable {
    let id = UUID()
    let title: String
    let valueText: String
    let progress: Double
    let color: Color
    let chart: HealthTrendChartModel
    let highlightedLineKey: String
}

private struct AIOverviewBlock: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let lines: [String]
}

private struct GeneDimensionCardModel: Identifiable {
    let id = UUID()
    let title: String
    let dimension: String
    let riskText: String
    let metricText: String
    let insight: String
    let color: Color
    let finding: GeneticFindingView
}

private struct SourceDimensionDetailModel: Identifiable {
    let card: HealthSourceDimensionCard
    let highlights: [String]
    let analyses: [HealthDimensionAnalysis]
    let relatedFindings: [GeneticFindingView]

    var id: String { card.id }
}

private enum HomeSheetDestination: Identifiable {
    case overview(AIOverviewBlock)
    case gene(GeneticFindingView)
    case reminder(HealthReminderItem)
    case sourceDimension(SourceDimensionDetailModel)

    var id: String {
        switch self {
        case let .overview(block):
            return "overview-\(block.id)"
        case let .gene(finding):
            return "gene-\(finding.id)"
        case let .reminder(reminder):
            return "reminder-\(reminder.id)"
        case let .sourceDimension(detail):
            return "source-\(detail.id)"
        }
    }
}

private struct ScoreRingCluster: View {
    let scores: [DashboardScoreItem]

    private var averageScore: Int {
        Int((scores.map(\.value).reduce(0, +) / Double(max(scores.count, 1))).rounded())
    }

    var body: some View {
        ZStack {
            ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                RingGauge(progress: score.value / 100, lineWidth: CGFloat(18 - index * 4), color: score.color)
                    .frame(width: CGFloat(156 - index * 24), height: CGFloat(156 - index * 24))
            }

            VStack(spacing: 4) {
                Text("\(averageScore)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("健康分")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(width: 156, height: 156)
    }
}

private struct RingGauge: View {
    let progress: Double
    let lineWidth: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.42), radius: 8, y: 4)
        }
    }
}

private struct ScoreLegendRow: View {
    let item: DashboardScoreItem

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.color)
                .frame(width: 10, height: 10)

            Text(item.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Text("\(Int(item.value.rounded()))")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
    }
}

private struct AIToolbarButton: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.headline)
            Text("AI")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(Color(hex: "#2563eb") ?? .blue)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((Color(hex: "#dbeafe") ?? .blue.opacity(0.12)), in: Capsule())
    }
}

private struct HomeShortcutCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.headline.weight(.semibold))

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct SummaryBadge: View {
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

private struct MetricPulseCard: View {
    let item: MetricPulseCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: item.icon)
                    .font(.title3)
                    .foregroundStyle(item.color)
                Spacer()
                StatusBadge(text: statusText, tint: item.tone.color)
            }

            Text(item.valueText)
                .font(.title3.weight(.bold))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SparklineShape(values: item.values)
                .stroke(item.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(height: 36)

            Text(item.deltaText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(item.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statusText: String {
        switch item.tone {
        case .positive:
            return "理想"
        case .neutral:
            return "平稳"
        case .attention:
            return "关注"
        }
    }
}

private struct MiniTrendBoardCard: View {
    let board: MiniTrendBoardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(board.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(board.valueText)
                .font(.title3.weight(.bold))
                .foregroundStyle(board.color)

            SparklineShape(values: board.values)
                .stroke(board.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(height: 46)

            Text(board.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color.appGroupedBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct AIOverviewBlockCard: View {
    let block: AIOverviewBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: block.icon)
                    .foregroundStyle(block.color)
                Text(block.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            ForEach(block.lines.prefix(2), id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(block.color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(previewText(for: line))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
        .background(block.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func previewText(for line: String) -> String {
        let separators = ["；", "，", "。", ":", "："]

        for separator in separators {
            if let index = line.firstIndex(of: Character(separator)) {
                let candidate = String(line[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.count >= 8 {
                    return candidate
                }
            }
        }

        if line.count <= 24 {
            return line
        }

        return "\(line.prefix(22))..."
    }
}

private struct AIOverviewDetailSheet: View {
    let block: AIOverviewBlock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: block.icon)
                            .foregroundStyle(block.color)
                        Text(block.title)
                            .font(.title3.weight(.semibold))
                    }

                    ForEach(Array(block.lines.enumerated()), id: \.offset) { index, line in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("要点 \(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(block.color)
                            Text(line)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(block.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle(block.title)
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct GeneFindingDetailSheet: View {
    let finding: GeneticFindingView
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Text(finding.dimension)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(riskColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(riskColor.opacity(0.12), in: Capsule())
                        Spacer()
                        StatusBadge(text: riskText, tint: riskColor)
                    }

                    Text(finding.traitLabel)
                        .font(.title3.weight(.semibold))

                    detailBlock(title: "核心解释", value: finding.plainMeaning ?? finding.summary)
                    detailBlock(title: "建议", value: finding.practicalAdvice ?? finding.suggestion)

                    if let linkedMetricLabel = finding.linkedMetricLabel, let linkedMetricValue = finding.linkedMetricValue {
                        detailBlock(title: "关联指标", value: "\(linkedMetricLabel)：\(linkedMetricValue)")
                    }

                    detailBlock(title: "基因位点", value: finding.geneSymbol)
                    detailBlock(title: "证据等级", value: finding.evidenceLevel)
                    detailBlock(title: "记录时间", value: finding.recordedAt)
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("基因详情")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var riskColor: Color {
        switch finding.riskLevel {
        case "high":
            return Color(hex: "#dc2626") ?? .red
        case "medium":
            return Color(hex: "#f59e0b") ?? .orange
        default:
            return Color(hex: "#0f766e") ?? .teal
        }
    }

    private var riskText: String {
        switch finding.riskLevel {
        case "high":
            return "高关注"
        case "medium":
            return "中关注"
        default:
            return "低关注"
        }
    }

    @ViewBuilder
    private func detailBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(riskColor)
            Text(value)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(riskColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ReminderDetailSheet: View {
    let reminder: HealthReminderItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        StatusBadge(text: severityText, tint: severityColor)
                        Spacer()
                    }

                    Text(reminder.title)
                        .font(.title3.weight(.semibold))

                    detailBlock(title: "为什么值得关注", value: reminder.summary)
                    detailBlock(title: "建议动作", value: reminder.suggestedAction)

                    if let indicatorMeaning = reminder.indicatorMeaning {
                        detailBlock(title: "指标含义", value: indicatorMeaning)
                    }

                    if let practicalAdvice = reminder.practicalAdvice {
                        detailBlock(title: "执行建议", value: practicalAdvice)
                    }
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("行动详情")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var severityColor: Color {
        switch reminder.severity {
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
        switch reminder.severity {
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

    @ViewBuilder
    private func detailBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(severityColor)
            Text(value)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(severityColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct SourceDimensionDetailSheet: View {
    let detail: SourceDimensionDetailModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        StatusBadge(text: statusText, tint: statusColor)
                        Spacer()
                        if let latestAt = detail.card.latestAt {
                            Text(latestAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(detail.card.label)
                        .font(.title3.weight(.semibold))

                    detailBlock(title: "当前概况", items: detail.highlights, tint: statusColor)

                    if detail.analyses.isEmpty == false {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AI 归纳")
                                .font(.headline)

                            ForEach(detail.analyses) { analysis in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(analysis.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(analysis.summary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    ForEach(analysis.actionPlan.prefix(2), id: \.self) { action in
                                        Label(action, systemImage: "sparkles")
                                            .font(.footnote.weight(.medium))
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }
                    }

                    if detail.relatedFindings.isEmpty == false {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("相关基因背景")
                                .font(.headline)

                            ForEach(detail.relatedFindings) { finding in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(finding.traitLabel)
                                        .font(.subheadline.weight(.semibold))
                                    Text(finding.plainMeaning ?? finding.summary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("数据详情")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        switch detail.card.status {
        case .ready:
            return .green
        case .attention:
            return .orange
        case .background:
            return .blue
        }
    }

    private var statusText: String {
        switch detail.card.status {
        case .ready:
            return "已更新"
        case .attention:
            return "需关注"
        case .background:
            return "背景信息"
        }
    }

    private func detailBlock(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.monochrome)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Chat History Manager

@MainActor
final class ChatHistoryManager: ObservableObject {
    static let shared = ChatHistoryManager()

    @Published var conversations: [ChatConversation] = []

    private static let storageKey = "vital-command.chat-conversations"

    struct ChatConversation: Codable, Identifiable {
        let id: String
        var title: String
        var messages: [AIChatMessage]
        let createdAt: String
        var updatedAt: String

        init(id: String = UUID().uuidString, title: String, messages: [AIChatMessage], createdAt: String? = nil) {
            self.id = id
            self.title = title
            self.messages = messages
            let now = ISO8601DateFormatter().string(from: Date())
            self.createdAt = createdAt ?? now
            self.updatedAt = now
        }
    }

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        conversations = (try? JSONDecoder().decode([ChatConversation].self, from: data)) ?? []
    }

    func save(_ conversation: ChatConversation) {
        var updated = conversation
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = updated
        } else {
            conversations.insert(updated, at: 0)
        }
        persist()
    }

    func delete(id: String) {
        conversations.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Speech Recognizer

@MainActor
final class SpeechRecognizerManager: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var errorMessage: String?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    AVAudioApplication.requestRecordPermission { allowed in
                        DispatchQueue.main.async {
                            completion(allowed)
                        }
                    }
                default:
                    completion(false)
                }
            }
        }
    }

    func startRecording() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "语音识别不可用"
            return
        }

        stopRecording()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "无法启动音频会话"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal == true) {
                    self.stopRecording()
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            transcript = ""
        } catch {
            errorMessage = "无法启动语音引擎"
        }
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
}

// MARK: - AI Chat Screen

private struct AIChatScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    var payload: HealthHomePageData?

    @State private var conversationId = UUID().uuidString
    @State private var messages: [AIChatMessage] = [
        AIChatMessage(
            role: .assistant,
            content: "你好！我是你的 AI 健康助手，基于你的健康档案为你解答问题。试试下面的快捷提问，或直接输入你想了解的内容。"
        )
    ]
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showHistory = false
    @State private var didLoadHistory = false
    @State private var remoteSuggestedQuestions: [String] = []
    @StateObject private var speechManager = SpeechRecognizerManager()
    @StateObject private var historyManager = ChatHistoryManager.shared

    private let tealColor = Color(hex: "#0f766e") ?? .teal
    private let darkText = Color(red: 0.05, green: 0.13, blue: 0.2)

    private var suggestedQuestions: [String] {
        if !remoteSuggestedQuestions.isEmpty {
            return remoteSuggestedQuestions
        }
        guard let payload else {
            return [
                "我目前最该关注什么健康指标？",
                "最近的睡眠质量怎么样？",
                "我的体脂变化趋势如何？",
                "有哪些基因风险需要注意？",
                "帮我制定一个改善计划",
                "最近身体状态有什么变化？"
            ]
        }
        return buildPersonalizedQuestions(from: payload)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Chat header card
            chatHeaderCard

            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        if isSending {
                            TypingIndicator()
                                .id("typing-indicator")
                        }

                        if messages.count == 1 {
                            suggestedQuestionsSection
                        }

                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.97, blue: 0.95),
                            Color(red: 0.94, green: 0.96, blue: 0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isSending) {
                    if isSending {
                        scrollToBottom(proxy: proxy, anchor: .bottom)
                    }
                }
            }

            // Input bar
            inputBar
        }
        .navigationTitle("AI 对话")
        .appInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        startNewConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tealColor)
                    }
                    Button {
                        showHistory = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tealColor)
                            if historyManager.conversations.count > 0 {
                                Text("\(min(historyManager.conversations.count, 99))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 14, minHeight: 14)
                                    .background(Color.orange, in: Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet(historyManager: historyManager) { conversation in
                loadConversation(conversation)
            }
        }
        .onAppear {
            if !didLoadHistory, let latest = historyManager.conversations.first {
                loadConversation(latest)
                didLoadHistory = true
            }
            Task {
                guard let client = try? settings.makeClient() else { return }
                if let response = try? await client.fetchSuggestedQuestions() {
                    remoteSuggestedQuestions = response.questions
                }
            }
        }
        .onChange(of: speechManager.transcript) {
            if speechManager.isRecording {
                draft = speechManager.transcript
            }
        }
    }

    // MARK: - Chat Header

    private var chatHeaderCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tealColor, Color(hex: "#0d5263") ?? .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("HealthAI 助手")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(darkText)
                Text("基于你的健康数据提供个性化解读")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSending {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            ZStack {
                Color.white
                LinearGradient(
                    colors: [tealColor.opacity(0.04), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        )
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Suggested Questions

    private var suggestedQuestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Text("基于你的数据，你可以这样问")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(darkText)
            }
            .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                ForEach(Array(suggestedQuestions.enumerated()), id: \.offset) { index, question in
                    Button {
                        send(question)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(tealColor, in: Circle())
                            Text(question)
                                .font(.footnote.weight(.medium))
                                .foregroundColor(darkText)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(tealColor.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            LinearGradient(
                                colors: [Color.white, Color(red: 0.95, green: 0.98, blue: 0.97)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(tealColor.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.03), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.7))
        )
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 8) {
            if !suggestedQuestions.isEmpty && draft.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedQuestions, id: \.self) { question in
                            Button { draft = question } label: {
                                Text(question)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .frame(maxWidth: 200, alignment: .leading)
                                    .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .foregroundStyle(Color.teal)
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.teal.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 4)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Microphone button
                Button {
                    toggleVoiceInput()
                } label: {
                    Image(systemName: speechManager.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(speechManager.isRecording ? .red : tealColor)
                        .symbolEffect(.pulse, isActive: speechManager.isRecording)
                }
                .disabled(isSending)

                // Text field
                HStack(spacing: 8) {
                    TextField("输入你的健康问题...", text: $draft, axis: .vertical)
                        .lineLimit(1 ... 4)
                        .font(.subheadline)
                        .disabled(isSending)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.96, green: 0.97, blue: 0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )

                // Send button
                Button {
                    if speechManager.isRecording {
                        speechManager.stopRecording()
                    }
                    send(draft)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            (isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                ? Color.gray.opacity(0.4)
                                : tealColor
                        )
                }
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if speechManager.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("正在录音，点击麦克风停止...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Text("回答仅用于健康管理和数据解读，不替代医生诊断。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                Color.white
                LinearGradient(
                    colors: [Color.white, Color(red: 0.98, green: 0.99, blue: 0.97)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color(red: 0.6, green: 0.2, blue: 0.1))
            Spacer()
            Button("重试") {
                if let lastUser = messages.last(where: { $0.role == .user }) {
                    errorMessage = nil
                    resend(lastUser.content)
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tealColor)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy, anchor: UnitPoint = .bottom) {
        let targetId = isSending ? "typing-indicator" : messages.last?.id
        guard let targetId else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(targetId, anchor: anchor)
        }
    }

    private func toggleVoiceInput() {
        if speechManager.isRecording {
            speechManager.stopRecording()
        } else {
            speechManager.requestPermission { granted in
                if granted {
                    speechManager.startRecording()
                } else {
                    errorMessage = "请在系统设置中允许语音识别和麦克风权限"
                }
            }
        }
    }

    private func loadConversation(_ conversation: ChatHistoryManager.ChatConversation) {
        conversationId = conversation.id
        messages = conversation.messages
        showHistory = false
    }

    private func startNewConversation() {
        conversationId = UUID().uuidString
        messages = [
            AIChatMessage(
                role: .assistant,
                content: "你好！我是你的 AI 健康助手，基于你的健康档案为你解答问题。试试下面的快捷提问，或直接输入你想了解的内容。"
            )
        ]
        draft = ""
        errorMessage = nil
    }

    // MARK: - Personalized Questions

    private func buildPersonalizedQuestions(from data: HealthHomePageData) -> [String] {
        var questions: [String] = []

        // Q1: Based on attention items
        if let firstAttention = data.overviewDigest.needsAttention.first {
            let short = String(firstAttention.prefix(12)).trimmingCharacters(in: .whitespacesAndNewlines)
            questions.append("「\(short)」具体是什么情况？我应该怎么做？")
        } else {
            questions.append("我目前最需要关注哪个健康指标？")
        }

        // Q2: Based on genetic findings
        if let firstGene = data.geneticFindings.first {
            questions.append("\(firstGene.traitLabel) 的基因背景对我目前的指标有什么影响？")
        } else {
            questions.append("我有哪些潜在的基因健康风险需要留意？")
        }

        // Q3: Based on key reminders
        if let firstReminder = data.keyReminders.first {
            let short = String(firstReminder.title.prefix(14)).trimmingCharacters(in: .whitespacesAndNewlines)
            questions.append("关于「\(short)」，能给我一个具体的执行方案吗？")
        } else {
            questions.append("请帮我梳理一个近期的健康改善计划")
        }

        // Q4: Based on action plan
        if let action = data.overviewDigest.actionPlan.first {
            let short = String(action.prefix(14)).trimmingCharacters(in: .whitespacesAndNewlines)
            questions.append("「\(short)」这个建议的科学依据是什么？")
        } else {
            questions.append("最近我的运动和睡眠数据说明了什么？")
        }

        // Q5: Overall trend
        questions.append("综合我所有的健康数据，帮我总结一下最近一个月的整体趋势")

        // Q6: Body status (weight/body fat/BMI trends)
        let bodyDimension = data.sourceDimensions.first(where: {
            $0.label.contains("体重") || $0.label.contains("体脂") || $0.label.contains("身体")
        })
        if let bd = bodyDimension {
            let short = String(bd.summary.prefix(10)).trimmingCharacters(in: .whitespacesAndNewlines)
            questions.append("最近的体重体脂变化「\(short)」说明了什么？需要调整饮食运动吗？")
        } else {
            questions.append("根据我最近的身体数据，体重和体脂的趋势如何？需要注意什么？")
        }

        return questions
    }

    // MARK: - Send Message

    private func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false, isSending == false else { return }

        errorMessage = nil
        draft = ""

        let userMessage = AIChatMessage(role: .user, content: text)
        withAnimation(.easeOut(duration: 0.25)) {
            messages.append(userMessage)
        }
        isSending = true

        Task {
            do {
                let client = try settings.makeClient()
                let response = try await client.chatWithAI(AIChatRequest(messages: messages))

                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.25)) {
                        messages.append(response.reply)
                        isSending = false
                    }
                    saveCurrentConversation()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }

    private func resend(_ text: String) {
        isSending = true
        Task {
            do {
                let client = try settings.makeClient()
                let response = try await client.chatWithAI(AIChatRequest(messages: messages))
                await MainActor.run {
                    withAnimation {
                        messages.append(response.reply)
                        isSending = false
                    }
                    saveCurrentConversation()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }

    private func saveCurrentConversation() {
        let userMessages = messages.filter { $0.role == .user }
        guard userMessages.isEmpty == false else { return }
        let title = String(userMessages.first!.content.prefix(20))
        let conversation = ChatHistoryManager.ChatConversation(
            id: conversationId,
            title: title,
            messages: messages
        )
        historyManager.save(conversation)
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color(hex: "#0f766e")?.opacity(0.6) ?? .teal)
                        .frame(width: 8, height: 8)
                        .offset(y: phase == Double(index) ? -4 : 0)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.white, Color(red: 0.97, green: 0.99, blue: 0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 0.05, green: 0.13, blue: 0.17).opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
            Spacer(minLength: 36)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                phase = 2
            }
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                // AI avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#0f766e") ?? .teal, Color(hex: "#0d5263") ?? .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: "brain.head.profile")
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: message.role == .assistant ? .leading : .trailing, spacing: 6) {
            if message.role == .assistant {
                MarkdownContentView(
                    text: message.content,
                    textColor: Color(red: 0.05, green: 0.13, blue: 0.2)
                )
            } else {
                Text(message.content)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineSpacing(3)
            }

            if let createdAt = message.createdAt {
                Text(formatTimestamp(createdAt))
                    .font(.caption2)
                    .foregroundStyle(message.role == .assistant ? Color.gray.opacity(0.5) : Color.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            message.role == .assistant
                ? AnyShapeStyle(
                    LinearGradient(
                        colors: [Color.white, Color(red: 0.97, green: 0.99, blue: 0.98)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                : AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: "#0f766e") ?? .teal,
                            Color(hex: "#0d5263") ?? .cyan
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ),
            in: ChatBubbleShape(isUser: message.role == .user)
        )
        .overlay(
            ChatBubbleShape(isUser: message.role == .user)
                .stroke(
                    message.role == .assistant
                        ? Color(red: 0.05, green: 0.13, blue: 0.17).opacity(0.1)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
        .frame(maxWidth: .infinity, alignment: message.role == .assistant ? .leading : .trailing)
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "" }
        let display = DateFormatter()
        display.dateFormat = "HH:mm"
        return display.string(from: date)
    }
}

// MARK: - Markdown Content View

private struct MarkdownContentView: View {
    let text: String
    let textColor: Color

    private let tealAccent = Color(hex: "#0f766e") ?? .teal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    private enum MarkdownBlock {
        case heading(String)
        case bullet(String)
        case numbered(Int, String)
        case codeBlock(String)
        case paragraph(String)
    }

    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block
            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            // Heading (## or **heading**)
            if trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
                let headingText = trimmed.replacingOccurrences(of: "^#{2,3}\\s+", with: "", options: .regularExpression)
                blocks.append(.heading(headingText))
                i += 1
                continue
            }

            // Bold-only line as heading
            if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4 {
                let inner = String(trimmed.dropFirst(2).dropLast(2))
                if !inner.contains("**") {
                    blocks.append(.heading(inner))
                    i += 1
                    continue
                }
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("* ") {
                let content = String(trimmed.dropFirst(2))
                blocks.append(.bullet(content))
                i += 1
                continue
            }

            // Numbered list
            if let match = trimmed.range(of: "^(\\d+)\\.\\s+", options: .regularExpression) {
                let numStr = trimmed[match].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
                let content = String(trimmed[match.upperBound...])
                blocks.append(.numbered(Int(numStr) ?? 0, content))
                i += 1
                continue
            }

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Normal paragraph
            blocks.append(.paragraph(trimmed))
            i += 1
        }

        return blocks
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.subheadline.weight(.bold))
                .foregroundColor(textColor)
                .padding(.top, 4)

        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(tealAccent)
                    .frame(width: 5, height: 5)
                    .padding(.top, 6)
                styledText(text)
            }

        case .numbered(let num, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(num).")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundColor(tealAccent)
                    .frame(width: 18, alignment: .trailing)
                    .padding(.top, 1)
                styledText(text)
            }

        case .codeBlock(let code):
            Text(code)
                .font(.caption.monospaced())
                .foregroundColor(textColor.opacity(0.85))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .paragraph(let text):
            styledText(text)
        }
    }

    private func styledText(_ text: String) -> Text {
        var result = Text("")
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Bold: **text**
            if let boldStart = remaining.range(of: "**") {
                // Add text before bold
                let before = remaining[remaining.startIndex..<boldStart.lowerBound]
                result = result + inlineCodeAware(String(before))

                let afterBold = remaining[boldStart.upperBound...]
                if let boldEnd = afterBold.range(of: "**") {
                    let boldContent = afterBold[afterBold.startIndex..<boldEnd.lowerBound]
                    result = result + Text(String(boldContent)).bold()
                    remaining = afterBold[boldEnd.upperBound...]
                } else {
                    result = result + Text(String(remaining))
                    break
                }
            } else {
                result = result + inlineCodeAware(String(remaining))
                break
            }
        }

        return result
            .font(.subheadline)
            .foregroundColor(textColor)
    }

    private func inlineCodeAware(_ text: String) -> Text {
        var result = Text("")
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            if let codeStart = remaining.range(of: "`") {
                let before = remaining[remaining.startIndex..<codeStart.lowerBound]
                result = result + Text(String(before))

                let afterCode = remaining[codeStart.upperBound...]
                if let codeEnd = afterCode.range(of: "`") {
                    let codeContent = afterCode[afterCode.startIndex..<codeEnd.lowerBound]
                    result = result + Text(String(codeContent))
                        .font(.caption.monospaced())
                        .foregroundColor(tealAccent)
                    remaining = afterCode[codeEnd.upperBound...]
                } else {
                    result = result + Text(String(remaining))
                    break
                }
            } else {
                result = result + Text(String(remaining))
                break
            }
        }

        return result
    }
}

// MARK: - Chat Bubble Shape

private struct ChatBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let smallRadius: CGFloat = 4
        var path = Path()

        if isUser {
            // User: rounded except bottom-right
            path.addRoundedRect(
                in: rect,
                cornerRadii: RectangleCornerRadii(
                    topLeading: radius,
                    bottomLeading: radius,
                    bottomTrailing: smallRadius,
                    topTrailing: radius
                )
            )
        } else {
            // Assistant: rounded except bottom-left
            path.addRoundedRect(
                in: rect,
                cornerRadii: RectangleCornerRadii(
                    topLeading: radius,
                    bottomLeading: smallRadius,
                    bottomTrailing: radius,
                    topTrailing: radius
                )
            )
        }

        return path
    }
}

// MARK: - Chat History Sheet

private struct ChatHistorySheet: View {
    @ObservedObject var historyManager: ChatHistoryManager
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ChatHistoryManager.ChatConversation) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if historyManager.conversations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("暂无对话记录")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("与 AI 健康助手开始对话后，历史记录会自动保存在这里")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(historyManager.conversations) { conversation in
                            Button {
                                onSelect(conversation)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(conversation.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color(red: 0.05, green: 0.13, blue: 0.2))
                                        .lineLimit(1)

                                    HStack {
                                        Text("\(conversation.messages.count) 条消息")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(formatDate(conversation.updatedAt))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    historyManager.delete(id: conversation.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .appInsetGroupedListStyle()
                }
            }
            .navigationTitle("对话历史")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "plus.bubble.fill")
                            .foregroundStyle(Color(hex: "#0f766e") ?? .teal)
                    }
                }
            }
        }
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateFormat = "MM/dd HH:mm"
        return display.string(from: date)
    }
}

private struct GeneDimensionCard: View {
    let item: GeneDimensionCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.dimension)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(item.color.opacity(0.12), in: Capsule())
                Spacer()
                StatusBadge(text: item.riskText, tint: item.color)
            }

            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            if !item.metricText.isEmpty {
                Text(item.metricText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(item.insight)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
        .background(item.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct CompositionBarCard: View {
    let metric: CompositionBarModel

    var body: some View {
        VStack(spacing: 12) {
            Text(metric.title)
                .font(.subheadline.weight(.semibold))

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 32, height: 140)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [metric.color.opacity(0.48), metric.color],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 32, height: CGFloat(140 * metric.progress))
            }

            Text(metric.valueText)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(width: 84)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(metric.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ReminderCapsuleCard: View {
    let item: HealthReminderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(color)
                Spacer()
                StatusBadge(text: severityText, tint: color)
            }

            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            Text(item.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(width: 230)
        .frame(minHeight: 154, alignment: .topLeading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var color: Color {
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

    private var iconName: String {
        switch item.severity {
        case .positive:
            return "checkmark.seal.fill"
        case .low:
            return "bell.badge.fill"
        case .medium:
            return "exclamationmark.triangle.fill"
        case .high:
            return "cross.case.fill"
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

// MARK: - Document Insight Sheet

private struct DocumentInsightSheet: View {
    let title: String
    let insightType: String
    @ObservedObject var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var result: DocumentInsightResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.4)
                        Text("AI 正在分析您的健康数据…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("通常需要 15-30 秒")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("分析暂时不可用")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            Task { await loadInsights() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let result = result {
                    insightContent(result)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await loadInsights() }
    }

    @ViewBuilder
    private func insightContent(_ data: DocumentInsightResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Summary card
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI 综合分析", systemImage: "brain.head.profile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                    Text(data.summary)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Urgent items
                if !data.urgentItems.isEmpty {
                    sectionHeader("需立即关注", icon: "exclamationmark.circle.fill", color: .red)
                    ForEach(data.urgentItems) { item in
                        InsightItemCard(item: item, accentColor: .red)
                    }
                }

                // Attention items
                if !data.attentionItems.isEmpty {
                    sectionHeader("需要关注", icon: "eye.circle.fill", color: .orange)
                    ForEach(data.attentionItems) { item in
                        InsightItemCard(item: item, accentColor: .orange)
                    }
                }

                // Positive items
                if !data.positiveItems.isEmpty {
                    sectionHeader("好消息", icon: "checkmark.circle.fill", color: .green)
                    ForEach(data.positiveItems) { item in
                        InsightItemCard(item: item, accentColor: .green)
                    }
                }

                // Recommendations
                if !data.recommendations.isEmpty {
                    sectionHeader("行动建议", icon: "lightbulb.fill", color: .teal)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(data.recommendations.enumerated()), id: \.offset) { index, rec in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.teal, in: Circle())
                                Text(rec)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Disclaimer
                if !data.disclaimer.isEmpty {
                    Text(data.disclaimer)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }

                // Provider info
                HStack {
                    Spacer()
                    Text("由 \(data.provider) / \(data.model) 生成")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(16)
        }
        .background(Color.appGroupedBackground)
    }

    @ViewBuilder
    private func sectionHeader(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.top, 4)
    }

    private func loadInsights() async {
        isLoading = true
        errorMessage = nil
        do {
            let client = try settings.makeClient()
            result = try await client.fetchDocumentInsights(type: insightType)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct InsightItemCard: View {
    let item: InsightItem
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let action = item.action {
                    Text(action)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(accentColor)
                }
            }
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let metrics = item.relatedMetrics, !metrics.isEmpty {
                HStack(spacing: 4) {
                    ForEach(metrics, id: \.self) { metric in
                        Text(metric)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accentColor.opacity(0.08), in: Capsule())
                            .foregroundStyle(accentColor.opacity(0.7))
                    }
                }
            }
        }
        .padding(12)
        .background(accentColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private var severityText: String {
        switch item.severity {
        case "high": return "紧急"
        case "medium": return "关注"
        case "low": return "提示"
        default: return "积极"
        }
    }
}
