import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import VitalCommandMobileCore
#if canImport(UIKit)
import UIKit
#endif

struct DataHubScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = DataHubViewModel()
    @State private var isImporterPresented = false
    @State private var isCameraPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var lastNotifiedImportTaskID: String?
    @State private var lastNotifiedHealthSyncTaskID: String?
    @State private var selectedDataType: DataUploadType? = nil
    @State private var uploadOptionsType: DataUploadType?
    @State private var completionPrompt: ImportCompletionPrompt?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if viewModel.isUsingCache {
                        OfflineCacheBanner(
                            title: "当前为离线缓存数据页",
                            cachedAt: viewModel.cacheDate
                        )
                    }
                    addDataSection
                    coverageOverviewSection
                    healthDevicesSection
                    recentTasksSection
                    privacySection
                }
                .padding(16)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.99, blue: 0.97),
                        Color(red: 0.95, green: 0.96, blue: 0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("数据")
        }
        .task(id: settings.dashboardReloadKey) {
            await reload()
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: selectedDataType?.supportedDocumentTypes ?? [.pdf, .commaSeparatedText, .json, .spreadsheet, .item]
        ) { result in
            Task {
                await handleImportSelection(result)
            }
        }
        .sheet(item: $uploadOptionsType) { type in
            UploadMethodSheet(type: type) { method in
                Task { await presentUploadMethod(method, for: type) }
            }
        }
        .sheet(isPresented: $isPhotoPickerPresented) {
            MultiImagePickerView { images in
                Task { await submitSelectedImages(images, for: selectedDataType) }
            }
        }
        .sheet(isPresented: $isCameraPresented) {
            ImagePickerView(sourceType: .camera) { image in
                Task { await submitSelectedImages([image], for: selectedDataType) }
            }
        }
        .onChange(of: selectedDataType?.id) {
            viewModel.clearTransientImportFeedback()
        }
        .onChange(of: viewModel.latestImportTask.map { "\($0.importTaskId):\($0.isFinished)" }) {
            guard let task = viewModel.latestImportTask, task.isFinished else {
                return
            }

            guard lastNotifiedImportTaskID != task.importTaskId else {
                return
            }

            lastNotifiedImportTaskID = task.importTaskId
            settings.markHealthDataChanged()
            completionPrompt = completionPrompt(for: task)
        }
        .onChange(of: viewModel.latestHealthSyncResult?.importTaskId) {
            guard let result = viewModel.latestHealthSyncResult else {
                return
            }

            guard lastNotifiedHealthSyncTaskID != result.importTaskId else {
                return
            }

            lastNotifiedHealthSyncTaskID = result.importTaskId
            settings.markHealthDataChanged()
        }
        .sheet(item: $completionPrompt) { prompt in
            ImportCompletionSheet(prompt: prompt) {
                completionPrompt = nil
            } onPrimaryAction: {
                completionPrompt = nil
                switch prompt.actionTarget {
                case .home(let destination):
                    settings.openHome(destination: destination)
                }
            }
        }
    }

    // MARK: - Add Data Section

    private var addDataSection: some View {
        SectionCard(title: "添加数据", subtitle: selectedDataType == nil ? "先选择数据类型，再在弹出的窗口里选择拍照、图片或文件上传。" : "已选 \(selectedDataType!.rawValue) · 点卡片可重新选择上传方式") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(DataUploadType.allCases) { type in
                    Button {
                        selectedDataType = type
                        uploadOptionsType = type
                    } label: {
                        DataTypeCard(type: type, isSelected: selectedDataType == type)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let type = selectedDataType {
                HStack(spacing: 10) {
                    Image(systemName: type.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(type.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前选择：\(type.rawValue)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("上传方式会在独立窗口中选择，图片会在选完后自动提交。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("继续上传") {
                        uploadOptionsType = type
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(type.accentColor)
                }
                .padding(14)
                .background(
                    type.accentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }

            importProgressView
        }
    }

    @ViewBuilder
    private var importProgressView: some View {
        switch viewModel.importPhase {
        case .idle:
            EmptyView()

        case let .uploading(fileName):
            ImportProgressCard(
                icon: "arrow.up.circle.fill",
                iconColor: .blue,
                title: "正在上传",
                detail: fileName,
                showSpinner: true,
                progress: nil
            )

        case let .serverProcessing(_, elapsed):
            ImportProgressCard(
                icon: "gearshape.2.fill",
                iconColor: .orange,
                title: "AI 解析中",
                detail: elapsed < 10
                    ? "服务器正在处理您的文件…"
                    : "AI 正在提取健康数据（已等待 \(elapsed) 秒）",
                showSpinner: true,
                progress: min(Double(elapsed) / 60.0, 0.9)
            )

        case let .completed(success, total):
            ImportProgressCard(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                title: "解析完成",
                detail: "成功提取 \(success) / \(total) 条健康数据，首页已更新。",
                showSpinner: false,
                progress: 1.0
            )

        case let .failed(message):
            ImportProgressCard(
                icon: "xmark.circle.fill",
                iconColor: .red,
                title: "处理失败",
                detail: message,
                showSpinner: false,
                progress: nil
            )
        }
    }

    // MARK: - Account Coverage

    private var coverageOverviewSection: some View {
        SectionCard(
            title: "当前账号数据覆盖",
            subtitle: "只展示当前登录账号已导入、已分析、已生成的个人健康数据。"
        ) {
            if let payload = viewModel.dashboard {
                NavigationLink {
                    AccountCoverageOverviewScreen(
                        payload: payload,
                        currentUser: authManager.currentUser
                    )
                } label: {
                    AccountCoverageEntryCard(
                        displayName: authManager.currentUser?.displayName ?? "当前账号",
                        userId: authManager.currentUser?.id ?? "anonymous",
                        connectedCount: connectedCoverageCount(in: payload),
                        totalCount: coverageCategoryTotal,
                        annualExamCount: annualExamDocumentCount(in: payload),
                        geneticCount: payload.geneticFindings.count,
                        reportCount: payload.latestReports.count,
                        dimensionHighlights: Array(payload.sourceDimensions.prefix(3))
                    )
                }
                .buttonStyle(.plain)
            } else if let message = viewModel.state.errorMessage {
                VStack(alignment: .leading, spacing: 12) {
                    Text("暂时无法读取当前账号的数据覆盖情况。")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    Button("重新加载") {
                        Task { await reload() }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在读取当前账号的数据覆盖概览…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Health Devices Section

    private var healthDevicesSection: some View {
        SectionCard(title: "健康应用", subtitle: "同步手机和可穿戴设备的健康数据。Apple Health 作为统一数据中心，汇集各设备数据。") {
            VStack(spacing: 12) {
                // Apple Health - primary data source
                DeviceConnectionCard(
                    icon: "heart.fill",
                    iconColor: Color(hex: "#ef4444") ?? .red,
                    title: "苹果健康",
                    subtitle: viewModel.latestHealthSyncResult != nil ? "已授权，可同步体成分、活动、睡眠与生命体征" : "点击授权同步更完整的 Apple 健康数据",
                    isConnected: viewModel.latestHealthSyncResult != nil,
                    isCurrentDevice: true,
                    isSyncing: viewModel.isSyncingHealthKit
                ) {
                    Task { await syncAppleHealth() }
                }

                // Informational sync guide cards
                DeviceSyncGuideCard(
                    icon: "figure.run",
                    iconColor: Color(hex: "#22c55e") ?? .green,
                    title: "华为运动健康",
                    steps: ["打开「华为运动健康」APP", "我的 → 隐私管理 → 数据共享", "开启「Apple 健康」同步所有类别"]
                )

                DeviceSyncGuideCard(
                    icon: "applewatch",
                    iconColor: Color(hex: "#3b82f6") ?? .blue,
                    title: "Garmin 佳明",
                    steps: ["打开「Garmin Connect」APP", "更多 → 设置 → 健康数据", "开启「写入 Apple 健康」"]
                )

                DeviceSyncGuideCard(
                    icon: "bolt.heart.fill",
                    iconColor: Color(hex: "#f59e0b") ?? .orange,
                    title: "COROS 高驰",
                    steps: ["打开「COROS」APP", "我的 → 设置 → 健康", "开启「Apple 健康」授权同步"]
                )
            }

            // Tip banner
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color(hex: "#0f766e") ?? .teal)
                Text("上述设备开启同步后，数据会自动汇入 Apple Health。当前会同步体重、体脂、BMI、步数、距离、活动能量、训练分钟、睡眠，以及静息心率、步行心率、HRV、血氧和呼吸频率等常见维度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(hex: "#0f766e")?.opacity(0.05) ?? Color.teal.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )

            if let result = viewModel.latestHealthSyncResult {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近同步")
                        .font(.subheadline.weight(.semibold))
                    Text("成功 \(result.successRecords) / \(result.totalRecords)，覆盖 \(result.syncedKinds.count) 个维度")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let latestSampleTime = result.latestSampleTime {
                        Text("最新同步到 \(String(latestSampleTime.prefix(16)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(hex: "#0f766e")?.opacity(0.06) ?? Color.green.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }

            if viewModel.healthSyncState.pendingSampleCount > 0
                || viewModel.healthSyncState.lastCollectedAt != nil
                || viewModel.healthSyncState.lastSuccessfulSyncAt != nil
            {
                VStack(alignment: .leading, spacing: 10) {
                    Text("离线补同步状态")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 12) {
                        syncStatusPill(
                            title: "待上传",
                            value: "\(viewModel.healthSyncState.pendingSampleCount) 条",
                            tint: viewModel.healthSyncState.pendingSampleCount > 0 ? .orange : .green
                        )
                        if let lastCollectedAt = viewModel.healthSyncState.lastCollectedAt {
                            syncStatusPill(
                                title: "最近采集",
                                value: formatHealthSyncDate(lastCollectedAt),
                                tint: .blue
                            )
                        }
                    }

                    if let lastSuccessfulAt = viewModel.healthSyncState.lastSuccessfulSyncAt {
                        Text("最近成功补传：\(formatHealthSyncDate(lastSuccessfulAt))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let serverURL = viewModel.healthSyncState.lastSuccessfulServerURL {
                        Text("上传目标：\(serverURL)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let errorMessage = viewModel.healthSyncState.lastErrorMessage,
                       viewModel.healthSyncState.pendingSampleCount > 0 {
                        Text("最近错误：\(errorMessage)")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.orange.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        }
    }

    // MARK: - Recent Tasks

    private var recentTasksSection: some View {
        Group {
            if viewModel.latestImportTask != nil || !viewModel.importTasks.isEmpty {
                SectionCard(title: "最近任务", subtitle: "数据解析和导入状态。") {
                    VStack(spacing: 10) {
                        if let latestTask = viewModel.latestImportTask {
                            ImportTaskStatusCard(task: latestTask, isEmphasized: true)
                        }

                        ForEach(viewModel.importTasks.prefix(4)) { task in
                            ImportTaskStatusCard(task: task, isEmphasized: false)
                        }

                        Button("刷新任务状态") {
                            Task { await refreshTasks() }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        SectionCard(title: "隐私操作") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button("导出数据") {
                        Task { await invokePrivacyExport() }
                    }
                    .buttonStyle(.bordered)

                    Button("删除数据") {
                        Task { await invokePrivacyDelete() }
                    }
                    .buttonStyle(.bordered)
                }

                if let latestPrivacyMessage = viewModel.latestPrivacyMessage {
                    Text(latestPrivacyMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

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

    private func refreshTasks() async {
        do {
            let client = try settings.makeClient()
            await viewModel.refreshImportTasks(using: client)
        } catch {
            viewModel.setPrivacyMessage(error.localizedDescription)
        }
    }

    private func syncAppleHealth() async {
        do {
            let client = try settings.makeClient()
            await viewModel.syncAppleHealth(
                using: client,
                settings: settings,
                preferredToken: authManager.token
            )
        } catch {
            viewModel.setPrivacyMessage(error.localizedDescription)
        }
    }

    private func syncStatusPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formatHealthSyncDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func invokePrivacyExport() async {
        do {
            let client = try settings.makeClient()
            await viewModel.requestPrivacyExport(using: client)
        } catch {
            viewModel.setPrivacyMessage(error.localizedDescription)
        }
    }

    private func invokePrivacyDelete() async {
        do {
            let client = try settings.makeClient()
            await viewModel.requestPrivacyDelete(using: client)
        } catch {
            viewModel.setPrivacyMessage(error.localizedDescription)
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let startedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if startedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let fileData = try Data(contentsOf: url)
            let contentType = UTType(filenameExtension: url.pathExtension)
            let mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"
            let extractedText = await DocumentTextExtractor.extractText(
                from: url,
                data: fileData,
                contentType: contentType
            )
            let client = try settings.makeClient()
            viewModel.clearTransientImportFeedback()

            await viewModel.submitImport(
                fileName: url.lastPathComponent,
                mimeType: mimeType,
                fileData: fileData,
                extractedText: extractedText,
                using: client
            )
        } catch {
            viewModel.setPrivacyMessage(error.localizedDescription)
        }
    }

    private func submitSelectedImages(_ images: [UIImage], for type: DataUploadType?) async {
        guard images.isEmpty == false, let type else {
            return
        }

        do {
            let client = try settings.makeClient()
            let payloads = await ImageUploadPayloadBuilder.prepare(
                images: images,
                importerKey: type.importerKey,
                filePrefix: "photo"
            )

            guard payloads.isEmpty == false else {
                viewModel.setPrivacyMessage("无法处理所选图片")
                return
            }

            viewModel.selectedImporter = type.importerKey
            viewModel.clearTransientImportFeedback()
            await viewModel.submitImports(files: payloads, using: client)
        } catch {
            viewModel.setPrivacyMessage(error.localizedDescription)
        }
    }

    private func presentUploadMethod(_ method: UploadMethodOption, for type: DataUploadType) async {
        selectedDataType = type
        viewModel.selectedImporter = type.importerKey
        viewModel.clearTransientImportFeedback()
        uploadOptionsType = nil

        try? await Task.sleep(for: .milliseconds(220))

        switch method {
        case .camera:
            isCameraPresented = true
        case .photoLibrary:
            isPhotoPickerPresented = true
        case .pdfDocument, .tableFile:
            isImporterPresented = true
        }
    }

    private func completionPrompt(for task: ImportTaskSummary) -> ImportCompletionPrompt? {
        guard task.taskStatus == .completed || task.taskStatus == .completedWithErrors else {
            return nil
        }

        let preview = task.completionPreview
        let fallbackHeadline: String
        let fallbackDetail: String
        let fallbackActionTitle: String
        let fallbackTarget: ImportNavigationTarget

        switch task.importerKey ?? .activity {
        case .diet:
            fallbackHeadline = "饮食数据已完成解析"
            fallbackDetail = "饮食热量和记录覆盖已更新，可前往首页查看饮食健康AI洞察。"
            fallbackActionTitle = "去看饮食洞察"
            fallbackTarget = .home(.dietInsight)
        case .genetic:
            fallbackHeadline = "基因报告已完成解析"
            fallbackDetail = "基因结果已写入当前账号，可前往首页查看基因健康AI洞察。"
            fallbackActionTitle = "查看基因洞察"
            fallbackTarget = .home(.geneticInsight)
        case .annualExam, .bloodTest:
            fallbackHeadline = "体检报告已完成解析"
            fallbackDetail = "体检和检验结果已更新，可前往首页查看体检报告AI洞察。"
            fallbackActionTitle = "查看体检洞察"
            fallbackTarget = .home(.medicalInsight)
        default:
            fallbackHeadline = "数据已完成导入"
            fallbackDetail = "最新健康数据已经写入，可前往首页查看更新后的核心指标和趋势。"
            fallbackActionTitle = "查看首页概览"
            fallbackTarget = .home(nil)
        }

        return ImportCompletionPrompt(
            id: task.importTaskId,
            headline: preview?.headline ?? fallbackHeadline,
            detail: preview?.detail ?? fallbackDetail,
            actionTitle: preview?.actionTitle ?? fallbackActionTitle,
            actionTarget: navigationTarget(from: preview?.actionTarget) ?? fallbackTarget,
            recognizedFoods: preview?.recognizedFoods ?? [],
            estimatedCaloriesKcal: preview?.estimatedCaloriesKcal,
            mealUploadCount: preview?.mealUploadCount
        )
    }

    private func navigationTarget(from rawValue: String?) -> ImportNavigationTarget? {
        switch rawValue {
        case "home_diet_insight":
            return .home(.dietInsight)
        case "home_genetic_insight":
            return .home(.geneticInsight)
        case "home_medical_insight":
            return .home(.medicalInsight)
        case "home":
            return .home(nil)
        default:
            return nil
        }
    }

    private var coverageCategoryTotal: Int { 4 }

    private func connectedCoverageCount(in payload: HealthHomePageData) -> Int {
        [
            payload.annualExam != nil,
            payload.geneticFindings.isEmpty == false,
            payload.sourceDimensions.isEmpty == false,
            payload.latestReports.isEmpty == false
        ]
        .filter { $0 }
        .count
    }

    private func annualExamDocumentCount(in payload: HealthHomePageData) -> Int {
        guard let annualExam = payload.annualExam else { return 0 }
        return annualExam.previousTitle == nil ? 1 : 2
    }
}

private struct AccountCoverageOverviewScreen: View {
    let payload: HealthHomePageData
    let currentUser: UserInfo?

    private var connectedCount: Int {
        [
            payload.annualExam != nil,
            payload.geneticFindings.isEmpty == false,
            payload.sourceDimensions.isEmpty == false,
            payload.latestReports.isEmpty == false
        ]
        .filter { $0 }
        .count
    }

    private var annualExamCount: Int {
        guard let annualExam = payload.annualExam else { return 0 }
        return annualExam.previousTitle == nil ? 1 : 2
    }

    private var connectedItems: [AccountCoverageItem] {
        var items: [AccountCoverageItem] = []

        if let annualExam = payload.annualExam {
            items.append(
                AccountCoverageItem(
                    title: "体检报告",
                    subtitle: annualExam.latestTitle,
                    detail: annualExam.highlightSummary,
                    icon: "heart.text.clipboard.fill",
                    tint: Color(hex: "#0f766e") ?? .teal,
                    statusText: annualExamCount >= 2 ? "已接入 \(annualExamCount) 份" : "已接入"
                )
            )
        }

        if payload.geneticFindings.isEmpty == false {
            let firstFinding = payload.geneticFindings[0]
            items.append(
                AccountCoverageItem(
                    title: "基因健康分析",
                    subtitle: "已识别 \(payload.geneticFindings.count) 条个人基因结论",
                    detail: firstFinding.plainMeaning ?? firstFinding.summary,
                    icon: "allergens",
                    tint: Color(hex: "#7c3aed") ?? .purple,
                    statusText: "已接入"
                )
            )
        }

        if payload.sourceDimensions.isEmpty == false {
            let latestDimension = payload.sourceDimensions[0]
            items.append(
                AccountCoverageItem(
                    title: "趋势与设备数据",
                    subtitle: "覆盖 \(payload.sourceDimensions.count) 个健康维度",
                    detail: latestDimension.highlight,
                    icon: "waveform.path.ecg",
                    tint: Color(hex: "#2563eb") ?? .blue,
                    statusText: "持续更新"
                )
            )
        }

        if payload.latestReports.isEmpty == false {
            items.append(
                AccountCoverageItem(
                    title: "AI 周报 / 月报",
                    subtitle: "最近可查看 \(payload.latestReports.count) 份报告",
                    detail: payload.latestReports[0].summary.output.headline,
                    icon: "chart.bar.doc.horizontal.fill",
                    tint: Color(hex: "#ea580c") ?? .orange,
                    statusText: "已生成"
                )
            )
        }

        return items
    }

    private var pendingItems: [AccountCoverageItem] {
        var items: [AccountCoverageItem] = []

        if payload.annualExam == nil {
            items.append(
                AccountCoverageItem(
                    title: "体检报告",
                    subtitle: "当前账号还没有年度体检报告",
                    detail: "上传近两年的体检 PDF 或拍照件后，首页可生成更完整的纵向比较结论。",
                    icon: "heart.text.clipboard",
                    tint: Color(hex: "#0f766e") ?? .teal,
                    statusText: "待补充"
                )
            )
        }

        if payload.geneticFindings.isEmpty {
            items.append(
                AccountCoverageItem(
                    title: "基因健康分析",
                    subtitle: "当前账号还没有基因检测结果",
                    detail: "没有基因数据时，页面不会复用其他账号的基因结论。",
                    icon: "allergens",
                    tint: Color(hex: "#7c3aed") ?? .purple,
                    statusText: "未接入"
                )
            )
        }

        if payload.latestReports.isEmpty {
            items.append(
                AccountCoverageItem(
                    title: "AI 健康报告",
                    subtitle: "当前账号还没有生成周报或月报",
                    detail: "持续积累数据并触发分析后，将自动生成只属于当前账号的阶段性报告。",
                    icon: "chart.bar.doc.horizontal",
                    tint: Color(hex: "#ea580c") ?? .orange,
                    statusText: "待生成"
                )
            )
        }

        return items
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                accountIdentityCard
                coverageStatsSection
                connectedCoverageSection
                sourceDimensionsSection

                if pendingItems.isEmpty == false {
                    pendingCoverageSection
                }

                privacyNoteSection
            }
            .padding(16)
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("账号数据覆盖")
    }

    private var accountIdentityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#0f766e") ?? .teal, (Color(hex: "#2563eb") ?? .blue).opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)

                    Text(String((currentUser?.displayName ?? "当").prefix(1)))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(currentUser?.displayName ?? "当前账号")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("用户 ID：\(currentUser?.id ?? "anonymous")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    if let phoneNumber = currentUser?.phoneNumber, phoneNumber.isEmpty == false {
                        Text("手机号：\(phoneNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Text(payload.overviewHeadline)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(payload.overviewNarrative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            HStack(spacing: 10) {
                Label("仅显示当前账号数据", systemImage: "lock.shield.fill")
                Label("切换账号后独立刷新", systemImage: "person.2.crop.square.stack.fill")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color(hex: "#0f766e") ?? .teal)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white, Color(red: 0.94, green: 0.98, blue: 0.97)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke((Color(hex: "#0f766e") ?? .teal).opacity(0.12), lineWidth: 1)
        )
    }

    private var coverageStatsSection: some View {
        SectionCard(title: "覆盖摘要", subtitle: "当前账号在关键数据模块上的接入情况。") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                CoverageStatCard(
                    title: "核心覆盖",
                    value: "\(connectedCount)/4",
                    detail: "体检、基因、趋势、报告",
                    tint: Color(hex: "#0f766e") ?? .teal
                )
                CoverageStatCard(
                    title: "体检报告",
                    value: "\(annualExamCount) 份",
                    detail: annualExamCount > 0 ? "已纳入个人纵向比较" : "尚未接入",
                    tint: Color(hex: "#2563eb") ?? .blue
                )
                CoverageStatCard(
                    title: "基因结论",
                    value: "\(payload.geneticFindings.count) 条",
                    detail: payload.geneticFindings.isEmpty ? "当前账号暂无基因数据" : "仅来自当前账号上传",
                    tint: Color(hex: "#7c3aed") ?? .purple
                )
                CoverageStatCard(
                    title: "报告快照",
                    value: "\(payload.latestReports.count) 份",
                    detail: payload.latestReports.isEmpty ? "等待持续积累后生成" : "可查看最近 AI 报告",
                    tint: Color(hex: "#ea580c") ?? .orange
                )
            }
        }
    }

    private var connectedCoverageSection: some View {
        SectionCard(title: "已接入内容", subtitle: "这些数据已经参与当前账号的首页结论、趋势或洞察生成。") {
            VStack(spacing: 12) {
                ForEach(connectedItems) { item in
                    AccountCoverageRow(item: item)
                }
            }
        }
    }

    private var sourceDimensionsSection: some View {
        SectionCard(title: "覆盖维度", subtitle: "逐项查看每个健康维度的最近数据与 AI 摘要。") {
            VStack(spacing: 12) {
                ForEach(payload.sourceDimensions) { dimension in
                    CoverageDimensionRow(dimension: dimension)
                }
            }
        }
    }

    private var pendingCoverageSection: some View {
        SectionCard(title: "待补充内容", subtitle: "这些模块在当前账号下仍为空白，不会与其他账号混用。") {
            VStack(spacing: 12) {
                ForEach(pendingItems) { item in
                    AccountCoverageRow(item: item)
                }
            }
        }
    }

    private var privacyNoteSection: some View {
        SectionCard(title: "隔离说明", subtitle: "帮助你快速确认这个账号看到的数据范围。") {
            VStack(alignment: .leading, spacing: 12) {
                Label("首页结论、体检洞察、基因洞察均按当前账号独立读取。", systemImage: "checkmark.shield.fill")
                Label("没有导入的数据模块会显示为空或待补充，不会借用其他账号内容。", systemImage: "person.crop.circle.badge.exclamationmark")
                Label("切换账号后，请以此页为准检查当前账号的数据覆盖范围。", systemImage: "arrow.left.arrow.right.circle.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
        }
    }
}

private struct AccountCoverageEntryCard: View {
    let displayName: String
    let userId: String
    let connectedCount: Int
    let totalCount: Int
    let annualExamCount: Int
    let geneticCount: Int
    let reportCount: Int
    let dimensionHighlights: [HealthSourceDimensionCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("当前账号 · \(userId)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text("已覆盖 \(connectedCount)/\(totalCount) 个核心模块")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                CoverageMiniPill(title: "体检", value: annualExamCount > 0 ? "\(annualExamCount) 份" : "未接入", tint: Color(hex: "#0f766e") ?? .teal)
                CoverageMiniPill(title: "基因", value: geneticCount > 0 ? "\(geneticCount) 条" : "暂无", tint: Color(hex: "#7c3aed") ?? .purple)
                CoverageMiniPill(title: "报告", value: reportCount > 0 ? "\(reportCount) 份" : "暂无", tint: Color(hex: "#ea580c") ?? .orange)
            }

            if dimensionHighlights.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前已覆盖维度")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        ForEach(dimensionHighlights) { dimension in
                            Text(dimension.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(dimensionStatusColor(dimension.status))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    dimensionStatusColor(dimension.status).opacity(0.1),
                                    in: Capsule()
                                )
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white, Color(red: 0.96, green: 0.98, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke((Color(hex: "#0f766e") ?? .teal).opacity(0.12), lineWidth: 1)
        )
    }

    private func dimensionStatusColor(_ status: SourceDimensionStatus) -> Color {
        switch status {
        case .ready:
            return .green
        case .attention:
            return .orange
        case .background:
            return .blue
        }
    }
}

private struct CoverageStatCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CoverageMiniPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AccountCoverageItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let tint: Color
    let statusText: String
}

private struct AccountCoverageRow: View {
    let item: AccountCoverageItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(item.tint.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: item.icon)
                    .font(.title3)
                    .foregroundStyle(item.tint)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(item.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(item.tint.opacity(0.12), in: Capsule())
                }

                Text(item.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CoverageDimensionRow: View {
    let dimension: HealthSourceDimensionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(dimension.label)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let latestAt = dimension.latestAt {
                        Text("最近数据：\(latestAt)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }

            Text(dimension.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            Text(dimension.highlight)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineSpacing(3)

            if let insightSummary = dimension.insightSummary, insightSummary.isEmpty == false {
                Label(insightSummary, systemImage: "brain.head.profile")
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private var statusText: String {
        switch dimension.status {
        case .ready:
            return "已接入"
        case .attention:
            return "需补充"
        case .background:
            return "背景数据"
        }
    }
}

// MARK: - Import Progress Card

private struct ImportProgressCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String
    let showSpinner: Bool
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(iconColor)
                        if showSpinner {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            if let progress {
                ProgressView(value: progress)
                    .tint(iconColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            iconColor.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(iconColor.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct UploadMethodSheet: View {
    let type: DataUploadType
    let onSelect: (UploadMethodOption) -> Void
    @Environment(\.dismiss) private var dismiss

    private var methods: [UploadMethodOption] {
        var items: [UploadMethodOption] = []
        if type.allowsCamera { items.append(.camera) }
        if type.allowsPhoto { items.append(.photoLibrary) }
        if type.allowsPDF { items.append(.pdfDocument) }
        if type.allowsCSV { items.append(.tableFile) }
        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(type.accentColor.opacity(0.12))
                                .frame(width: 56, height: 56)

                            Image(systemName: type.icon)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(type.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(type.rawValue)
                                .font(.headline.weight(.bold))
                            Text("选择本次上传方式")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(type.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(methods) { method in
                            DataOptionCard(
                                icon: method.icon,
                                title: method.title,
                                subtitle: method.subtitle(for: type),
                                gradientColors: [type.accentColor, type.accentColor.opacity(0.76)]
                            ) {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                    onSelect(method)
                                }
                            }
                        }
                    }

                    if type == .diet || type == .genetic {
                        Text(type == .diet ? "饮食图片会自动识别食物与热量，并累计到当天概览。" : "基因图片、PDF 或结构化文件都会进入统一解析链路。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(16)
            }
            .navigationTitle("选择上传方式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ImportCompletionSheet: View {
    let prompt: ImportCompletionPrompt
    let onDismiss: () -> Void
    let onPrimaryAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(prompt.headline)
                                .font(.headline.weight(.bold))
                            Text("上传与解析已完成")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(prompt.detail)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if prompt.recognizedFoods.isEmpty == false || prompt.estimatedCaloriesKcal != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("解析结果")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                if let estimatedCaloriesKcal = prompt.estimatedCaloriesKcal {
                                    completionMetric(title: "热量", value: "\(Int(estimatedCaloriesKcal.rounded())) kcal")
                                }
                                if let mealUploadCount = prompt.mealUploadCount {
                                    completionMetric(title: "记录次数", value: "\(mealUploadCount) 次")
                                }
                            }

                            if prompt.recognizedFoods.isEmpty == false {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    ForEach(prompt.recognizedFoods, id: \.self) { food in
                                        Text(food)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.orange)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.orange.opacity(0.1), in: Capsule())
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                        .background(Color.appGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    VStack(spacing: 12) {
                        Button {
                            dismiss()
                            onPrimaryAction()
                        } label: {
                            Text(prompt.actionTitle)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("稍后再看") {
                            dismiss()
                            onDismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
            }
            .navigationTitle("完成")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func completionMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Data Option Card

private struct DataOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradientColors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: gradientColors.map { $0.opacity(0.12) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(gradientColors.first ?? .blue)
                }

                VStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(red: 0.05, green: 0.13, blue: 0.2))

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.white, Color(red: 0.97, green: 0.99, blue: 0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(gradientColors.first?.opacity(0.12) ?? Color.clear, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Device Connection Card

private struct DeviceConnectionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let isConnected: Bool
    let isCurrentDevice: Bool
    let isSyncing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(red: 0.05, green: 0.13, blue: 0.2))

                        if isCurrentDevice {
                            Text("当前机型")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(hex: "#0f766e") ?? .teal)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Color(hex: "#0f766e")?.opacity(0.1) ?? Color.teal.opacity(0.1),
                                    in: Capsule()
                                )
                        }
                    }

                    if isSyncing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("同步中...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(isConnected ? Color(hex: "#0f766e") ?? .teal : .secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.white,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isConnected
                            ? iconColor.opacity(0.15)
                            : Color(red: 0.05, green: 0.13, blue: 0.17).opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.02), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(isCurrentDevice || isConnected ? 1 : 0.6)
    }
}

// MARK: - Device Sync Guide Card

private struct DeviceSyncGuideCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let steps: [String]

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(iconColor.opacity(0.1))
                            .frame(width: 44, height: 44)

                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(iconColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(red: 0.05, green: 0.13, blue: 0.2))

                        Text("通过 Apple Health 桥接同步")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().padding(.vertical, 8)

                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(iconColor, in: Circle())

                            Text(step)
                                .font(.caption)
                                .foregroundStyle(Color(red: 0.05, green: 0.13, blue: 0.2))
                        }
                    }

                    Text("开启后，数据自动汇入 Apple Health")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.leading, 58)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.05, green: 0.13, blue: 0.17).opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 4, y: 2)
    }
}

// MARK: - Import Task Status Card

private struct ImportTaskStatusCard: View {
    let task: ImportTaskSummary
    let isEmphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                    if let sourceFile = task.sourceFile {
                        Text(sourceFile)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                StatusBadge(text: statusText, tint: statusColor)
            }

            Text("成功 \(task.successRecords) / \(max(task.totalRecords, task.successRecords))")
                .font(.footnote.weight(.medium))

            Text(task.completionPreview?.detail ?? (task.finishedAt == nil ? "后台处理中，可稍后回来查看结果。" : "任务已结束，可回首页刷新查看新趋势。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            statusColor.opacity(isEmphasized ? 0.08 : 0.04),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var statusColor: Color {
        switch task.taskStatus {
        case .running:
            .orange
        case .completed:
            .green
        case .completedWithErrors:
            .orange
        case .failed:
            .red
        }
    }

    private var statusText: String {
        switch task.taskStatus {
        case .running:
            "处理中"
        case .completed:
            "已完成"
        case .completedWithErrors:
            "部分完成"
        case .failed:
            "失败"
        }
    }
}

// MARK: - Data Upload Type

private enum DataUploadType: String, CaseIterable, Identifiable {
    case annualExam  = "年度体检"
    case bloodTest   = "医院检查"
    case bodyScale   = "体重体脂"
    case activity    = "运动健康"
    case genetic     = "基因报告"
    case diet        = "饮食健康"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .annualExam: return "heart.text.clipboard"
        case .bloodTest:  return "cross.vial.fill"
        case .bodyScale:  return "scalemass.fill"
        case .activity:   return "figure.run"
        case .genetic:    return "allergens"
        case .diet:       return "fork.knife"
        }
    }
    var description: String {
        switch self {
        case .annualExam: return "上传体检报告，形成年度基线与洞察"
        case .bloodTest:  return "导入医院复查，补齐血脂与生化趋势"
        case .bodyScale:  return "同步体重、BMI、体脂率等体成分"
        case .activity:   return "接入运动、步数、心率与活动消耗"
        case .genetic:    return "支持图片/文档/结构化文件的基因报告"
        case .diet:       return "上传饮食照片，按日累计热量与记录次数"
        }
    }
    var accentColor: Color {
        switch self {
        case .annualExam: return .teal
        case .bloodTest:  return Color(red: 0.85, green: 0.3, blue: 0.3)
        case .bodyScale:  return Color(red: 0.4, green: 0.55, blue: 0.9)
        case .activity:   return Color(red: 0.2, green: 0.75, blue: 0.5)
        case .genetic:    return Color(red: 0.7, green: 0.45, blue: 0.9)
        case .diet:       return Color(red: 0.96, green: 0.62, blue: 0.18)
        }
    }
    var importerKey: ImporterKey {
        switch self {
        case .annualExam: return .annualExam
        case .bloodTest:  return .bloodTest
        case .bodyScale:  return .bodyScale
        case .activity:   return .activity
        case .genetic:    return .genetic
        case .diet:       return .diet
        }
    }
    var allowsCamera: Bool { self == .annualExam || self == .bloodTest || self == .bodyScale || self == .activity || self == .genetic || self == .diet }
    var allowsPhoto: Bool { allowsCamera }
    var allowsPDF: Bool { self != .diet }
    var allowsCSV: Bool { self == .bodyScale || self == .activity || self == .genetic }
    var supportedDocumentTypes: [UTType] {
        switch self {
        case .diet:
            return [.image]
        case .genetic:
            return [.pdf, .commaSeparatedText, .json, .spreadsheet, .image, .item]
        case .bodyScale, .activity:
            return [.pdf, .commaSeparatedText, .json, .spreadsheet, .item]
        case .annualExam, .bloodTest:
            return [.pdf, .image, .item]
        }
    }
}

private enum UploadMethodOption: Identifiable {
    case camera
    case photoLibrary
    case pdfDocument
    case tableFile

    var id: String {
        switch self {
        case .camera: return "camera"
        case .photoLibrary: return "photo"
        case .pdfDocument: return "pdf"
        case .tableFile: return "table"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .photoLibrary: return "photo.on.rectangle"
        case .pdfDocument: return "doc.text.fill"
        case .tableFile: return "tablecells"
        }
    }

    var title: String {
        switch self {
        case .camera: return "拍照上传"
        case .photoLibrary: return "图片上传"
        case .pdfDocument: return "PDF 上传"
        case .tableFile: return "表格上传"
        }
    }

    func subtitle(for type: DataUploadType) -> String {
        switch self {
        case .camera:
            return "拍摄\(type.rawValue)内容后直接提交"
        case .photoLibrary:
            return "支持多选图片，选完会自动提交"
        case .pdfDocument:
            return "选择 PDF 文档进行解析"
        case .tableFile:
            return "导入 CSV / Excel / JSON 结构化文件"
        }
    }
}

private enum ImportNavigationTarget {
    case home(HomeDestination?)
}

private struct ImportCompletionPrompt: Identifiable {
    let id: String
    let headline: String
    let detail: String
    let actionTitle: String
    let actionTarget: ImportNavigationTarget
    let recognizedFoods: [String]
    let estimatedCaloriesKcal: Double?
    let mealUploadCount: Int?
}

// MARK: - Data Type Card

private struct DataTypeCard: View {
    let type: DataUploadType
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(colors: [type.accentColor, type.accentColor.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [type.accentColor.opacity(0.14), type.accentColor.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: isSelected ? type.accentColor.opacity(0.35) : .clear, radius: 6, y: 3)

                Image(systemName: type.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : type.accentColor)
            }

            Text(type.rawValue)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isSelected ? type.accentColor : .primary)

            Text(type.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? type.accentColor.opacity(0.06) : Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isSelected ? type.accentColor.opacity(0.45) : Color(.separator).opacity(0.3), lineWidth: isSelected ? 1.5 : 0.5)
                )
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(type.accentColor)
                    .padding(12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .shadow(color: isSelected ? type.accentColor.opacity(0.12) : Color.black.opacity(0.03), radius: isSelected ? 8 : 4, y: isSelected ? 3 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Image Picker

#if canImport(UIKit)
struct MultiImagePickerView: UIViewControllerRepresentable {
    var selectionLimit = 0
    let onImagesPicked: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiImagePickerView

        init(_ parent: MultiImagePickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard results.isEmpty == false else {
                parent.dismiss()
                return
            }

            Task {
                var images: [UIImage] = []

                for result in results {
                    if let image = await loadImage(from: result.itemProvider) {
                        images.append(image)
                    }
                }

                await MainActor.run {
                    parent.dismiss()
                }
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    parent.onImagesPicked(images)
                }
            }
        }

        private func loadImage(from provider: NSItemProvider) async -> UIImage? {
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                return nil
            }

            return await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
        }
    }
}

struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView

        init(_ parent: ImagePickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                self.parent.dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.parent.onImagePicked(image)
                }
                return
            }
            self.parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            self.parent.dismiss()
        }
    }
}

enum ImageUploadPayloadBuilder {
    static func prepare(
        images: [UIImage],
        importerKey: ImporterKey,
        filePrefix: String
    ) async -> [ImportUploadPayload] {
        var payloads: [ImportUploadPayload] = []

        for (index, image) in images.enumerated() {
            autoreleasepool {
                let prepared = downsampledImage(image, for: importerKey)
                guard let imageData = prepared.jpegData(compressionQuality: compressionQuality(for: importerKey)) else {
                    return
                }

                payloads.append(
                    ImportUploadPayload(
                        fileName: "\(filePrefix)_\(Int(Date().timeIntervalSince1970))_\(index + 1).jpg",
                        mimeType: "image/jpeg",
                        fileData: imageData,
                        extractedText: nil
                    )
                )
            }
        }

        guard shouldExtractText(for: importerKey) else {
            return payloads
        }

        var enrichedPayloads: [ImportUploadPayload] = []
        for (index, payload) in payloads.enumerated() {
            let extractedText = await DocumentTextExtractor.extractText(
                from: URL(fileURLWithPath: "/tmp/\(filePrefix)-\(index).jpg"),
                data: payload.fileData,
                contentType: .image
            )

            enrichedPayloads.append(
                ImportUploadPayload(
                    fileName: payload.fileName,
                    mimeType: payload.mimeType,
                    fileData: payload.fileData,
                    extractedText: extractedText
                )
            )
        }

        return enrichedPayloads
    }

    private static func shouldExtractText(for importerKey: ImporterKey) -> Bool {
        importerKey != .diet
    }

    private static func downsampledImage(_ image: UIImage, for importerKey: ImporterKey) -> UIImage {
        let normalized = normalizedImage(image)
        let maxDimension: CGFloat

        switch importerKey {
        case .diet:
            maxDimension = 1440
        case .genetic:
            maxDimension = 1800
        default:
            maxDimension = 1920
        }

        let longestEdge = max(normalized.size.width, normalized.size.height)
        guard longestEdge > maxDimension, longestEdge > 0 else {
            return normalized
        }

        let scale = maxDimension / longestEdge
        let targetSize = CGSize(width: normalized.size.width * scale, height: normalized.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else {
            return image
        }

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func compressionQuality(for importerKey: ImporterKey) -> CGFloat {
        switch importerKey {
        case .diet:
            return 0.78
        case .genetic:
            return 0.82
        default:
            return 0.84
        }
    }
}
#endif
