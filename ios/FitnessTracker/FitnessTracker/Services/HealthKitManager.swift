import CoreLocation
import Foundation
import HealthKit

enum HealthKitError: Error {
    case notAvailable
}

struct DailySleep {
    let totalMinutes: Int
    let inBedMinutes: Int
}

/// Which of our own concepts a Watch-recorded `HKWorkout` maps to - the
/// only `HKWorkoutActivityType`s `fetchRecentWorkouts` looks for at all,
/// everything else is dropped before it ever reaches app code.
enum WatchWorkoutKind {
    case walk
    case stairmaster
    case functionalStrength
    case running
}

/// One Watch-recorded workout, already reduced to just what
/// `WatchActivityViewModel` needs - no `HealthKit` types escape
/// `HealthKitManager` itself.
struct DetectedWatchWorkout: Identifiable {
    let id: String
    let kind: WatchWorkoutKind
    let startedAt: Date
    let endedAt: Date
    let avgHeartRate: Int?
    let activeCalories: Double?
    /// Only meaningful for `.walk` - whether the Watch itself was started
    /// as an Indoor Walk vs Outdoor Walk (`HKMetadataKeyIndoorWorkout`).
    /// `nil` when the Watch didn't record that flag at all (older watchOS
    /// versions, or a source other than the Watch's own Workout app) -
    /// callers should read that as "unknown," not "outdoor."
    let isIndoor: Bool?
    /// Distance the Watch recorded for the workout, if it recorded one -
    /// what a running plan compares against its target.
    let distanceMeters: Double?
    /// The rest are run extras - nil for anything the Watch didn't record,
    /// and for every non-run workout.
    let elevationGainM: Double?
    let avgPowerW: Int?
    let avgCadenceSPM: Int?
    /// Active + resting energy, as Apple's own "Total Calories".
    let totalCalories: Double?
    /// Steps taken during the workout, as the Watch counted them.
    let stepCount: Int?
}

final class HealthKitManager {
    private let store = HKHealthStore()

