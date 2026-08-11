import Foundation
import HealthKit

enum HealthKitError: Error {
    case notAvailable
}

struct DailySleep {
    let totalMinutes: Int
    let inBedMinutes: Int
}

final class HealthKitManager {
    private let store = HKHealthStore()

    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.notAvailable }
        try await store.requestAuthorization(toShare: [], read: [stepType, sleepType])
    }

    func fetchDailySteps(daysBack: Int) async throws -> [Date: Int] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: Date()))!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: stepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)

        var totals: [Date: Int] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            totals[day, default: 0] += Int(sample.quantity.doubleValue(for: .count()))
        }
        return totals
    }

    func fetchDailySleep(daysBack: Int) async throws -> [Date: DailySleep] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: Date()))!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate)]
        )
        let samples = try await descriptor.result(for: store)

        var totals: [Date: (asleep: Int, inBed: Int)] = [:]
        for sample in samples {
            // Attribute to the date the sample ends on (the wake-up date), so
            // a night's sleep that spans midnight counts as one consistent
            // day rather than splitting across two.
            let wakeDay = calendar.startOfDay(for: sample.endDate)
            let minutes = Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)

            var entry = totals[wakeDay] ?? (asleep: 0, inBed: 0)
            if let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                switch value {
                case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                    entry.asleep += minutes
                    entry.inBed += minutes
                case .inBed:
                    entry.inBed += minutes
                case .awake:
                    break
                @unknown default:
                    break
                }
            }
            totals[wakeDay] = entry
        }
        return totals.mapValues { DailySleep(totalMinutes: $0.asleep, inBedMinutes: $0.inBed) }
    }
}
