import Foundation

enum CardioType: String, CaseIterable, Identifiable, Codable {
    case treadmill
    case inclineTreadmill = "incline_treadmill"
    case outdoorRun = "outdoor_run"
    case outdoorWalk = "outdoor_walk"
    case stairmaster
    case bike
    case elliptical
    case rowing
    case swimming
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .treadmill: return "Treadmill"
        case .inclineTreadmill: return "Incline Walk"
        case .outdoorRun: return "Run"
        case .outdoorWalk: return "Walk"
        case .stairmaster: return "Stairmaster"
        case .bike: return "Bike"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .swimming: return "Swimming"
        case .other: return "Other"
        }
    }

    /// Whether this type involves a stepping gait that a phone/watch step
    /// counter would pick up - these are the types worth asking for
    /// steps-before/after so that count can be excluded from the day's
    /// step total. Bike/elliptical/rowing/swimming don't generate steps.
    var involvesSteps: Bool {
        switch self {
        case .treadmill, .inclineTreadmill, .outdoorRun, .outdoorWalk, .stairmaster: return true
        case .bike, .elliptical, .rowing, .swimming, .other: return false
        }
    }
}
