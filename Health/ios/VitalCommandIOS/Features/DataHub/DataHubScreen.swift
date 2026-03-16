import SwiftUI
import UniformTypeIdentifiers
import VitalCommandMobileCore
#if canImport(UIKit)
import UIKit
#endif

struct DataHubScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var viewModel = DataHubViewModel()
    @State private var isImporterPresented = false
    @State private var isCameraPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var lastNotifiedImportTaskID: String?
    @State private var lastNotifiedHealthSyncTaskID: String?
    @State private var showAddDataSheet = false
    @State private var selectedDataType: DataUploadType? = nil
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    addDataSection
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
        .onAppear {
            Task {
                await reload()
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf, .commaSeparatedText, .json, .spreadsheet, .item]
        ) { result in
            Task {
                await handleImportSelection(result)
            }
        }
        .sheet(isPresented: $isPhotoPickerPresented) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                Task { await handleImageUpload(image) }
            }
        }
        .sheet(isPresented: $isCameraPresented) {
            ImagePickerView(sourceType: .camera) { image in
                Task { await handleImageUpload(image) }
            }
        }
        .onChange(of: viewModel.latestImportTask.map { "\($0.importTaskId):\($0.isFinished)" }) { _ in
            guard let task = viewModel.latestImportTask, task.isFinished else {
                return
            }

            guard lastNotifiedImportTaskID != task.importTaskId else {
                return
            }

            lastNotifiedImportTaskID = task.importTaskId
            settings.markHealthDataChanged()
        }
        .onChange(of: viewModel.latestHealthSyncResult?.importTaskId) { _ in
            guard let result = viewModel.latestHealthSyncResult else {
                return
            }

            guard lastNotifiedHealthSyncTaskID != result.importTaskId else {
                return
            }

            lastNotifiedHealthSyncTaskID = result.importTaskId
            settings.markHealthDataChanged()
        }
    }

    // MARK: - Add Data Section

    private var addDataSection: some View {
        SectionCard(title: "添加数据", subtitle: selectedDataType == nil ? "选择数据类型，再选择上传方式。" : "已选：\(selectedDataType!.rawValue) · 选择上传方式") {
            // Layer 1: 2-column type card grid
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(DataUploadType.allCases) { type in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedDataType = selectedDataType == type ? nil : type
                        }
                    } label: {
                        DataTypeCard(type: type, isSelected: selectedDataType == type)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, selectedDataType != nil ? 4 : 0)

            // Layer 2: Upload method grid (contextual)
            if let type = selectedDataType {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    if type.allowsCamera {
                        DataOptionCard(
                            icon: "camera.fill",
                            title: "拍照上传",
                            subtitle: "拍摄\(type.rawValue)文档",
                            gradientColors: [Color(hex: "#3b82f6") ?? .blue, Color(hex: "#2563eb") ?? .blue]
                        ) {
                            viewModel.selectedImporter = type.importerKey
                            isCameraPresented = true
                        }
                    }

                    if type.allowsPhoto {
                        DataOptionCard(
                            icon: "photo.on.rectangle",
                            title: "图片上传",
                            subtitle: "从相册选择图片",
                            gradientColors: [Color(hex: "#8b5cf6") ?? .purple, Color(hex: "#7c3aed") ?? .purple]
                        ) {
                            viewModel.selectedImporter = type.importerKey
                            isPhotoPickerPresented = true
                        }
                    }

                    if type.allowsPDF {
                        DataOptionCard(
                            icon: "doc.text.fill",
                            title: "PDF 上传",
                            subtitle: "选择 PDF 文件",
                            gradientColors: [Color(hex: "#0f766e") ?? .teal, Color(hex: "#0d5263") ?? .cyan]
                        ) {
                            viewModel.selectedImporter = type.importerKey
                            isImporterPresented = true
                        }
                    }

                    if type.allowsCSV {
                        DataOptionCard(
                            icon: "tablecells",
                            title: "表格上传",
                            subtitle: "CSV / Excel 数据",
                            gradientColors: [Color(hex: "#ea580c") ?? .orange, Color(hex: "#dc2626") ?? .red]
                        ) {
                            viewModel.selectedImporter = type.importerKey
                            isImporterPresented = true
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("请先选择数据类型")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }

            if viewModel.isSubmittingImport {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在上传处理中...")
                        .font(.footnote)
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
                    subtitle: viewModel.latestHealthSyncResult != nil ? "已授权" : "点击授权同步",
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
                Text("上述设备开启同步后，数据会自动汇入 Apple Health。点击上方「苹果健康」即可统一同步到本应用。")
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
            await viewModel.load(using: client)
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
            await viewModel.syncAppleHealth(using: client)
        } catch {
            viewModel.setPrivacyMessage(error.localizedDescription)
        }
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

    private func handleImageUpload(_ image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            viewModel.setPrivacyMessage("无法处理图片")
            return
        }

        do {
            let client = try settings.makeClient()
            await viewModel.submitImport(
                fileName: "photo_\(Date().timeIntervalSince1970).jpg",
                mimeType: "image/jpeg",
                fileData: imageData,
                extractedText: nil,
                using: client
            )
        } catch {
            viewModel.setPrivacyMessage(error.localizedDescription)
        }
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

            Text(task.finishedAt == nil ? "后台处理中，可稍后回来查看结果。" : "任务已结束，可回首页刷新查看新趋势。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .annualExam: return "heart.text.clipboard"
        case .bloodTest:  return "cross.vial.fill"
        case .bodyScale:  return "scalemass.fill"
        case .activity:   return "figure.run"
        case .genetic:    return "allergens"
        }
    }
    var description: String {
        switch self {
        case .annualExam: return "体检报告、综合体检单"
        case .bloodTest:  return "血常规、生化、影像"
        case .bodyScale:  return "体重、BMI、体脂率"
        case .activity:   return "运动记录、心率、步数"
        case .genetic:    return "基因检测报告"
        }
    }
    var accentColor: Color {
        switch self {
        case .annualExam: return .teal
        case .bloodTest:  return Color(red: 0.85, green: 0.3, blue: 0.3)
        case .bodyScale:  return Color(red: 0.4, green: 0.55, blue: 0.9)
        case .activity:   return Color(red: 0.2, green: 0.75, blue: 0.5)
        case .genetic:    return Color(red: 0.7, green: 0.45, blue: 0.9)
        }
    }
    var importerKey: ImporterKey {
        switch self {
        case .annualExam: return .annualExam
        case .bloodTest:  return .bloodTest
        case .bodyScale:  return .bodyScale
        case .activity:   return .activity
        case .genetic:    return .genetic
        }
    }
    var allowsCamera: Bool { self != .genetic }
    var allowsPhoto: Bool { self != .genetic }
    var allowsPDF: Bool { true }
    var allowsCSV: Bool { self == .bodyScale || self == .activity || self == .genetic }
}

// MARK: - Data Type Card

private struct DataTypeCard: View {
    let type: DataUploadType
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(isSelected ? type.accentColor : type.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: type.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : type.accentColor)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(type.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(type.rawValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? type.accentColor : .primary)
                Text(type.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? type.accentColor.opacity(0.08) : Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? type.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Image Picker

#if canImport(UIKit)
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
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
