import Foundation

struct WeeklyCheckin: Codable, Identifiable {
    let id: UUID
    let checkinDate: String
    let goalId: UUID?
    let weekNumber: Int?
    let overallRating7d: Int?
    let weightKg: Double?
    let energyLevel: Int?
    let sorenessLevel: Int?
    let stressLevel: Int?
    let stressReason: String?
    let biggestWin: String?
    let moodNotes: String?
    let overallAdherence: Int?
    let trainingAdherence: Int?
    let nutritionAdherence: Int?
    let disciplineLevel: Int?
    let upcomingDistractions: String?

    enum CodingKeys: String, CodingKey {
        case id
        case checkinDate = "checkin_date"
        case goalId = "goal_id"
        case weekNumber = "week_number"
        case overallRating7d = "overall_rating_7d"
        case weightKg = "weight_kg"
        case energyLevel = "energy_level"
        case sorenessLevel = "soreness_level"
        case stressLevel = "stress_level"
        case stressReason = "stress_reason"
        case biggestWin = "biggest_win"
        case moodNotes = "mood_notes"
        case overallAdherence = "overall_adherence"
        case trainingAdherence = "training_adherence"
        case nutritionAdherence = "nutrition_adherence"
        case disciplineLevel = "discipline_level"
        case upcomingDistractions = "upcoming_distractions"
    }
}
