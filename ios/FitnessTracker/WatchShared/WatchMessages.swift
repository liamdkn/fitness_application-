import Foundation

/// What the Watch and the iPhone say to each other over WatchConnectivity.
/// Everything is sent as a property list (`userInfo`), which is queued and
/// delivered even if the other side isn't running, and each message carries an
/// id so being delivered twice never logs twice.
nonisolated enum WatchMessage {
    static let typeKey = "type"

    /// Water drunk, logged from the Watch.
    struct Water {
        let id: UUID
        let amountMl: Int
        let at: Date

        var userInfo: [String: Any] {
            [WatchMessage.typeKey: "water", "id": id.uuidString, "ml": amountMl, "at": at.timeIntervalSince1970]
        }

        init(id: UUID = UUID(), amountMl: Int, at: Date = Date()) {
            self.id = id; self.amountMl = amountMl; self.at = at
        }

        init?(_ info: [String: Any]) {
            guard info[WatchMessage.typeKey] as? String == "water",
                  let id = (info["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let ml = info["ml"] as? Int, let at = info["at"] as? Double else { return nil }
            self.init(id: id, amountMl: ml, at: Date(timeIntervalSince1970: at))
        }
    }

    /// A finished incline-treadmill session: when it ran, the steps counted
    /// before and after, and the Watch workout it was recorded as.
    struct Treadmill {
        let workoutId: UUID
        let start: Date
        let end: Date
        let stepsBefore: Int
        let stepsAfter: Int
        let avgHeartRate: Int?
        let activeCalories: Double?

        var userInfo: [String: Any] {
            var info: [String: Any] = [
                WatchMessage.typeKey: "treadmill", "id": workoutId.uuidString,
                "start": start.timeIntervalSince1970, "end": end.timeIntervalSince1970,
                "stepsBefore": stepsBefore, "stepsAfter": stepsAfter,
            ]
            if let avgHeartRate { info["hr"] = avgHeartRate }
            if let activeCalories { info["kcal"] = activeCalories }
            return info
        }

        init(workoutId: UUID, start: Date, end: Date, stepsBefore: Int, stepsAfter: Int, avgHeartRate: Int?, activeCalories: Double?) {
            self.workoutId = workoutId; self.start = start; self.end = end
            self.stepsBefore = stepsBefore; self.stepsAfter = stepsAfter
            self.avgHeartRate = avgHeartRate; self.activeCalories = activeCalories
        }

        init?(_ info: [String: Any]) {
            guard info[WatchMessage.typeKey] as? String == "treadmill",
                  let id = (info["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let start = info["start"] as? Double, let end = info["end"] as? Double,
                  let before = info["stepsBefore"] as? Int, let after = info["stepsAfter"] as? Int else { return nil }
            self.init(
                workoutId: id, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end),
                stepsBefore: before, stepsAfter: after,
                avgHeartRate: info["hr"] as? Int, activeCalories: info["kcal"] as? Double
            )
        }
    }

    /// Sent the other way, as application context (the latest wins): the
    /// water amounts to offer as buttons and today's total.
    struct Config {
        let waterButtonsMl: [Int]
        let waterTodayMl: Int
        let waterTargetMl: Int

        var context: [String: Any] {
            ["waterButtons": waterButtonsMl, "waterToday": waterTodayMl, "waterTarget": waterTargetMl]
        }

        init(waterButtonsMl: [Int], waterTodayMl: Int, waterTargetMl: Int) {
            self.waterButtonsMl = waterButtonsMl; self.waterTodayMl = waterTodayMl; self.waterTargetMl = waterTargetMl
        }

        init?(_ context: [String: Any]) {
            guard let buttons = context["waterButtons"] as? [Int], let today = context["waterToday"] as? Int,
                  let target = context["waterTarget"] as? Int else { return nil }
            self.init(waterButtonsMl: buttons, waterTodayMl: today, waterTargetMl: target)
        }
    }
}
