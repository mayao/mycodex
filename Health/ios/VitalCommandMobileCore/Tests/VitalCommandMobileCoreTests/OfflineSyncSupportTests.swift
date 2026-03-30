import Foundation
import Testing
@testable import VitalCommandMobileCore

struct OfflineSyncSupportTests {
    @Test
    func fileStorePersistsCachedPayloads() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MobileFileStore(baseDirectory: directory)
        let payload = CachedPayload(value: ["headline": "缓存命中"], cachedAt: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(store.save(payload, fileName: "dashboard.json"))

        let loaded = store.load(CachedPayload<[String: String]>.self, fileName: "dashboard.json")
        #expect(loaded?.value["headline"] == "缓存命中")
        #expect(loaded?.cachedAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test
    func syncQueueDedupesAndPersistsPendingSamples() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let queue = HealthKitSyncStateStore(
            fileStore: MobileFileStore(baseDirectory: directory),
            fileName: "queue.json"
        )
        let first = HealthKitMetricSampleInput(
            kind: .weight,
            value: 70.1,
            unit: "kg",
            sampleTime: "2026-03-30T08:00:00Z",
            sourceLabel: "Apple Health"
        )
        let second = HealthKitMetricSampleInput(
            kind: .weight,
            value: 70.4,
            unit: "kg",
            sampleTime: "2026-03-30T08:00:00Z",
            sourceLabel: "Apple Health"
        )
        let third = HealthKitMetricSampleInput(
            kind: .steps,
            value: 8500,
            unit: "count",
            sampleTime: "2026-03-30T20:00:00Z",
            sourceLabel: "Apple Health"
        )

        let merged = queue.mergePendingSamples([first, second, third], collectedAt: Date(timeIntervalSince1970: 1_700_000_100))

        #expect(merged.pendingSampleCount == 2)
        #expect(merged.pendingSamples.first(where: { $0.id == first.id })?.value == 70.4)
        #expect(merged.lastCollectedAt == Date(timeIntervalSince1970: 1_700_000_100))

        let persisted = queue.loadState()
        #expect(persisted.pendingSampleCount == 2)
    }

    @Test
    func syncQueueMarksSuccessAndRemovesUploadedSamples() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let queue = HealthKitSyncStateStore(
            fileStore: MobileFileStore(baseDirectory: directory),
            fileName: "queue.json"
        )
        let weight = HealthKitMetricSampleInput(
            kind: .weight,
            value: 70.4,
            unit: "kg",
            sampleTime: "2026-03-30T08:00:00Z"
        )
        let steps = HealthKitMetricSampleInput(
            kind: .steps,
            value: 8500,
            unit: "count",
            sampleTime: "2026-03-30T20:00:00Z"
        )
        _ = queue.mergePendingSamples([weight, steps])

        let state = queue.markSyncSuccess(
            sentSampleIDs: [weight.id],
            result: HealthKitSyncResult(
                importTaskId: "task-1",
                taskStatus: .completed,
                totalRecords: 1,
                successRecords: 1,
                failedRecords: 0,
                syncedKinds: [.weight],
                latestSampleTime: weight.sampleTime
            ),
            serverURL: "http://192.168.1.8:3000",
            syncedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )

        #expect(state.pendingSampleCount == 1)
        #expect(state.pendingSamples.first?.id == steps.id)
        #expect(state.lastSuccessfulServerURL == "http://192.168.1.8:3000")
        #expect(state.lastResult?.importTaskId == "task-1")
    }

    @Test
    func resolverPrioritizesLanTargetsBeforeCurrentAndSaved() {
        let ordered = HealthKitUploadTargetResolver.prioritizeTargets(
            discoveredServerURLs: ["http://192.168.1.8:3000/", "http://10.0.0.4:3000"],
            currentServerURL: "http://health.example.com:3000/",
            savedServerURLs: [
                "http://10.0.0.4:3000",
                "http://172.16.1.9:3000",
                "http://backup.example.com:3000/"
            ]
        )

        #expect(ordered == [
            "http://192.168.1.8:3000",
            "http://10.0.0.4:3000",
            "http://health.example.com:3000",
            "http://172.16.1.9:3000",
            "http://backup.example.com:3000"
        ])
    }
}
