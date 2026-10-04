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

struct PlannedRun: Codable, Identifiable, Hashable {
    let id: UUID
    let runningPlanId: UUID
    let date: String
    let runType: RunType
    let targetDistanceKm: Double?
    let targetDurationMin: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, date, notes
        case runningPlanId = "running_plan_id"
        case runType = "run_type"
        case targetDistanceKm = "target_distance_km"
        case targetDurationMin = "target_duration_min"
    }

    var day: Date { DateFormatting.date(fromISODate: date) ?? Date() }

    /// The plan's implied average pace when both distance and duration have
    /// been entered. The watch workout uses this as its target pace alert.
    var targetPaceLabel: String? {
        guard let targetDistanceKm, targetDistanceKm > 0,
              let targetDurationMin, targetDurationMin > 0
        else { return nil }
        return RunFormat.pace(seconds: Double(targetDurationMin * 60), meters: targetDistanceKm * 1000)
    }

    /// "9 km", "35 min", "10 km \u{00b7} 60 min" - whichever targets exist.
    var targetLabel: String {
        var parts: [String] = []
        if let targetDistanceKm { parts.append(RunFormat.km(targetDistanceKm)) }
        if let targetDurationMin { parts.append("\(targetDurationMin) min") }
        if let targetPaceLabel { parts.append(targetPaceLabel) }
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
