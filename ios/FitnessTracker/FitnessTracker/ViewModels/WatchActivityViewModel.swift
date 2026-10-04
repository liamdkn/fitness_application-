import Combine
import Foundation

/// One reviewable Watch workout - either a cardio session with no home in
/// the app yet (import it as a real one), or a Functional Strength
/// Training session that overlaps a workout already logged in-app (add its
/// heart rate/calories onto that existing workout). Never a Functional
/// Strength Training session with no matching app workout - per the
/// enrich-only design, that one has nowhere to go and is silently skipped.
enum WatchActivityCandidate: Identifiable {
    case cardio(DetectedWatchWorkout, cardioType: CardioType)
    case strengthEnrichment(DetectedWatchWorkout, workout: Workout)

    var id: String {
        switch self {
        case .cardio(let workout, _): workout.id
        case .strengthEnrichment(let workout, _): workout.id
        }
    }

    var detectedWorkout: DetectedWatchWorkout {
        switch self {
        case .cardio(let workout, _): workout
        case .strengthEnrichment(let workout, _): workout
        }
    }
}

/// Surfaces Watch-recorded workouts for the user to explicitly import
/// (cardio) or enrich (strength) - see `docs` conversation: detection runs
/// automatically, but nothing is written to `cardio_tracking_sessions` or
/// `workouts` without the user tapping a specific candidate. This is
/// deliberately separate from `HealthSyncService`, which only ever writes
/// steps/sleep/nutrition silently - workouts are a different kind of data
/// (a whole logged session, not just a daily number) and warrant asking
/// first.
@MainActor
final class WatchActivityViewModel: ObservableObject {
    @Published var candidates: [WatchActivityCandidate] = []
    @Published var errorMessage: String?
    @Published var isProcessing = false

    private let healthKit = HealthKitManager()
    private let cardioSessionRepository = CardioSessionRepository()
    private let workoutRepository = WorkoutRepository()
    private let dismissedRepository = DismissedHealthKitWorkoutRepository()
    /// How far back a Watch workout is still worth surfacing - long enough
    /// to catch "forgot to check for a few days," not so long it starts
    /// digging up ancient sessions once the user's actually caught up.
    private let daysBack = 7
    /// Runs reach back much further than the rest - a running plan is
    /// judged over weeks, so a run from a month ago is still worth
    /// importing (once; imported/dismissed ones are skipped below).
    private let runDaysBack = 60

