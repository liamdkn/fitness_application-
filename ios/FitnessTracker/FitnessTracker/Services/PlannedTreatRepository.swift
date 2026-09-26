import Foundation
import Supabase

struct PlannedTreatRepository {
    let client = SupabaseService.shared.client

    private struct NewPlannedTreat: Encodable {
        let user_id: UUID
        let date: String
        let meal_slot_id: UUID?
        let label: String
        let extra_calories: Double
        let extra_protein_g: Double
        let extra_carbs_g: Double
        let extra_fat_g: Double
    }

    /// Every treat in an inclusive date range - a whole calendar week's
    /// worth at a time, since that's the unit `CalorieBankCalculator`
    /// redistributes across.
    func fetchTreats(from: Date, to: Date) async throws -> [PlannedTreat] {
        try await client
            .from("planned_treats")
            .select()
            .gte("date", value: DateFormatting.isoDate(from))
            .lte("date", value: DateFormatting.isoDate(to))
            .order("date")
            .execute()
            .value
    }

    @discardableResult
    func createTreat(
        date: Date,
        mealSlotId: UUID?,
        label: String,
        extraCalories: Double,
        extraProteinG: Double,
        extraCarbsG: Double,
        extraFatG: Double
    ) async throws -> PlannedTreat {
        let userId = try await client.auth.session.user.id
        let inserted: [PlannedTreat] = try await client
            .from("planned_treats")
            .insert(NewPlannedTreat(
                user_id: userId,
                date: DateFormatting.isoDate(date),
                meal_slot_id: mealSlotId,
                label: label,
                extra_calories: extraCalories,
                extra_protein_g: extraProteinG,
                extra_carbs_g: extraCarbsG,
                extra_fat_g: extraFatG
            ))
            .select()
            .execute()
            .value
        guard let treat = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return treat
    }

    func deleteTreat(id: UUID) async throws {
        try await client
            .from("planned_treats")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
