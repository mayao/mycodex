import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class TrendsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<HealthHomePageData> = .idle

    func setError(_ message: String) {
        state = .failed(message)
    }

    func load(using client: HealthAPIClient) async {
        if case .loading = state {
            return
        }

        state = .loading

        do {
            state = .loaded(try await client.fetchDashboard())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
