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

    func loadCandidates() async {
        do {
            try await healthKit.requestAuthorization()
            let calendar = Calendar.current
            let windowStart = calendar.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()

            async let detectedResult = healthKit.fetchRecentWorkouts(daysBack: daysBack)
            async let dismissedResult = dismissedRepository.fetchDismissedIds()
            async let cardioHistoryResult = cardioSessionRepository.fetchHistory(limit: 50)
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
                switch workout.kind {
                case .walk:
                    guard !importedCardioIds.contains(workout.id) else { continue }
                    guard !overlapsExistingAppSession(workout, in: appCardioSessions) else { continue }
                    built.append(.cardio(workout, cardioType: .outdoorWalk))
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

    func importCardio(_ workout: DetectedWatchWorkout, cardioType: CardioType) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await cardioSessionRepository.importFromHealthKit(
                cardioType: cardioType,
                startedAt: workout.startedAt,
                endedAt: workout.endedAt,
                avgHeartRate: workout.avgHeartRate,
                activeCalories: workout.activeCalories,
                healthkitUUID: workout.id
            )
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
