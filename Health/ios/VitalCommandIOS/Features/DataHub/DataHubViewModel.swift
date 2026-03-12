import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class DataHubViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[HealthImportOption]> = .idle
    @Published var selectedImporter: ImporterKey = .annualExam
    @Published private(set) var importTasks: [ImportTaskSummary] = []
    @Published private(set) var latestImportTask: ImportTaskSummary?
    @Published private(set) var latestHealthSyncResult: HealthKitSyncResult?
    @Published private(set) var latestPrivacyMessage: String?
    @Published private(set) var isSubmittingImport = false
    @Published private(set) var isSyncingHealthKit = false

    private let healthKitService = HealthKitSyncService()
    private var importPollingTask: Task<Void, Never>?

    deinit {
        importPollingTask?.cancel()
    }

    func setError(_ message: String) {
        state = .failed(message)
    }

    func setPrivacyMessage(_ message: String) {
        latestPrivacyMessage = message
    }

    func load(using client: HealthAPIClient) async {
        if case .loading = state {
            return
        }

        state = .loading

        do {
            async let dashboard = client.fetchDashboard()
            async let taskResponse = client.fetchImportTasks()

            let (dashboardPayload, taskPayload) = try await (dashboard, taskResponse)
            state = .loaded(dashboardPayload.importOptions)
            importTasks = taskPayload.tasks

            if let runningTask = taskPayload.tasks.first(where: { !$0.isFinished }) {
                startPolling(taskID: runningTask.importTaskId, using: client)
            }
        } catch {
            state = .failed(error.localizedDescription)
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
        isSubmittingImport = true
        defer { isSubmittingImport = false }

        do {
            let response = try await client.importData(
                importerKey: selectedImporter,
                fileName: fileName,
                mimeType: mimeType,
                fileData: fileData,
                extractedText: extractedText
            )
            latestImportTask = response.task
            merge(task: response.task)
            latestPrivacyMessage = "任务已进入后台处理，可离开当前页面继续使用。"
            await refreshImportTasks(using: client)
            startPolling(taskID: response.task.importTaskId, using: client)
        } catch {
            latestPrivacyMessage = importErrorMessage(for: error)
        }
    }

    func syncAppleHealth(using client: HealthAPIClient) async {
        isSyncingHealthKit = true
        defer { isSyncingHealthKit = false }

        do {
            let samples = try await healthKitService.fetchSyncSamples()

            guard samples.isEmpty == false else {
                latestPrivacyMessage = "Apple 健康当前没有可同步的新数据。"
                return
            }

            let response = try await client.syncHealthKit(HealthKitSyncRequest(samples: samples))
            latestHealthSyncResult = response.result
            latestPrivacyMessage = "Apple 健康已同步 \(response.result.successRecords) 条记录。"

            if let task = try? await client.fetchImportTask(taskID: response.result.importTaskId).task {
                merge(task: task)
            }
            await refreshImportTasks(using: client)

            await LocalNotificationManager.notify(
                title: "Apple 健康同步完成",
                body: "已写入 \(response.result.successRecords) 条记录。"
            )
        } catch {
            latestPrivacyMessage = healthKitErrorMessage(for: error)
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

    private func startPolling(taskID: String, using client: HealthAPIClient) {
        importPollingTask?.cancel()
        importPollingTask = Task {
            while !Task.isCancelled {
                do {
                    let task = try await client.fetchImportTask(taskID: taskID).task

                    await MainActor.run {
                        self.latestImportTask = task
                        self.merge(task: task)
                    }

                    if task.isFinished {
                        await LocalNotificationManager.notify(
                            title: task.taskStatus == .completed ? "数据更新完成" : "数据任务已结束",
                            body: "\(task.title)：成功 \(task.successRecords) / \(task.totalRecords)"
                        )
                        break
                    }
                } catch {
                    await MainActor.run {
                        self.latestPrivacyMessage = error.localizedDescription
                    }
                    break
                }

                try? await Task.sleep(for: .seconds(2))
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
}