    func loadCandidates() async {
        do {
            try await healthKit.requestAuthorization()
            let calendar = Calendar.current
            let windowStart = calendar.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
            let runWindowStart = calendar.date(byAdding: .day, value: -runDaysBack, to: Date()) ?? Date()

            async let detectedResult = healthKit.fetchRecentWorkouts(daysBack: runDaysBack)
            async let dismissedResult = dismissedRepository.fetchDismissedIds()
            // Same span as the Watch lookup, so a run imported weeks ago is
            // still recognised as imported instead of reappearing.
            async let cardioHistoryResult = cardioSessionRepository.fetchHistory(from: runWindowStart, to: Date())
            async let appWorkoutsResult = workoutRepository.fetchWorkouts(from: windowStart, to: Date())

            let detected = try await detectedResult
            let dismissed = try await dismissedResult
            let cardioHistory = try await cardioHistoryResult
            let importedCardioIds = Set(cardioHistory.compactMap(\.healthkitUUID))
            // Sessions the user tracked live in-app (started/stopped here,
            // steps entered by hand) - never Watch-sourced ones, so this
            // can't match a Watch session against itself. Checked by time
            // overlap rather than cardio type, since the Watch's own
            // auto-detected type is coarser than what's picked in-app (e.g.
            // it says plain "Walk" for what was logged here as "Incline
            // Walk") - matching on type would miss exactly the duplicate
            // this exists to catch.
            let appCardioSessions = cardioHistory.filter { $0.source == "app" }
            let appWorkouts = try await appWorkoutsResult
            let enrichedWorkoutIds = Set(appWorkouts.compactMap(\.healthkitWorkoutUUID))

            // Each app workout can only absorb one Watch strength session -
            // without tracking this, two Watch workouts on the same day
            // (e.g. a real session plus a stray Watch-detected one) could
            // both try to match the same still-unenriched app workout.
            var claimedWorkoutIds: Set<UUID> = []
            var built: [WatchActivityCandidate] = []
            for workout in detected {
                guard !dismissed.contains(workout.id) else { continue }
                // Only runs get the long lookback; everything else keeps
                // the original short one.
                if workout.kind != .running, workout.startedAt < windowStart { continue }
                switch workout.kind {
                case .running:
                    guard !importedCardioIds.contains(workout.id) else { continue }
                    guard !overlapsExistingAppSession(workout, in: appCardioSessions) else { continue }
                    // An Indoor Run on a treadmill is a treadmill session,
                    // not an outdoor run - keeps the running plan to runs
                    // that actually covered ground.
                    built.append(.cardio(workout, cardioType: workout.isIndoor == true ? .treadmill : .outdoorRun))
                case .walk:
                    guard !importedCardioIds.contains(workout.id) else { continue }
                    guard !overlapsExistingAppSession(workout, in: appCardioSessions) else { continue }
                    // A walk the Watch started as an Indoor Walk is a treadmill
                    // session, not an outdoor walk - so it counts as one and
                    // its steps can come off the day's real walking.
                    built.append(.cardio(workout, cardioType: workout.isIndoor == true ? .inclineTreadmill : .outdoorWalk))
                case .stairmaster:
                    guard !importedCardioIds.contains(workout.id) else { continue }
                    guard !overlapsExistingAppSession(workout, in: appCardioSessions) else { continue }
                    built.append(.cardio(workout, cardioType: .stairmaster))
                case .functionalStrength:
                    guard !enrichedWorkoutIds.contains(workout.id) else { continue }
                    guard let match = appWorkouts.first(where: {
                        !claimedWorkoutIds.contains($0.id)
                            && $0.healthkitWorkoutUUID == nil
                            && calendar.isDate($0.performedAt, inSameDayAs: workout.startedAt)
                    }) else { continue }
                    claimedWorkoutIds.insert(match.id)
                    built.append(.strengthEnrichment(workout, workout: match))
                }
            }
            candidates = built
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Whether this detected Watch workout's time range overlaps a cardio
    /// session already tracked live in the app - e.g. recording a treadmill
    /// walk here to log exact steps, which the Watch also auto-detected as
    /// its own separate "Walk" session. A plain overlap check (rather than
    /// requiring one to fully contain the other) since the Watch's
    /// auto-detected start/end rarely lines up exactly with a manual
    /// start/stop.
    private func overlapsExistingAppSession(_ detected: DetectedWatchWorkout, in appSessions: [CardioTrackingSession]) -> Bool {
        appSessions.contains { session in
            guard let sessionEnd = session.endedAt else { return false }
            return detected.startedAt < sessionEnd && session.startedAt < detected.endedAt
        }
    }

    /// Old Watch runs imported before the extras and route were read: fills
    /// them in. Only touches runs with none of the extras stored yet, so a
    /// run is enriched once, not on every open.
    func backfillRunExtras() async {
        do {
            let runWindowStart = Calendar.current.date(byAdding: .day, value: -runDaysBack, to: Date()) ?? Date()
            let history = try await cardioSessionRepository.fetchHistory(from: runWindowStart, to: Date())
            let needing = history.filter {
                $0.healthkitUUID != nil && !$0.hasRoute && $0.elevationGainM == nil
                    && $0.avgPowerW == nil && $0.avgCadenceSPM == nil
                    && ($0.cardioType == .outdoorRun || $0.cardioType == .treadmill)
            }
            guard !needing.isEmpty else { return }
            try await healthKit.requestAuthorization()
            let detected = try await healthKit.fetchRecentWorkouts(daysBack: runDaysBack).filter { $0.kind == .running }
            for session in needing {
                guard let workout = detected.first(where: { $0.id == session.healthkitUUID }) else { continue }
                let route = await healthKit.fetchRoute(workoutId: workout.id)
                try await cardioSessionRepository.enrichRun(
                    sessionId: session.id,
                    distanceMeters: session.distanceMeters == nil ? workout.distanceMeters : nil,
                    elevationGainM: workout.elevationGainM,
                    avgPowerW: workout.avgPowerW,
                    avgCadenceSPM: workout.avgCadenceSPM,
                    totalCalories: workout.totalCalories,
                    route: route
                )
            }
        } catch {
            // Best-effort - the runs are already imported; extras can wait.
        }
    }

    func importCardio(_ workout: DetectedWatchWorkout, cardioType: CardioType) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let route = workout.kind == .running ? await healthKit.fetchRoute(workoutId: workout.id) : []
            try await cardioSessionRepository.importFromHealthKit(
                cardioType: cardioType,
                startedAt: workout.startedAt,
                endedAt: workout.endedAt,
                avgHeartRate: workout.avgHeartRate,
                activeCalories: workout.activeCalories,
                distanceMeters: workout.distanceMeters,
                elevationGainM: workout.elevationGainM,
                avgPowerW: workout.avgPowerW,
                avgCadenceSPM: workout.avgCadenceSPM,
                totalCalories: workout.totalCalories,
                route: route,
                healthkitUUID: workout.id
            )
            // A machine-counted walk's steps go in the same place a hand-timed
            // one's do, so "exclude cardio steps" works for Watch sessions too.
            if workout.kind == .walk, workout.isIndoor == true, let steps = workout.stepCount, steps > 0 {
                _ = try? await CardioStepSessionRepository().logSession(date: workout.startedAt, stepsBefore: 0, stepsAfter: steps)
            }
            candidates.removeAll { $0.id == workout.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enrichStrength(_ workout: DetectedWatchWorkout, appWorkout: Workout) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await workoutRepository.enrichFromHealthKit(
                workoutId: appWorkout.id,
                avgHeartRate: workout.avgHeartRate,
                activeCalories: workout.activeCalories,
                healthkitWorkoutUUID: workout.id
            )
            candidates.removeAll { $0.id == workout.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismiss(_ workout: DetectedWatchWorkout) async {
        do {
            try await dismissedRepository.dismiss(healthkitUUID: workout.id)
            candidates.removeAll { $0.id == workout.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
