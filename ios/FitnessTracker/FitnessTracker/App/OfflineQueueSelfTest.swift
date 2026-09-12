#if DEBUG
import Foundation
import Supabase

/// Debug-only, launch-argument-triggered verification harness for
/// `OfflineWorkoutQueue`. Not part of the product - this exists purely so
/// the offline-logging feature could be exercised end to end (real
/// SwiftData store, real Supabase, real network on/off) without a UI
/// automation path, and is safe to leave in the tree since `#if DEBUG`
/// compiles it out of Release builds entirely and it only ever runs when
/// explicitly launched with one of the arguments below.
///
/// Writes a running log to `<Documents>/offline-self-test.log`, appended
/// to (not overwritten) across the multiple launches a full run needs, so
/// the whole timeline - including across a simulated kill - can be read
/// back from the host Mac afterward via `xcrun simctl get_app_container`.
enum OfflineQueueSelfTest {
    private static var logURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline-self-test.log")
    }
    private static var stateURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline-self-test-state.json")
    }

    private struct TestState: Codable {
        var workoutId: UUID
        var setIds: [UUID]
    }

    static func runIfRequested() async {
        let arguments = Set(CommandLine.arguments)
        if arguments.contains("-offlineSelfTestReset") {
            try? FileManager.default.removeItem(at: logURL)
            try? FileManager.default.removeItem(at: stateURL)
            exit(0)
        }
        if arguments.contains("-offlineSelfTestRun") {
            await runMainScenario()
            exit(0)
        }
        if arguments.contains("-offlineKillTestStart") {
            await runKillTestStart()
            // Deliberately no `exit(0)` here for the *scripted* end of the
            // scenario - the harness kills this process externally
            // (`simctl terminate`) partway through, which is the point.
            // If it ever runs to completion on its own, exit cleanly.
            exit(0)
        }
        if arguments.contains("-offlineKillTestVerify") {
            await runKillTestVerify()
            exit(0)
        }
    }

    private static func log(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(line)\n"
        print(entry, terminator: "")
        if let data = entry.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    /// Mirrors `ActiveWorkoutViewModel.loadTemplate()`'s own fallback - the
    /// exercise library is reference data cached via `OfflineReferenceCache`,
    /// not something a genuinely offline test (or the real app, cold at the
    /// gym) can fetch live. Reuses the same cache key so this harness is
    /// actually exercising the same offline path the app does, rather than
    /// a fetch the real active-workout screen never depends on when offline.
    private static func fetchAnyExercise() async -> Exercise? {
        if let fetched = try? await ExerciseRepository().fetchAll() {
            OfflineReferenceCache.save(fetched, key: "exercise-library")
            return fetched.first
        }
        return OfflineReferenceCache.load([Exercise].self, key: "exercise-library")?.first
    }

    private static func waitForSession() async -> Bool {
        for _ in 0..<20 {
            if SupabaseService.shared.session != nil { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    /// Requirement 1: start a workout, log sets, and confirm they land in
    /// Supabase once connectivity returns - all in one long-lived process
    /// so the "no relaunch needed" part of automatic sync is genuinely
    /// exercised, not just "it syncs the next time the app happens to
    /// launch."
    private static func runMainScenario() async {
        log("=== main scenario start ===")
        guard await waitForSession() else {
            log("FAIL: no authenticated session after waiting - cannot proceed")
            return
        }

        let queue = OfflineWorkoutQueue.shared
        guard let exercise = await fetchAnyExercise() else {
            log("FAIL: could not fetch any exercise to log a test set against")
            return
        }
        log("Using exercise \(exercise.name) (\(exercise.id))")

        do {
            let workout = try await queue.startWorkout(routineDayId: nil)
            log("Started workout locally: id=\(workout.id)")

            var setIds: [UUID] = []
            for i in 1...3 {
                let set = try await queue.addSet(
                    workout: workout,
                    exerciseId: exercise.id,
                    setIndex: i,
                    reps: 10 + i,
                    weightKg: 20.0 * Double(i),
                    rpe: 7.0,
                    isWarmup: false,
                    isDropSet: false
                )
                setIds.append(set.id)
                log("Logged set \(i) locally: id=\(set.id) reps=\(set.reps) weightKg=\(set.weightKg)")
            }
            try await queue.finishWorkout(workout: workout, rating: 4)
            log("Finished workout locally")

            try? JSONEncoder().encode(TestState(workoutId: workout.id, setIds: setIds)).write(to: stateURL)

            // Monitor for up to 2 minutes - long enough for the harness to
            // flip host networking back on partway through and for
            // `NetworkMonitor`'s reconnect callback to trigger a flush,
            // entirely on its own, no relaunch.
            for tick in 0..<40 {
                let remoteSets = (try? await WorkoutRepository().fetchSets(workoutId: workout.id)) ?? []
                let remoteWorkout = try? await fetchWorkoutDirect(id: workout.id)
                log("tick=\(tick) remoteSetsCount=\(remoteSets.count) remoteWorkoutFound=\(remoteWorkout != nil) remoteWorkoutEndedAt=\(remoteWorkout?.endedAt.map(String.init(describing:)) ?? "nil")")
                if remoteSets.count == 3, remoteWorkout?.endedAt != nil {
                    log("SUCCESS: workout and all 3 sets confirmed present in Supabase")
                    break
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }

            // Clean up so the test leaves no trace in real data.
            try? await queue.deleteWorkout(workoutId: workout.id)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await queue.flushPendingChanges()
            let stillThere = (try? await fetchWorkoutDirect(id: workout.id)) != nil
            log("Cleanup: workout still present remotely = \(stillThere)")
        } catch {
            log("FAIL: \(error)")
        }
        log("=== main scenario end ===")
    }

    /// Requirement 3: start a workout, log a set, then simulate the app
    /// being killed before anything syncs (this process just calls
    /// `exit(0)` right after the local writes, which - since nothing here
    /// awaits a network round trip - lands at effectively the same point a
    /// real kill would: local data written, nothing yet pushed).
    private static func runKillTestStart() async {
        log("=== kill test start ===")
        guard await waitForSession() else {
            log("FAIL: no authenticated session after waiting - cannot proceed")
            return
        }
        let queue = OfflineWorkoutQueue.shared
        guard let exercise = await fetchAnyExercise() else {
            log("FAIL: could not fetch any exercise to log a test set against")
            return
        }
        do {
            let workout = try await queue.startWorkout(routineDayId: nil)
            let set = try await queue.addSet(
                workout: workout,
                exerciseId: exercise.id,
                setIndex: 1,
                reps: 12,
                weightKg: 42.5,
                rpe: nil,
                isWarmup: false,
                isDropSet: false
            )
            try? JSONEncoder().encode(TestState(workoutId: workout.id, setIds: [set.id])).write(to: stateURL)
            log("Wrote workout \(workout.id) and set \(set.id) locally - simulating kill now")
        } catch {
            log("FAIL: \(error)")
        }
    }

    private static func runKillTestVerify() async {
        log("=== kill test verify (fresh process) ===")
        guard let data = try? Data(contentsOf: stateURL), let state = try? JSONDecoder().decode(TestState.self, from: data) else {
            log("FAIL: no state file from the kill-test start phase")
            return
        }
        guard await waitForSession() else {
            log("FAIL: no authenticated session after waiting - cannot proceed")
            return
        }
        let queue = OfflineWorkoutQueue.shared

        // Local durability check first - this must be non-empty and exactly
        // one set even before any network activity, proving the SwiftData
        // store survived the kill on its own.
        let localSets = (try? await queue.fetchSets(workoutId: state.workoutId)) ?? []
        log("Local sets recovered after relaunch: \(localSets.count) (expected 1)")

        // `OfflineWorkoutQueue.init()` schedules a flush on its own the
        // moment it's created - this loop just waits for that to land
        // rather than triggering it manually.
        for tick in 0..<20 {
            let remoteSets = (try? await WorkoutRepository().fetchSets(workoutId: state.workoutId)) ?? []
            log("tick=\(tick) remoteSetsCount=\(remoteSets.count)")
            if remoteSets.count == 1 {
                log("SUCCESS: post-kill relaunch synced the queued set with no duplicates")
                break
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }

        try? await queue.deleteWorkout(workoutId: state.workoutId)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await queue.flushPendingChanges()
        try? FileManager.default.removeItem(at: stateURL)
        log("Cleanup done")
    }

    private static func fetchWorkoutDirect(id: UUID) async throws -> Workout? {
        let workouts: [Workout] = try await SupabaseService.shared.client
            .from("workouts")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return workouts.first
    }
}
#endif
