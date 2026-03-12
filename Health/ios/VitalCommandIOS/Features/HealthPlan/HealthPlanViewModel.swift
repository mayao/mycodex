import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class HealthPlanViewModel: ObservableObject {
    @Published private(set) var state: LoadState<HealthPlanDashboard> = .idle
    @Published private(set) var isGenerating = false
    @Published private(set) var operationError: String?

    var dashboard: HealthPlanDashboard? { state.value }

    func load(using client: HealthAPIClient) async {
        if case .loading = state { return }
        state = .loading

        do {
            state = .loaded(try await client.fetchHealthPlan())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func generateSuggestions(using client: HealthAPIClient) async {
        guard !isGenerating else { return }
        isGenerating = true
        operationError = nil

        do {
            _ = try await client.generateSuggestions()
            // Reload dashboard to show new suggestions
            state = .loaded(try await client.fetchHealthPlan())
        } catch {
            operationError = error.localizedDescription
        }

        isGenerating = false
    }

    @discardableResult
    func acceptSuggestion(_ request: AcceptSuggestionRequest, using client: HealthAPIClient) async -> HealthPlanItem? {
        operationError = nil
        do {
            let response = try await client.acceptSuggestion(request)
            // Reload
            state = .loaded(try await client.fetchHealthPlan())
            return response.planItem
        } catch {
            operationError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func updatePlanItem(_ request: UpdatePlanItemRequest, using client: HealthAPIClient) async -> HealthPlanItem? {
        operationError = nil
        do {
            let response = try await client.updatePlanItem(request)
            state = .loaded(try await client.fetchHealthPlan())
            return response.planItem
        } catch {
            operationError = error.localizedDescription
            return nil
        }
    }

    func checkIn(planItem: HealthPlanItem, using client: HealthAPIClient) async {
        operationError = nil
        do {
            _ = try await client.manualCheckIn(ManualCheckInRequest(planItemId: planItem.id))
            state = .loaded(try await client.fetchHealthPlan())
        } catch {
            operationError = error.localizedDescription
        }
    }

    func updateStatus(planItem: HealthPlanItem, status: PlanItemStatus, using client: HealthAPIClient) async {
        operationError = nil
        do {
            _ = try await client.updatePlanStatus(UpdatePlanStatusRequest(planItemId: planItem.id, status: status))
            state = .loaded(try await client.fetchHealthPlan())
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
}
