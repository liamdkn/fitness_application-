import Foundation
import HealthKit

enum HealthKitError: Error {
    case notAvailable
}

struct DailySleep {
    let totalMinutes: Int
    let inBedMinutes: Int
}

struct DailyNutrition {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

final class HealthKitManager {
    private let store = HKHealthStore()

    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    private var caloriesType: HKQuantityType { HKQuantityType(.dietaryEnergyConsumed) }
    private var proteinType: HKQuantityType { HKQuantityType(.dietaryProtein) }
    private var carbsType: HKQuantityType { HKQuantityType(.dietaryCarbohydrates) }
    private var fatType: HKQuantityType { HKQuantityType(.dietaryFatTotal) }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.notAvailable }
        try await store.requestAuthorization(
            toShare: [],
            read: [stepType, sleepType, caloriesType, proteinType, carbsType, fatType]
        )
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

    /// Pulls in whatever a nutrition-logging app (e.g. MyFitnessPal) has
    /// written to Health. `.cumulativeSum` here is "add up every food/meal
    /// logged that day" - unlike steps, there's no cross-source dedup
    /// concern to worry about, it's just the correct daily total.
    func fetchDailyNutrition(daysBack: Int) async throws -> [Date: DailyNutrition] {
        async let calories = fetchDailySum(for: caloriesType, unit: .kilocalorie(), daysBack: daysBack)
        async let protein = fetchDailySum(for: proteinType, unit: .gram(), daysBack: daysBack)
        async let carbs = fetchDailySum(for: carbsType, unit: .gram(), daysBack: daysBack)
        async let fat = fetchDailySum(for: fatType, unit: .gram(), daysBack: daysBack)

        let (caloriesByDay, proteinByDay, carbsByDay, fatByDay) = try await (calories, protein, carbs, fat)

        // A day only appears if at least one of the four had samples, so a
        // day with no MFP entries is naturally skipped rather than synced
        // as all-zero.
        let allDays = Set(caloriesByDay.keys).union(proteinByDay.keys).union(carbsByDay.keys).union(fatByDay.keys)
        return Dictionary(uniqueKeysWithValues: allDays.map { day in
            (day, DailyNutrition(
                calories: caloriesByDay[day] ?? 0,
                proteinG: proteinByDay[day] ?? 0,
                carbsG: carbsByDay[day] ?? 0,
                fatG: fatByDay[day] ?? 0
            ))
        })
    }

    private func fetchDailySum(for type: HKQuantityType, unit: HKUnit, daysBack: Int) async throws -> [Date: Double] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: Date()))!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let anchorDate = calendar.startOfDay(for: startDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: anchorDate,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)

        var totals: [Date: Double] = [:]
        collection.enumerateStatistics(from: startDate, to: Date()) { statistics, _ in
            guard let sum = statistics.sumQuantity() else { return }
            totals[statistics.startDate] = sum.doubleValue(for: unit)
        }
        return totals
    }
}
