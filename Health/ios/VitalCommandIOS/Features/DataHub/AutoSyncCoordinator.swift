import Foundation
import VitalCommandMobileCore

/// Automatically syncs HealthKit data when the app enters foreground.
/// Throttled to run at most once every 15 minutes. Failures are silent.
@MainActor
final class AutoSyncCoordinator: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?

    private static let lastSyncKey = "vital-command.last-healthkit-sync"
    private static let throttleInterval: TimeInterval = 15 * 60 // 15 minutes
    private let syncStateStore = HealthKitSyncStateStore()

    init() {
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    func syncIfNeeded(settings: AppSettingsStore) {
        guard !isSyncing else { return }

        // Throttle check
        if let last = lastSyncDate, Date().timeIntervalSince(last) < Self.throttleInterval {
            return
        }

        isSyncing = true
        Task {
            await performSync(settings: settings)
        }
    }

    private func performSync(settings: AppSettingsStore) async {
        defer { isSyncing = false }

        do {
            let service = HealthKitSyncService()
            let samples = try await service.fetchSyncSamples(daysBack: 7)
            let state =
                samples.isEmpty
                    ? syncStateStore.loadState()
                    : syncStateStore.mergePendingSamples(samples)

            guard state.pendingSampleCount > 0 else { return }

            let upload = try await HealthKitOfflineSyncEngine.flushPendingSamples(
                targetURLs: settings.healthKitUploadTargetURLs(),
                preferredToken: settings.authToken,
                pendingSamples: state.pendingSamples
            )
            _ = syncStateStore.markSyncSuccess(
                sentSampleIDs: upload.sentSampleIDs,
                result: upload.result,
                serverURL: upload.serverURL
            )

            // Update throttle timestamp
            let now = Date()
            lastSyncDate = now
            UserDefaults.standard.set(now, forKey: Self.lastSyncKey)

            // Trigger dashboard refresh
            settings.markHealthDataChanged()

            print("[AutoSync] Synced \(upload.result.successRecords) records from HealthKit")
        } catch {
            _ = syncStateStore.markSyncFailure(message: error.localizedDescription)
            // Silent failure — don't bother the user
            print("[AutoSync] Failed: \(error.localizedDescription)")
        }
    }
}
