import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<ReportsIndexData> = .idle
    @Published var selectedKind: ReportKind = .weekly

    func setError(_ message: String) {
        state = .failed(message)
    }

    func load(using client: HealthAPIClient) async {
        if case .loading = state {
            return
        }

        state = .loading

        do {
            state = .loaded(try await client.fetchReports())
        } catch {
            state = .failed(error.localizedDescription)
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
}
