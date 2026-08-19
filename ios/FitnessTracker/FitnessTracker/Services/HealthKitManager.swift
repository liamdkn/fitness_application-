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

    func fetchDailySteps(daysBack: Int, source: StepSource) async throws -> [Date: Int] {
        switch source {
        case .merged:
            return try await fetchMergedDailySteps(daysBack: daysBack)
        case .appleWatch:
            return try await fetchAppleWatchDailySteps(daysBack: daysBack)
        }
    }

    // Matches the Health app's own displayed total: HKStatisticsCollectionQuery
    // with .cumulativeSum resolves overlapping same-time-window samples from
    // multiple sources (iPhone + Watch both log steps independently), unlike
    // a raw sum of every sample which double-counts them.
    private func fetchMergedDailySteps(daysBack: Int) async throws -> [Date: Int] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: Date()))!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let anchorDate = calendar.startOfDay(for: startDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: anchorDate,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)

        var totals: [Date: Int] = [:]
        collection.enumerateStatistics(from: startDate, to: Date()) { statistics, _ in
            guard let sum = statistics.sumQuantity() else { return }
            totals[statistics.startDate] = Int(sum.doubleValue(for: .count()))
        }
        return totals
    }

    // HKSource represents the writing app (both iPhone- and Watch-native step
    // data are written by the same "Health" source), so source separation
    // doesn't isolate the Watch - HKDevice (per-sample) does. Summing raw
    // samples is safe here since a single device's own data stream doesn't
    // overlap itself the way cross-source samples do.
    private func fetchAppleWatchDailySteps(daysBack: Int) async throws -> [Date: Int] {
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
            guard let device = sample.device, isAppleWatch(device) else { continue }
            let day = calendar.startOfDay(for: sample.startDate)
            totals[day, default: 0] += Int(sample.quantity.doubleValue(for: .count()))
        }
        return totals
    }

    private func isAppleWatch(_ device: HKDevice) -> Bool {
        if let hardwareVersion = device.hardwareVersion, hardwareVersion.localizedCaseInsensitiveContains("watch") {
            return true
        }
        if let model = device.model, model.localizedCaseInsensitiveContains("watch") {
            return true
        }
        if let name = device.name, name.localizedCaseInsensitiveContains("watch") {
            return true
        }
        return false
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