    /// Midnight `daysBack` days ago. (Falls back to today's midnight rather
    /// than crashing in the unreachable case that the calendar can't subtract.)
    private static func windowStart(daysBack: Int, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
    }
    private var stepObserver: HKObserverQuery?

    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
    private var activeEnergyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private var distanceType: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }
    private var runningPowerType: HKQuantityType { HKQuantityType(.runningPower) }
    private var basalEnergyType: HKQuantityType { HKQuantityType(.basalEnergyBurned) }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.notAvailable }
        try await store.requestAuthorization(
            toShare: [],
            read: [
                stepType, sleepType,
                heartRateType, activeEnergyType, distanceType, runningPowerType, basalEnergyType,
                HKObjectType.workoutType(), HKSeriesType.workoutRoute()
            ]
        )
    }

    /// Every Watch-recorded Walk, Run, Stairmaster, or Functional
    /// Strength Training session in the last `daysBack` days - read-only,
    /// detection only. Nothing here writes anything; turning a result into
    /// an imported cardio session or an enriched workout only happens once
    /// the user confirms it (`WatchActivityViewModel`), never automatically.
    func fetchRecentWorkouts(daysBack: Int) async throws -> [DetectedWatchWorkout] {
        let calendar = Calendar.current
        let startDate = Self.windowStart(daysBack: daysBack, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let workouts = try await descriptor.result(for: store)

        return workouts.compactMap { workout -> DetectedWatchWorkout? in
            let kind: WatchWorkoutKind
            switch workout.workoutActivityType {
            case .walking: kind = .walk
            case .stairClimbing: kind = .stairmaster
            case .functionalStrengthTraining: kind = .functionalStrength
            case .running: kind = .running
            default: return nil
            }
            let avgHeartRate = workout.statistics(for: heartRateType)?
                .averageQuantity()?
                .doubleValue(for: .count().unitDivided(by: .minute()))
            let activeCalories = workout.statistics(for: activeEnergyType)?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
            let isIndoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool
            let distanceMeters = workout.statistics(for: distanceType)?
                .sumQuantity()?
                .doubleValue(for: .meter())
            var elevationGainM: Double?
            var avgPowerW: Int?
            var avgCadenceSPM: Int?
            var totalCalories: Double?
            if kind == .running {
                elevationGainM = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
                    .doubleValue(for: .meter())
                let watts = workout.statistics(for: runningPowerType)?
                    .averageQuantity()?
                    .doubleValue(for: .watt())
                avgPowerW = watts.map { Int($0.rounded()) }
                // Apple's "Avg Cadence" is steps taken during the run per
                // minute of it - no stored average to read, so derive it.
                if let steps = workout.statistics(for: stepType)?.sumQuantity()?.doubleValue(for: .count()),
                   workout.duration > 0 {
                    avgCadenceSPM = Int((steps / (workout.duration / 60)).rounded())
                }
                let basal = workout.statistics(for: basalEnergyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
                if let activeCalories { totalCalories = activeCalories + (basal ?? 0) }
            }
            let stepCount = workout.statistics(for: stepType)?.sumQuantity()
                .map { Int($0.doubleValue(for: .count()).rounded()) }
            return DetectedWatchWorkout(
                id: workout.uuid.uuidString,
                kind: kind,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                avgHeartRate: avgHeartRate.map { Int($0.rounded()) },
                activeCalories: activeCalories,
                isIndoor: (kind == .walk || kind == .running) ? isIndoor : nil,
                distanceMeters: distanceMeters,
                elevationGainM: elevationGainM,
                avgPowerW: avgPowerW,
                avgCadenceSPM: avgCadenceSPM,
                totalCalories: totalCalories,
                stepCount: stepCount
            )
        }
    }

    /// The GPS route of one workout, thinned for storage - empty for a
    /// workout with no route (an indoor run, GPS off) or one that can't be
    /// read. Fetched separately from `fetchRecentWorkouts` and only when a
    /// run is actually being imported: reading every point of every run on
    /// each Dashboard load would be wasteful, and it's only wanted once.
    func fetchRoute(workoutId: String) async -> [RoutePoint] {
        guard let uuid = UUID(uuidString: workoutId) else { return [] }
        do {
            let workouts = try await HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForObject(with: uuid))],
                sortDescriptors: [],
                limit: 1
            ).result(for: store)
            guard let workout = workouts.first else { return [] }

            let routeSamples = try await HKSampleQueryDescriptor(
                predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))],
                sortDescriptors: [SortDescriptor(\.startDate)]
            ).result(for: store)

            var locations: [CLLocation] = []
            for case let route as HKWorkoutRoute in routeSamples {
                for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
                    locations.append(location)
                }
            }
            return RouteMath.downsample(locations)
        } catch {
            return []
        }
    }

    /// Calls `onChange` whenever new step data lands in Health - including
    /// while the app isn't running, when iOS wakes it in the background
    /// (hourly at most; needs the HealthKit background-delivery entitlement,
    /// and doesn't apply to an app the user has force-quit). The query has to
    /// be set up each launch, which is why `AppDelegate` does it at startup.
    func observeSteps(onChange: @escaping @Sendable () async -> Void) {
        guard HKHealthStore.isHealthDataAvailable(), stepObserver == nil else { return }
        let query = Self.makeObserver(for: stepType, onChange: onChange)
        stepObserver = query
        store.execute(query)
        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { _, _ in }
    }

    // Static and nonisolated so the handler isn't inferred as main-actor
    // isolated - HealthKit calls it on its own queue.
    private nonisolated static func makeObserver(
        for type: HKQuantityType, onChange: @escaping @Sendable () async -> Void
    ) -> HKObserverQuery {
        HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            nonisolated(unsafe) let completion = completion
            guard error == nil else { completion(); return }
            Task {
                await onChange()
                // HealthKit stops waking the app if this isn't called.
                completion()
            }
        }
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
        let startDate = Self.windowStart(daysBack: daysBack, calendar: calendar)
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
        let startDate = Self.windowStart(daysBack: daysBack, calendar: calendar)
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

        // A day with zero Watch samples (dead battery, watch not worn that
        // day, etc.) would otherwise just be absent from the result -
        // "Apple Watch" stays the default source (this function still runs
        // first, and any day the Watch actually recorded something wins),
        // but a day it recorded nothing falls back to the merged Health
        // total for that day only, rather than silently reading as
        // no-data/zero.
        let mergedTotals = try await fetchMergedDailySteps(daysBack: daysBack)
        for (day, mergedCount) in mergedTotals where totals[day] == nil {
            totals[day] = mergedCount
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

    /// A night's samples aren't one continuous block - Watch sleep-stage
    /// tracking writes many small, separately-timestamped samples across
    /// the night. Bucketing each sample by its OWN end date (the previous
    /// approach) silently split a night at midnight: the chunk between
    /// bedtime and 00:00 landed on yesterday, undercounting last night's
    /// total by however long that pre-midnight chunk was. Consecutive
    /// samples less than this far apart are treated as the same night
    /// (comfortably wider than any mid-sleep awake gap, but tight enough
    /// to still separate a night from, say, an afternoon nap).
    private static let sleepSessionGapThreshold: TimeInterval = 4 * 60 * 60

    /// When you fell asleep on each recent night, on `BedtimeEstimate`'s night
    /// scale - the start of the first asleep stretch of each sleep session.
    /// Sessions are split the same way as `fetchDailySleep` (a gap of more than
    /// `sleepSessionGapThreshold` starts a new one), and anything with under
    /// three hours asleep is treated as a nap and ignored.
    func fetchSleepOnsets(daysBack: Int) async throws -> [Int] {
        let calendar = Calendar.current
        let startDate = Self.windowStart(daysBack: daysBack, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)

        var onsets: [Int] = []
        var sessionEnd: Date?
        var onset: Date?
        var asleepMinutes = 0

        func commit() {
            if let onset, asleepMinutes >= 180 {
                onsets.append(BedtimeEstimate.nightMinutes(for: onset, calendar: calendar))
            }
        }

        for sample in samples {
            if let sessionEnd, sample.startDate.timeIntervalSince(sessionEnd) > Self.sleepSessionGapThreshold {
                commit()
                onset = nil
                asleepMinutes = 0
            }
            sessionEnd = Swift.max(sessionEnd ?? sample.endDate, sample.endDate)
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            switch value {
            case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                if onset == nil { onset = sample.startDate }
                asleepMinutes += Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
            default:
                break
            }
        }
        commit()
        return onsets
    }

    /// When you woke on each recent night, as minutes after midnight - the
    /// end of the last asleep stretch of each sleep session (same session
    /// rules as `fetchSleepOnsets`; naps under three hours are ignored).
    func fetchWakeMinutes(daysBack: Int) async throws -> [Int] {
        let calendar = Calendar.current
        let startDate = Self.windowStart(daysBack: daysBack, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)

        var wakes: [Int] = []
        var sessionEnd: Date?
        var lastAsleepEnd: Date?
        var asleepMinutes = 0

        func commit() {
            if let lastAsleepEnd, asleepMinutes >= 180 {
                let parts = calendar.dateComponents([.hour, .minute], from: lastAsleepEnd)
                wakes.append((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
        }

        for sample in samples {
            if let sessionEnd, sample.startDate.timeIntervalSince(sessionEnd) > Self.sleepSessionGapThreshold {
                commit()
                lastAsleepEnd = nil
                asleepMinutes = 0
            }
            sessionEnd = Swift.max(sessionEnd ?? sample.endDate, sample.endDate)
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            switch value {
            case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                lastAsleepEnd = sample.endDate
                asleepMinutes += Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
            default:
                break
            }
        }
        commit()
        return wakes
    }

    func fetchDailySleep(daysBack: Int) async throws -> [Date: DailySleep] {
        let calendar = Calendar.current
        let startDate = Self.windowStart(daysBack: daysBack, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)

        var totals: [Date: (asleep: Int, inBed: Int)] = [:]
        var sessionEnd: Date?
        var sessionAsleep = 0
        var sessionInBed = 0

        func commitSession() {
            guard let sessionEnd else { return }
            // The whole night is attributed to its wake-up date, not any
            // individual sample's end date, so a night that started before
            // midnight still counts as one consistent day.
            let wakeDay = calendar.startOfDay(for: sessionEnd)
            var entry = totals[wakeDay] ?? (asleep: 0, inBed: 0)
            entry.asleep += sessionAsleep
            entry.inBed += sessionInBed
            totals[wakeDay] = entry
        }

        for sample in samples {
            if let sessionEnd, sample.startDate.timeIntervalSince(sessionEnd) > Self.sleepSessionGapThreshold {
                commitSession()
                sessionAsleep = 0
                sessionInBed = 0
            }
            sessionEnd = Swift.max(sessionEnd ?? sample.endDate, sample.endDate)

            let minutes = Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
            if let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                switch value {
                case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                    sessionAsleep += minutes
                    sessionInBed += minutes
                case .inBed:
                    sessionInBed += minutes
                case .awake:
                    break
                @unknown default:
                    break
                }
            }
        }
        commitSession()

        return totals.mapValues { DailySleep(totalMinutes: $0.asleep, inBedMinutes: $0.inBed) }
    }
}
