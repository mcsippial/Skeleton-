import Foundation
import HealthKit
import SkeletonCore

/// Daily health metrics. Apple Health directly via HealthKit; wearables (Oura, WHOOP, Garmin,
/// Fitbit) come later through Terra or Junction behind the same protocol.
protocol HealthService: Sendable {
    var sourceName: String { get }
    var isAvailable: Bool { get }
    func requestAccess() async throws
    func dailyMetrics(from start: Date, to end: Date) async throws -> [DailyMetric]
}

/// Demo data shaped around the pain history (short sleep and low HRV before flares).
struct MockHealthService: HealthService {
    let entries: @Sendable () async -> [PainEntry]
    var sourceName: String { "Demo health data" }
    var isAvailable: Bool { true }
    func requestAccess() async throws {}
    func dailyMetrics(from start: Date, to end: Date) async throws -> [DailyMetric] {
        DemoHealth.metrics(now: end, entries: await entries()).filter { $0.day >= start }
    }
}

/// Apple Health. Read-only: Skeleton never writes to Health.
final class HealthKitService: HealthService, @unchecked Sendable {
    private let store = HKHealthStore()
    var sourceName: String { "Apple Health" }
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var quantityTypes: [(HKQuantityType, HealthMetricKind, HKUnit, HKStatisticsOptions)] {
        [
            (HKQuantityType(.heartRateVariabilitySDNN), .hrv, .secondUnit(with: .milli), .discreteAverage),
            (HKQuantityType(.restingHeartRate), .restingHeartRate, .count().unitDivided(by: .minute()), .discreteAverage),
            (HKQuantityType(.stepCount), .steps, .count(), .cumulativeSum),
            (HKQuantityType(.bodyMass), .weightKg, .gramUnit(with: .kilo), .discreteAverage),
        ]
    }

    enum HealthAccessError: LocalizedError {
        case notEntitled
        var errorDescription: String? {
            "This build of Skeleton isn't allowed to use Apple Health yet. Rebuild after regenerating the project (xcodegen generate) so the HealthKit permission is included."
        }
    }

    func requestAccess() async throws {
        var read: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
        for (type, _, _, _) in quantityTypes { read.insert(type) }
        do {
            try await store.requestAuthorization(toShare: [], read: read)
        } catch let error as NSError where error.domain == HKErrorDomain && error.localizedDescription.localizedCaseInsensitiveContains("entitlement") {
            throw HealthAccessError.notEntitled
        }
    }

    func dailyMetrics(from start: Date, to end: Date) async throws -> [DailyMetric] {
        let cal = Calendar.current
        let from = cal.startOfDay(for: start)
        let range = HKQuery.predicateForSamples(withStart: from, end: end)
        var out: [DailyMetric] = []

        for (type, kind, unit, options) in quantityTypes {
            let descriptor = HKStatisticsCollectionQueryDescriptor(
                predicate: HKSamplePredicate.quantitySample(type: type, predicate: range),
                options: options, anchorDate: from, intervalComponents: DateComponents(day: 1))
            let collection = try await descriptor.result(for: store)
            for stats in collection.statistics() {
                let q = options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
                if let q { out.append(DailyMetric(kind: kind, day: cal.startOfDay(for: stats.startDate), value: q.doubleValue(for: unit))) }
            }
        }

        // Sleep: asleep time, credited to the day the night ends.
        let sleep = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: range)], sortDescriptors: [])
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        var sleepByDay: [Date: Double] = [:]
        for s in try await sleep.result(for: store) where asleep.contains(s.value) {
            sleepByDay[cal.startOfDay(for: s.endDate), default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
        }
        out += sleepByDay.map { DailyMetric(kind: .sleepHours, day: $0.key, value: $0.value) }

        let workouts = HKSampleQueryDescriptor(predicates: [.workout(range)], sortDescriptors: [])
        var minutesByDay: [Date: Double] = [:]
        for w in try await workouts.result(for: store) {
            minutesByDay[cal.startOfDay(for: w.startDate), default: 0] += w.duration / 60
        }
        out += minutesByDay.map { DailyMetric(kind: .workoutMinutes, day: $0.key, value: $0.value) }
        return out
    }
}
