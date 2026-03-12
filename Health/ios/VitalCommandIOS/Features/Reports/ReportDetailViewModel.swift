import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class ReportDetailViewModel: ObservableObject {
    @Published private(set) var state: LoadState<HealthReportSnapshotRecord> = .idle

    func setError(_ message: String) {
        state = .failed(message)
    }

    func load(reportID: String, using client: HealthAPIClient) async {
        if case .loading = state {
            return
        }

        state = .loading

        do {
            state = .loaded(try await client.fetchReportDetail(snapshotId: reportID))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
