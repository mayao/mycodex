import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class ReportDetailViewModel: ObservableObject {
    @Published private(set) var state: LoadState<HealthReportSnapshotRecord> = .idle
    @Published private(set) var isUsingCache = false
    @Published private(set) var cacheDate: Date?

    private let fileStore = MobileFileStore(namespace: "HealthAI")

    func setError(_ message: String) {
        state = .failed(message)
    }

    func load(reportID: String, using client: HealthAPIClient, cacheScope: String) async {
        if case .loading = state {
            return
        }

        let cacheFileName = "report-detail-\(sanitizeCacheScope(cacheScope))-\(sanitizeCacheScope(reportID)).json"
        if case .idle = state,
           let cached = fileStore.load(CachedPayload<HealthReportSnapshotRecord>.self, fileName: cacheFileName) {
            state = .loaded(cached.value)
            isUsingCache = true
            cacheDate = cached.cachedAt
        } else if case .idle = state {
            state = .loading
        }

        do {
            let report = try await client.fetchReportDetail(snapshotId: reportID)
            state = .loaded(report)
            isUsingCache = false
            cacheDate = nil
            _ = fileStore.save(CachedPayload(value: report), fileName: cacheFileName)
        } catch {
            if let cached = fileStore.load(CachedPayload<HealthReportSnapshotRecord>.self, fileName: cacheFileName) {
                state = .loaded(cached.value)
                isUsingCache = true
                cacheDate = cached.cachedAt
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func sanitizeCacheScope(_ cacheScope: String) -> String {
        cacheScope.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }
}
