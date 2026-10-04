import Foundation

/// A running programme: a start date and a set of planned runs, judged
/// against what the Apple Watch actually recorded (`RunningPlanRepository`).
struct RunningPlan: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    /// "yyyy-MM-dd" - same plain-date-as-String convention as the rest of
    /// the app's `date` columns, parse with `DateFormatting.date(fromISODate:)`.
    let startDate: String
    /// The programme's own week number for the week `startDate` falls in -
    /// a plan joined at week 4 still reads "Week 4", not "Week 1".
    let firstWeekNumber: Int
    let targetRaceDate: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case startDate = "start_date"
        case firstWeekNumber = "first_week_number"
        case targetRaceDate = "target_race_date"
    }

    var start: Date { DateFormatting.date(fromISODate: startDate) ?? Date() }
}

enum RunType: String, Codable, CaseIterable, Identifiable {
    case easy, long, tempo, interval
    case racePace = "race_pace"
    case rest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .long: "Long"
        case .tempo: "Tempo"
        case .interval: "Intervals"
        case .racePace: "Race pace"
        case .rest: "Rest"
        }
    }
}

/// One part of a run: a distance or a time, and the pace to hold for it.
struct RunStep: Codable, Hashable {
    var distanceM: Double?
    var seconds: Int?
    var paceSecPerKm: Int?

    enum CodingKeys: String, CodingKey {
        case distanceM = "distance_m"
        case seconds
        case paceSecPerKm = "pace_sec"
    }

    /// "400 m @ 4:30/km", "60 s", "2 km".
    var label: String {
        var parts: [String] = []
        if let distanceM {
            parts.append(distanceM >= 1000 ? RunFormat.km(distanceM / 1000) : "\(Int(distanceM)) m")
        } else if let seconds {
            parts.append(seconds % 60 == 0 && seconds >= 120 ? "\(seconds / 60) min" : "\(seconds) s")
        }
        if let paceSecPerKm { parts.append("@ " + PaceText.format(paceSecPerKm)) }
        return parts.joined(separator: " ")
    }
}

/// A piece repeated `reps` times: work, then optionally recovery.
struct RunBlock: Codable, Hashable {
    var reps: Int
    var work: RunStep
    var recovery: RunStep?

    var label: String {
        var text = "\(reps) \u{00d7} \(work.label)"
        if let recovery { text += ", \(recovery.label) recovery" }
        return text
    }
}

/// Paces typed and shown as minutes:seconds per km.
enum PaceText {
    /// "5:30" or "5.5"-free: only m:ss, returning seconds per km.
    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]),
              (0..<60).contains(seconds), minutes >= 0 else { return nil }
        let total = minutes * 60 + seconds
        return (150...1200).contains(total) ? total : nil
    }

    static func format(_ secPerKm: Int) -> String {
        String(format: "%d:%02d/km", secPerKm / 60, secPerKm % 60)
    }

    /// The editable form, without the unit.
    static func field(_ secPerKm: Int?) -> String {
        secPerKm.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? ""
    }
}

struct PlannedRun: Codable, Identifiable, Hashable {
    let id: UUID
    let runningPlanId: UUID
    let date: String
    let runType: RunType
    let targetDistanceKm: Double?
    let targetDurationMin: Int?
    let notes: String?
    /// Minutes of warm-up and cool-down. Nil is the old default of 10; 0 is none.
    var warmupMin: Int? = nil
    var warmupPaceSec: Int? = nil
    var cooldownMin: Int? = nil
    var cooldownPaceSec: Int? = nil
    /// The pace to hold for a plain run; nil works it out from distance and time.
    var mainPaceSec: Int? = nil
    /// Repeated pieces (intervals, tempo blocks); when present they replace
    /// the single main step.
    var blocks: [RunBlock]? = nil

    enum CodingKeys: String, CodingKey {
        case id, date, notes, blocks
        case warmupMin = "warmup_min"
        case warmupPaceSec = "warmup_pace_sec"
        case cooldownMin = "cooldown_min"
        case cooldownPaceSec = "cooldown_pace_sec"
        case mainPaceSec = "main_pace_sec"
        case runningPlanId = "running_plan_id"
        case runType = "run_type"
        case targetDistanceKm = "target_distance_km"
        case targetDurationMin = "target_duration_min"
    }

    var day: Date { DateFormatting.date(fromISODate: date) ?? Date() }

    /// The plan's implied average pace when both distance and duration have
    /// been entered. The watch workout uses this as its target pace alert.
    var targetPaceLabel: String? {
        if let mainPaceSec { return PaceText.format(mainPaceSec) }
        guard let targetDistanceKm, targetDistanceKm > 0,
              let targetDurationMin, targetDurationMin > 0
        else { return nil }
        return RunFormat.pace(seconds: Double(targetDurationMin * 60), meters: targetDistanceKm * 1000)
    }

    /// "Warm-up 10 min @ 6:30/km. 6 x 400 m @ 4:30/km, 90 s recovery. Cool-down 10 min" - only when
    /// the run spells out more than the plain target.
    var structureLine: String? {
        var parts: [String] = []
        if let warmupMin, warmupMin > 0 {
            parts.append("Warm-up \(warmupMin) min" + (warmupPaceSec.map { " @ " + PaceText.format($0) } ?? ""))
        }
        if let blocks, !blocks.isEmpty { parts.append(contentsOf: blocks.map(\.label)) }
        if let cooldownMin, cooldownMin > 0 {
            parts.append("Cool-down \(cooldownMin) min" + (cooldownPaceSec.map { " @ " + PaceText.format($0) } ?? ""))
        }
        let hasDetail = (blocks?.isEmpty == false) || warmupPaceSec != nil || cooldownPaceSec != nil
            || (warmupMin != nil && warmupMin != 10) || (cooldownMin != nil && cooldownMin != 10)
        return hasDetail ? parts.joined(separator: " \u{00b7} ") : nil
    }

    /// "9 km", "35 min", "10 km \u{00b7} 60 min" - whichever targets exist.
    var targetLabel: String {
        var parts: [String] = []
        if let targetDistanceKm { parts.append(RunFormat.km(targetDistanceKm)) }
        if let targetDurationMin { parts.append("\(targetDurationMin) min") }
        if let targetPaceLabel { parts.append(targetPaceLabel) }
        if let blocks, !blocks.isEmpty, parts.isEmpty { return blocks.map(\.label).joined(separator: "; ") }
        return parts.isEmpty ? (runType == .rest ? "Rest" : "No target") : parts.joined(separator: " \u{00b7} ")
    }
}

/// How a Watch-recorded run reads next to its plan row.
enum RunFormat {
    static func km(_ km: Double) -> String {
        let text = String(format: "%.1f", km)
        return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + " km"
    }

    /// "5:34/km" from total seconds and metres - `nil` without a distance.
    static func pace(seconds: TimeInterval, meters: Double) -> String? {
        guard meters > 0, seconds > 0 else { return nil }
        let perKm = seconds / (meters / 1000)
        let whole = Int(perKm.rounded())
        return String(format: "%d:%02d/km", whole / 60, whole % 60)
    }
}
