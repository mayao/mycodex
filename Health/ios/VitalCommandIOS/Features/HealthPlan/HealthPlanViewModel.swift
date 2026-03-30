import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class HealthPlanViewModel: ObservableObject {
    @Published private(set) var state: LoadState<HealthPlanDashboard> = .idle
    @Published private(set) var isGenerating = false
    @Published private(set) var operationError: String?
    @Published private(set) var isUsingCache = false
    @Published private(set) var cacheDate: Date?

    var dashboard: HealthPlanDashboard? { state.value }
    private let fileStore = MobileFileStore(namespace: "HealthAI")
    private var lastCacheScope: String?

    func load(using client: HealthAPIClient, cacheScope: String) async {
        if case .loading = state { return }

        let cacheFileName = "health-plan-\(sanitizeCacheScope(cacheScope)).json"
        lastCacheScope = cacheScope
        if case .idle = state,
           let cached = fileStore.load(CachedPayload<HealthPlanDashboard>.self, fileName: cacheFileName) {
            state = .loaded(cached.value)
            isUsingCache = true
            cacheDate = cached.cachedAt
        } else if case .idle = state {
            state = .loading
        }

        do {
            let dashboard = try await client.fetchHealthPlan()
            state = .loaded(dashboard)
            isUsingCache = false
            cacheDate = nil
            saveDashboardCache(dashboard, cacheScope: cacheScope)
        } catch {
            if let cached = fileStore.load(CachedPayload<HealthPlanDashboard>.self, fileName: cacheFileName) {
                state = .loaded(cached.value)
                isUsingCache = true
                cacheDate = cached.cachedAt
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func generateSuggestions(using client: HealthAPIClient) async {
        guard !isGenerating else { return }
        guard !isUsingCache else {
            operationError = "当前处于离线缓存模式，计划页暂时只读；恢复联网后再生成建议。"
            return
        }
        isGenerating = true
        operationError = nil

        do {
            _ = try await client.generateSuggestions()
            // Reload dashboard to show new suggestions
            let dashboard = try await client.fetchHealthPlan()
            state = .loaded(dashboard)
            isUsingCache = false
            cacheDate = nil
            saveDashboardCache(dashboard)
        } catch {
            operationError = error.localizedDescription
        }

        isGenerating = false
    }

    @discardableResult
    func acceptSuggestion(_ request: AcceptSuggestionRequest, using client: HealthAPIClient) async -> HealthPlanItem? {
        guard !isUsingCache else {
            operationError = "当前处于离线缓存模式，计划页暂时只读；恢复联网后再接受建议。"
            return nil
        }
        operationError = nil
        do {
            let response = try await client.acceptSuggestion(request)
            // Reload
            let dashboard = try await client.fetchHealthPlan()
            state = .loaded(dashboard)
            isUsingCache = false
            cacheDate = nil
            saveDashboardCache(dashboard)
            return response.planItem
        } catch {
            operationError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func updatePlanItem(_ request: UpdatePlanItemRequest, using client: HealthAPIClient) async -> HealthPlanItem? {
        guard !isUsingCache else {
            operationError = "当前处于离线缓存模式，计划页暂时只读；恢复联网后再编辑计划。"
            return nil
        }
        operationError = nil
        do {
            let response = try await client.updatePlanItem(request)
            let dashboard = try await client.fetchHealthPlan()
            state = .loaded(dashboard)
            isUsingCache = false
            cacheDate = nil
            saveDashboardCache(dashboard)
            return response.planItem
        } catch {
            operationError = error.localizedDescription
            return nil
        }
    }

    func checkIn(planItem: HealthPlanItem, using client: HealthAPIClient) async {
        guard !isUsingCache else {
            operationError = "当前处于离线缓存模式，计划页暂时只读；恢复联网后再打卡。"
            return
        }
        operationError = nil
        do {
            _ = try await client.manualCheckIn(ManualCheckInRequest(planItemId: planItem.id))
            let dashboard = try await client.fetchHealthPlan()
            state = .loaded(dashboard)
            isUsingCache = false
            cacheDate = nil
            saveDashboardCache(dashboard)
        } catch {
            operationError = error.localizedDescription
        }
    }

    func updateStatus(planItem: HealthPlanItem, status: PlanItemStatus, using client: HealthAPIClient) async {
        guard !isUsingCache else {
            operationError = "当前处于离线缓存模式，计划页暂时只读；恢复联网后再修改状态。"
            return
        }
        operationError = nil
        do {
            _ = try await client.updatePlanStatus(UpdatePlanStatusRequest(planItemId: planItem.id, status: status))
            let dashboard = try await client.fetchHealthPlan()
            state = .loaded(dashboard)
            isUsingCache = false
            cacheDate = nil
            saveDashboardCache(dashboard)
        } catch {
            operationError = error.localizedDescription
        }
    }

    func setError(_ message: String) {
        state = .failed(message)
    }

    func clearOperationError() {
        operationError = nil
    }

    private func sanitizeCacheScope(_ cacheScope: String) -> String {
        cacheScope.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }

    private func saveDashboardCache(_ dashboard: HealthPlanDashboard, cacheScope: String? = nil) {
        let effectiveScope = cacheScope ?? lastCacheScope
        guard let effectiveScope else { return }
        _ = fileStore.save(
            CachedPayload(value: dashboard),
            fileName: "health-plan-\(sanitizeCacheScope(effectiveScope)).json"
        )
    }
}
