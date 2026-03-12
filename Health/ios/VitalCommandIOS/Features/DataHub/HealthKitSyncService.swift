import Foundation
import HealthKit
import VitalCommandMobileCore

enum HealthKitSyncServiceError: LocalizedError {
    case unavailable
    case missingType

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "当前设备不支持 Apple 健康。"
        case .missingType:
            "Apple 健康数据类型不可用。"
        }
    }
}

final class HealthKitSyncService: @unchecked Sendable {
    private let store = HKHealthStore()
    private let calendar = Calendar.current
    private let isoFormatter = ISO8601DateFormatter()
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitSyncServiceError.unavailable
        }

        let readTypes = Set<HKObjectType>([
            quantityType(.bodyMass),
            quantityType(.bodyFatPercentage),
            quantityType(.bodyMassIndex),
            quantityType(.stepCount),
            quantityType(.distanceWalkingRunning),
            quantityType(.activeEnergyBurned),
            quantityType(.appleExerciseTime),
            categoryType(.sleepAnalysis)
        ])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitSyncServiceError.unavailable)
                }
            }
        }
    }

    func fetchSyncSamples(daysBack: Int = 90) async throws -> [HealthKitMetricSampleInput] {
        try await requestAuthorization()

        async let weight = quantitySamples(
            identifier: .bodyMass,
            kind: .weight,
            unit: .gramUnit(with: .kilo),
            daysBack: daysBack,
            transform: { $0 }
        )
        async let bodyFat = quantitySamples(
            identifier: .bodyFatPercentage,
            kind: .bodyFat,
            unit: .percent(),
            daysBack: daysBack,
            transform: { $0 * 100 }
        )
        async let bmi = quantitySamples(
            identifier: .bodyMassIndex,
            kind: .bmi,
            unit: .count(),
            daysBack: daysBack,
            transform: { $0 }
        )
        async let steps = cumulativeDailySamples(
            identifier: .stepCount,
            kind: .steps,
            unit: .count(),
            daysBack: daysBack
        )
        async let distance = cumulativeDailySamples(
            identifier: .distanceWalkingRunning,
            kind: .distanceWalkingRunning,
            unit: .meterUnit(with: .kilo),
            daysBack: daysBack
        )
        async let activeEnergy = cumulativeDailySamples(
            identifier: .activeEnergyBurned,
            kind: .activeEnergy,
            unit: .kilocalorie(),
            daysBack: daysBack
        )
        async let exercise = cumulativeDailySamples(
            identifier: .appleExerciseTime,
            kind: .exerciseMinutes,
            unit: .minute(),
            daysBack: daysBack
        )
        async let sleep = sleepSamples(daysBack: daysBack)

        return try await (
            weight +
            bodyFat +
            bmi +
            steps +
            distance +
            activeEnergy +
            exercise +
            sleep
        ).sorted { $0.sampleTime < $1.sampleTime }
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            fatalError("Missing HealthKit quantity type \(identifier.rawValue)")
        }
        return type
    }

    private func categoryType(_ identifier: HKCategoryTypeIdentifier) -> HKCategoryType {
        guard let type = HKObjectType.categoryType(forIdentifier: identifier) else {
            fatalError("Missing HealthKit category type \(identifier.rawValue)")
        }
        return type
    }

    private func quantitySamples(
        identifier: HKQuantityTypeIdentifier,
        kind: HealthKitMetricKind,
        unit: HKUnit,
        daysBack: Int,
        transform: @escaping (Double) -> Double
    ) async throws -> [HealthKitMetricSampleInput] {
        let type = quantityType(identifier)
        let startDate = calendar.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }

            store.execute(query)
        }

        return samples.map { sample in
            HealthKitMetricSampleInput(
                kind: kind,
                value: transform(sample.quantity.doubleValue(for: unit)),
                unit: displayUnit(for: kind),
                sampleTime: isoFormatter.string(from: sample.endDate),
                sourceLabel: sample.sourceRevision.source.name
            )
        }
    }

    private func cumulativeDailySamples(
        identifier: HKQuantityTypeIdentifier,
        kind: HealthKitMetricKind,
        unit: HKUnit,
        daysBack: Int
    ) async throws -> [HealthKitMetricSampleInput] {
        let type = quantityType(identifier)
        let startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date())
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let interval = DateComponents(day: 1)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HealthKitMetricSampleInput], Error>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results else {
                    continuation.resume(returning: [])
                    return
                }

                var items: [HealthKitMetricSampleInput] = []
                results.enumerateStatistics(from: startDate, to: Date()) { [self] stats, _ in
                    guard let quantity = stats.sumQuantity() else {
                        return
                    }

                    let value = quantity.doubleValue(for: unit)
                    guard value > 0 else {
                        return
                    }

                    items.append(
                        HealthKitMetricSampleInput(
                            kind: kind,
                            value: value,
                            unit: self.displayUnit(for: kind),
                            sampleTime: self.dayFormatter.string(from: stats.startDate)
                        )
                    )
                }

                continuation.resume(returning: items)
            }

            store.execute(query)
        }
    }

    private func sleepSamples(daysBack: Int) async throws -> [HealthKitMetricSampleInput] {
        let type = categoryType(.sleepAnalysis)
        let startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date())
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }

            store.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]
        var minutesByDay: [String: Double] = [:]

        for sample in samples where asleepValues.contains(sample.value) {
            let day = dayFormatter.string(from: sample.endDate)
            minutesByDay[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60
        }

        return minutesByDay
            .sorted { $0.key < $1.key }
            .map { day, minutes in
                HealthKitMetricSampleInput(
                    kind: .sleepMinutes,
                    value: minutes,
                    unit: displayUnit(for: .sleepMinutes),
                    sampleTime: day
                )
            }
    }

    private func displayUnit(for kind: HealthKitMetricKind) -> String {
        switch kind {
        case .weight:
            "kg"
        case .bodyFat:
            "%"
        case .bmi:
            "kg/m2"
        case .steps:
            "count"
        case .distanceWalkingRunning:
            "km"
        case .activeEnergy:
            "kcal"
        case .exerciseMinutes, .sleepMinutes:
            "min"
        }
    }
}
