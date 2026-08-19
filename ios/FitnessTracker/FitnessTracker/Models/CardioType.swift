import Foundation

enum CardioType: String, CaseIterable, Identifiable, Codable {
    case treadmill
    case outdoorRun = "outdoor_run"
    case outdoorWalk = "outdoor_walk"
    case bike
    case elliptical
    case rowing
    case swimming
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .treadmill: return "Treadmill"
        case .outdoorRun: return "Outdoor Run"
        case .outdoorWalk: return "Outdoor Walk"
        case .bike: return "Bike"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .swimming: return "Swimming"
        case .other: return "Other"
        }
    }
}
