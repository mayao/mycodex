import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<ReportsIndexData> = .idle
    @Published var selectedKind: ReportKind = .weekly
    @Published private(set) var planProgress: PlanProgressReport?
    @Published private(set) var isLoadingPlanProgress = false
    @Published private(set) var isUsingCache = false
    @Published private(set) var cacheDate: Date?

    private let fileStore = MobileFileStore(namespace: "HealthAI")

    func setError(_ message: String) {
        state = .failed(message)
    }

    func load(using client: HealthAPIClient, cacheScope: String) async {
        if case .loading = state {
            return
        }

        let cacheFileName = "reports-index-\(sanitizeCacheScope(cacheScope)).json"
        if case .idle = state, let cached = fileStore.load(CachedPayload<ReportsIndexData>.self, fileName: cacheFileName) {
            state = .loaded(cached.value)
            isUsingCache = true
            cacheDate = cached.cachedAt
        }

        if state.value == nil {
            state = .loading
        }

        do {
            let reports = try await client.fetchReports()
            state = .loaded(reports)
            isUsingCache = false
            cacheDate = nil
            _ = fileStore.save(CachedPayload(value: reports), fileName: cacheFileName)
        } catch {
            if let cached = fileStore.load(CachedPayload<ReportsIndexData>.self, fileName: cacheFileName) {
                state = .loaded(cached.value)
                isUsingCache = true
                cacheDate = cached.cachedAt
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func loadPlanProgress(using client: HealthAPIClient, cacheScope: String) async {
        guard !isLoadingPlanProgress else { return }
        isLoadingPlanProgress = true
        defer { isLoadingPlanProgress = false }

        let cacheFileName = "plan-progress-\(sanitizeCacheScope(cacheScope)).json"

        if planProgress == nil,
           let cached = fileStore.load(CachedPayload<PlanProgressReport>.self, fileName: cacheFileName) {
            planProgress = cached.value
        }

        do {
            let progress = try await client.fetchPlanProgress()
            planProgress = progress
            _ = fileStore.save(CachedPayload(value: progress), fileName: cacheFileName)
        } catch {
            if let cached = fileStore.load(CachedPayload<PlanProgressReport>.self, fileName: cacheFileName) {
                planProgress = cached.value
            }
        }
    }

    var visibleReports: [HealthReportSnapshotRecord] {
        guard case let .loaded(payload) = state else {
            return []
        }

        switch selectedKind {
        case .weekly:
            return payload.weeklyReports
        case .monthly:
            return payload.monthlyReports
        }
    }

    private func sanitizeCacheScope(_ cacheScope: String) -> String {
        cacheScope.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }
}
