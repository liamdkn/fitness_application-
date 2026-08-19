import Foundation

enum StepSource: String, Codable, CaseIterable, Identifiable {
    case merged
    case appleWatch = "apple_watch"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .merged: return "Merged (Health App)"
        case .appleWatch: return "Apple Watch Only"
        }
    }
}
