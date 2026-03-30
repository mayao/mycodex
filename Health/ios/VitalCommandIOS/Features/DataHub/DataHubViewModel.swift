import Foundation
import SwiftUI
import VitalCommandMobileCore

struct ImportUploadPayload {
    let fileName: String
    let mimeType: String
    let fileData: Data
    let extractedText: String?
}

enum ImportPhase: Equatable {
    case idle
    case uploading(fileName: String)
    case serverProcessing(taskId: String, elapsed: Int)
    case completed(success: Int, total: Int)
    case failed(message: String)

    var isActive: Bool {
        switch self {
        case .uploading, .serverProcessing: return true
        default: return false
        }
    }
}

@MainActor
final class DataHubViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[HealthImportOption]> = .idle
    @Published var selectedImporter: ImporterKey = .annualExam
    @Published private(set) var dashboard: HealthHomePageData?
    @Published private(set) var importTasks: [ImportTaskSummary] = []
    @Published private(set) var latestImportTask: ImportTaskSummary?
    @Published private(set) var latestHealthSyncResult: HealthKitSyncResult?
    @Published private(set) var latestPrivacyMessage: String?
    @Published private(set) var isSubmittingImport = false
    @Published private(set) var isSyncingHealthKit = false
    @Published private(set) var importPhase: ImportPhase = .idle
    @Published private(set) var healthSyncState = HealthKitSyncState()
    @Published private(set) var isUsingCache = false
    @Published private(set) var cacheDate: Date?

    private let healthKitService = HealthKitSyncService()
    private let healthSyncStateStore = HealthKitSyncStateStore()
    private let fileStore = MobileFileStore(namespace: "HealthAI")
    private var importPollingTask: Task<Void, Never>?
    private var importPhaseResetTask: Task<Void, Never>?

    deinit {
        importPollingTask?.cancel()
        importPhaseResetTask?.cancel()
    }

    func setError(_ message: String) {
        state = .failed(message)
    }

    func setPrivacyMessage(_ message: String) {
        latestPrivacyMessage = message
    }

    func load(using client: HealthAPIClient, cacheScope: String) async {
        if case .loading = state {
            return
        }

        healthSyncState = healthSyncStateStore.loadState()
        if latestHealthSyncResult == nil {
            latestHealthSyncResult = healthSyncState.lastResult
        }

        let dashboardCacheFile = "data-hub-dashboard-\(sanitizeCacheScope(cacheScope)).json"
        let taskCacheFile = "data-hub-tasks-\(sanitizeCacheScope(cacheScope)).json"

        if case .idle = state,
           let cachedDashboard = fileStore.load(CachedPayload<HealthHomePageData>.self, fileName: dashboardCacheFile) {
            dashboard = cachedDashboard.value
            state = .loaded(cachedDashboard.value.importOptions)
            isUsingCache = true
            cacheDate = cachedDashboard.cachedAt
        }
        if importTasks.isEmpty,
           let cachedTasks = fileStore.load(CachedPayload<[ImportTaskSummary]>.self, fileName: taskCacheFile) {
            importTasks = cachedTasks.value
        }

        if dashboard == nil {
            state = .loading
        }

        do {
            async let dashboardPayloadTask = client.fetchDashboard()
            async let taskResponse = client.fetchImportTasks()

            let (dashboardPayload, taskPayload) = try await (dashboardPayloadTask, taskResponse)
            dashboard = dashboardPayload
            state = .loaded(dashboardPayload.importOptions)
            importTasks = taskPayload.tasks
            isUsingCache = false
            cacheDate = nil
            _ = fileStore.save(CachedPayload(value: dashboardPayload), fileName: dashboardCacheFile)
            _ = fileStore.save(CachedPayload(value: taskPayload.tasks), fileName: taskCacheFile)

            if let runningTask = taskPayload.tasks.first(where: { !$0.isFinished }) {
                startPolling(taskID: runningTask.importTaskId, using: client)
            }
        } catch {
            if dashboard != nil {
                isUsingCache = true
            } else if let cachedDashboard = fileStore.load(CachedPayload<HealthHomePageData>.self, fileName: dashboardCacheFile) {
                dashboard = cachedDashboard.value
                state = .loaded(cachedDashboard.value.importOptions)
                isUsingCache = true
                cacheDate = cachedDashboard.cachedAt
            } else {
                dashboard = nil
                state = .failed(error.localizedDescription)
            }
        }
    }

    func refreshImportTasks(using client: HealthAPIClient) async {
        do {
            importTasks = try await client.fetchImportTasks().tasks
        } catch {
            latestPrivacyMessage = error.localizedDescription
        }
    }

    func submitImport(
        fileName: String,
        mimeType: String,
        fileData: Data,
        extractedText: String?,
        using client: HealthAPIClient
    ) async {
        await submitImports(
            files: [
                ImportUploadPayload(
                    fileName: fileName,
                    mimeType: mimeType,
                    fileData: fileData,
                    extractedText: extractedText
                )
            ],
            using: client
        )
    }

    func submitImports(
        files: [ImportUploadPayload],
        using client: HealthAPIClient
    ) async {
        guard files.isEmpty == false else {
            return
        }

        isSubmittingImport = true
        defer { isSubmittingImport = false }

        var acceptedTasks: [ImportTaskSummary] = []
        var failedMessages: [String] = []

        for (index, file) in files.enumerated() {
            let displayName =
                files.count == 1
                    ? file.fileName
                    : "\(index + 1)/\(files.count) · \(file.fileName)"
            setImportPhase(.uploading(fileName: displayName))

            do {
                let response = try await client.importData(
                    importerKey: selectedImporter,
                    fileName: file.fileName,
                    mimeType: file.mimeType,
                    fileData: file.fileData,
                    extractedText: file.extractedText
                )
                latestImportTask = response.task
                merge(task: response.task)
                acceptedTasks.append(response.task)
            } catch {
                failedMessages.append("\(file.fileName)：\(importErrorMessage(for: error))")
            }
        }

        guard let lastTask = acceptedTasks.last else {
            let message = failedMessages.first ?? "上传失败，请稍后重试。"
            setImportPhase(.failed(message: message), autoResetAfter: 4)
            if failedMessages.count > 1 {
                latestPrivacyMessage = failedMessages.joined(separator: "\n")
            }
            return
        }

        if failedMessages.isEmpty == false {
            latestPrivacyMessage = failedMessages.joined(separator: "\n")
        }

        setImportPhase(.serverProcessing(taskId: lastTask.importTaskId, elapsed: 0))
        await refreshImportTasks(using: client)
        startPolling(taskID: lastTask.importTaskId, using: client)
    }

    func syncAppleHealth(
        using client: HealthAPIClient,
        settings: AppSettingsStore,
        preferredToken: String?
    ) async {
        isSyncingHealthKit = true
        defer { isSyncingHealthKit = false }

        do {
            let samples = try await healthKitService.fetchSyncSamples()
            let collectedCount = samples.count
            if samples.isEmpty == false {
                healthSyncState = healthSyncStateStore.mergePendingSamples(samples)
            } else {
                healthSyncState = healthSyncStateStore.loadState()
            }

            let queuedBeforeUpload = healthSyncState.pendingSampleCount
            guard queuedBeforeUpload > 0 else {
                latestPrivacyMessage = "Apple 健康当前没有可同步的新数据。"
                return
            }

            let upload = try await HealthKitOfflineSyncEngine.flushPendingSamples(
                targetURLs: settings.healthKitUploadTargetURLs(),
                preferredToken: preferredToken ?? client.token,
                pendingSamples: healthSyncState.pendingSamples
            )

            healthSyncState = healthSyncStateStore.markSyncSuccess(
                sentSampleIDs: upload.sentSampleIDs,
                result: upload.result,
                serverURL: upload.serverURL
            )
            latestHealthSyncResult = upload.result
            latestImportTask = upload.task
            if let task = upload.task {
                merge(task: task)
            }
            await refreshImportTasks(using: client)

            let pendingCount = healthSyncState.pendingSampleCount
            latestPrivacyMessage =
                pendingCount == 0
                    ? "Apple 健康已同步 \(upload.result.successRecords) 条记录；本次采集 \(collectedCount) 条，队列已清空。"
                    : "Apple 健康已同步 \(upload.result.successRecords) 条记录，仍有 \(pendingCount) 条待补传。"

            await LocalNotificationManager.notify(
                title: "Apple 健康同步完成",
                body: queuedBeforeUpload == collectedCount
                    ? "已写入 \(upload.result.successRecords) 条记录。"
                    : "已补传 \(upload.result.successRecords) 条记录。"
            )
        } catch {
            let message = healthKitErrorMessage(for: error)
            healthSyncState = healthSyncStateStore.markSyncFailure(message: message)
            latestPrivacyMessage =
                healthSyncState.pendingSampleCount > 0
                    ? "\(message) 当前仍有 \(healthSyncState.pendingSampleCount) 条待上传样本，会在下次联网时继续补传。"
                    : message
        }
    }

    func requestPrivacyExport(using client: HealthAPIClient) async {
        do {
            let response = try await client.requestPrivacyExport(PrivacyExportRequest())
            latestPrivacyMessage = "导出占位返回: \(response.nextStep)"
        } catch {
            latestPrivacyMessage = error.localizedDescription
        }
    }

    func requestPrivacyDelete(using client: HealthAPIClient) async {
        do {
            let response = try await client.requestPrivacyDelete(PrivacyDeleteRequest())
            latestPrivacyMessage = "删除占位返回: \(response.nextStep)"
        } catch {
            latestPrivacyMessage = error.localizedDescription
        }
    }

    func clearTransientImportFeedback() {
        importPhaseResetTask?.cancel()
        if case .failed = importPhase {
            importPhase = .idle
        }
    }

    private func startPolling(taskID: String, using client: HealthAPIClient) {
        importPollingTask?.cancel()
        pollingElapsed = 0
        importPollingTask = Task {
            var missingTaskRetries = 0
            while !Task.isCancelled {
                do {
                    let task = try await client.fetchImportTask(taskID: taskID).task
                    missingTaskRetries = 0

                    await MainActor.run {
                        self.latestImportTask = task
                        self.merge(task: task)
                    }

                    if task.isFinished {
                        await MainActor.run {
                            self.setImportPhase(
                                .completed(
                                    success: task.successRecords,
                                    total: max(task.totalRecords, task.successRecords)
                                ),
                                autoResetAfter: 3
                            )
                        }
                        await LocalNotificationManager.notify(
                            title: task.taskStatus == .completed ? "数据更新完成" : "数据任务已结束",
                            body: "\(task.title)：成功 \(task.successRecords) / \(task.totalRecords)"
                        )
                        break
                    } else {
                        await MainActor.run {
                            self.pollingElapsed += 2
                            self.setImportPhase(.serverProcessing(taskId: taskID, elapsed: self.pollingElapsed))
                        }
                    }
                } catch {
                    if case let HealthAPIClientError.server(statusCode, _) = error, statusCode == 404 {
                        missingTaskRetries += 1
                        await self.refreshImportTasks(using: client)

                        if missingTaskRetries <= 2 {
                            await MainActor.run {
                                self.pollingElapsed += 2
                                self.setImportPhase(.serverProcessing(taskId: taskID, elapsed: self.pollingElapsed))
                            }
                            try? await Task.sleep(for: .seconds(2))
                            continue
                        }

                        await MainActor.run {
                            self.setImportPhase(.failed(message: "上传已提交，但任务状态暂时不可见，请稍后在最近任务中刷新查看。"), autoResetAfter: 4)
                        }
                        break
                    }

                    let message = error.localizedDescription
                    await MainActor.run {
                        self.setImportPhase(.failed(message: message), autoResetAfter: 4)
                    }
                    break
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var pollingElapsed = 0

    private func setImportPhase(_ phase: ImportPhase, autoResetAfter seconds: Double? = nil) {
        importPhaseResetTask?.cancel()
        importPhase = phase

        guard let seconds else {
            return
        }

        importPhaseResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                self?.importPhase = .idle
            }
        }
    }

    private func merge(task: ImportTaskSummary) {
        var items = importTasks.filter { $0.importTaskId != task.importTaskId }
        items.insert(task, at: 0)
        importTasks = items.sorted { $0.startedAt > $1.startedAt }
    }

    private func importErrorMessage(for error: Error) -> String {
        if case let HealthAPIClientError.server(statusCode, _) = error, statusCode == 405 {
            return "当前服务没有开启数据上传接口，请先启动最新版 HealthAI 服务。"
        }

        return error.localizedDescription
    }

    private func healthKitErrorMessage(for error: Error) -> String {
        if case let HealthAPIClientError.server(statusCode, _) = error, statusCode == 405 {
            return "当前服务没有开启 Apple 健康同步接口，请先启动最新版 HealthAI 服务。"
        }

        return error.localizedDescription
    }

    private func sanitizeCacheScope(_ cacheScope: String) -> String {
        cacheScope.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }
}

struct HealthKitPendingUpload {
    let serverURL: String
    let result: HealthKitSyncResult
    let task: ImportTaskSummary?
    let sentSampleIDs: [String]
}

enum HealthKitOfflineSyncEngine {
    static func flushPendingSamples(
        targetURLs: [String],
        preferredToken: String?,
        pendingSamples: [HealthKitMetricSampleInput]
    ) async throws -> HealthKitPendingUpload {
        guard pendingSamples.isEmpty == false else {
            throw HealthAPIClientError.transport("当前没有待同步的 Apple 健康样本。")
        }

        guard targetURLs.isEmpty == false else {
            throw HealthAPIClientError.transport("未找到可用的同步服务器，请先在设置里保存可访问的服务地址。")
        }

        var lastError: Error?

        for targetURL in targetURLs {
            do {
                let client = try makeClient(urlString: targetURL, token: preferredToken)
                let response = try await sync(pendingSamples: pendingSamples, using: client)
                let task = try? await client.fetchImportTask(taskID: response.result.importTaskId).task
                _ = try? await client.triggerSync()
                _ = try? await client.triggerPlanCheck()

                return HealthKitPendingUpload(
                    serverURL: targetURL,
                    result: response.result,
                    task: task,
                    sentSampleIDs: pendingSamples.map(\.id)
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? HealthAPIClientError.transport("没有可用的同步服务器。")
    }

    private static func makeClient(urlString: String, token: String?) throws -> HealthAPIClient {
        guard let baseURL = URL(string: urlString), baseURL.scheme?.hasPrefix("http") == true else {
            throw HealthAPIClientError.transport("无效的同步服务地址：\(urlString)")
        }

        return HealthAPIClient(
            configuration: AppServerConfiguration(baseURL: baseURL),
            token: token
        )
    }

    private static func sync(
        pendingSamples: [HealthKitMetricSampleInput],
        using client: HealthAPIClient
    ) async throws -> HealthKitSyncEnvelope {
        do {
            return try await client.syncHealthKit(HealthKitSyncRequest(samples: pendingSamples))
        } catch let error as HealthAPIClientError {
            guard case let .server(statusCode, _) = error, statusCode == 401 else {
                throw error
            }

            let relogin = try await client.deviceLogin(
                DeviceLoginRequest(
                    deviceId: AuthManager.persistedDeviceId(),
                    deviceLabel: UIDevice.current.name
                )
            )
            client.token = relogin.token
            return try await client.syncHealthKit(HealthKitSyncRequest(samples: pendingSamples))
        }
    }
}
