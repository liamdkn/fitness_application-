import Foundation
import Testing
@testable import FitnessTracker

/// The maths the app's numbers rest on. These are pure functions, so they run
/// instantly and never touch the network.
struct MacroEnergyTests {
    @Test func macrosThatAddUpAreConsistent() {
        // 30 P + 50 C + 10 F = 120 + 200 + 90 = 410 kcal
        let check = MacroEnergy.check(calories: 410, protein: 30, carbs: 50, fat: 10)
        #expect(check.isConsistent)
        #expect(abs(check.unassignedKcal) < 0.001)
    }

    @Test func missingMacroShowsAsUnassignedCalories() {
        let check = MacroEnergy.check(calories: 1000, protein: 16, carbs: 0, fat: 0)
        #expect(!check.isConsistent)
        #expect(check.unassignedKcal == 1000 - 64)
    }

    @Test func labelToleranceIsLooserThanStrict() {
        let strict = MacroEnergy.check(calories: 450, protein: 30, carbs: 50, fat: 10, tolerance: .strict)
        let label = MacroEnergy.check(calories: 450, protein: 30, carbs: 50, fat: 10, tolerance: .label)
        #expect(!strict.isConsistent)
        #expect(label.isConsistent)
    }
}

struct MealFitterTests {
    typealias M = MealFitter.Macros

    @Test func solvesProteinCarbAndFatTargetsTogether() {
        // Per 100 g: chicken 31P/3.6F, rice 2.7P/28C/0.3F, oil 100F.
        let chicken = MealFitter.Line(perServing: M(calories: 165, protein: 31, carbs: 0, fat: 3.6), servings: 1.5)
        let rice = MealFitter.Line(perServing: M(calories: 130, protein: 2.7, carbs: 28, fat: 0.3), servings: 1.5)
        let oil = MealFitter.Line(perServing: M(calories: 884, protein: 0, carbs: 0, fat: 100), servings: 0.1)
        let scale = MealFitter.fit(
            protein: [chicken], carbs: [rice], fat: [oil], fixed: [],
            targets: .init(protein: 50, carbs: 80, fat: 15)
        )
        let protein = 31 * 1.5 * scale.protein + 2.7 * 1.5 * scale.carbs
        let carbs = 28 * 1.5 * scale.carbs
        let fat = 3.6 * 1.5 * scale.protein + 0.3 * 1.5 * scale.carbs + 100 * 0.1 * scale.fat
        #expect(abs(protein - 50) < 0.1)
        #expect(abs(carbs - 80) < 0.1)
        #expect(abs(fat - 15) < 0.1)
    }

    @Test func leavesAGroupAloneWithoutATarget() {
        let rice = MealFitter.Line(perServing: M(calories: 130, protein: 2.7, carbs: 28, fat: 0.3), servings: 1)
        let scale = MealFitter.fit(protein: [], carbs: [rice], fat: [], fixed: [], targets: .init(protein: nil, carbs: nil, fat: nil))
        #expect(scale.carbs == 1)
    }

    @Test func sizesAreNeverNegative() {
        // Fixed foods already overshoot the carb target.
        let rice = MealFitter.Line(perServing: M(calories: 130, protein: 2.7, carbs: 28, fat: 0.3), servings: 1)
        let bread = MealFitter.Line(perServing: M(calories: 265, protein: 9, carbs: 49, fat: 3), servings: 3)
        let scale = MealFitter.fit(protein: [], carbs: [rice], fat: [], fixed: [bread], targets: .init(protein: nil, carbs: 50, fat: nil))
        #expect(scale.carbs >= 0)
    }
}

struct PreworkoutCarbsTests {
    @Test func targetIsGramsPerKgOfBodyweight() {
        #expect(PreworkoutCarbs.targetG(weightKg: 71.1, gramsPerKg: 1.0) == 71)
        #expect(PreworkoutCarbs.targetG(weightKg: 80, gramsPerKg: 1.5) == 120)
    }

    @Test func noTargetWithoutWeightOrWhenTurnedOff() {
        #expect(PreworkoutCarbs.targetG(weightKg: nil, gramsPerKg: 1) == nil)
        #expect(PreworkoutCarbs.targetG(weightKg: 80, gramsPerKg: 0) == nil)
    }
}

struct WaterPaceTests {
    @Test func paceClimbsStraightFromWakeToTheEndOfTheDay() {
        let wake = 7 * 60, end = 19 * 60
        #expect(WaterPace.expectedMl(atMinute: wake, wakeMinutes: wake, endMinutes: end, targetMl: 3000) == 0)
        #expect(WaterPace.expectedMl(atMinute: 13 * 60, wakeMinutes: wake, endMinutes: end, targetMl: 3000) == 1500)
        #expect(WaterPace.expectedMl(atMinute: 22 * 60, wakeMinutes: wake, endMinutes: end, targetMl: 3000) == 3000)
    }

    @Test func catchUpIsAtLeastOneGlass() {
        #expect(WaterPace.glassesToCatchUp(behindMl: 40, glassMl: 250) == 1)
        #expect(WaterPace.glassesToCatchUp(behindMl: 600, glassMl: 250) == 3)
    }
}

struct CheckinGapsTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ iso: String) -> Date { DateFormatting.date(fromISODate: iso)! }

    @Test func countsConsecutiveMissedDaysBackFromYesterday() {
        let logged: Set<String> = ["2026-09-28", "2026-09-29"]
        // Today is 2 Oct: 1 Oct and 30 Sep are empty, 29 Sep has an entry.
        #expect(CheckinGaps.consecutiveMissed(logged: logged, today: date("2026-10-02")) == 2)
    }

    @Test func todayDoesNotCountAsMissed() {
        #expect(CheckinGaps.consecutiveMissed(logged: ["2026-10-01"], today: date("2026-10-02")) == 0)
    }

    @Test func findsTheGapBetweenTwoWeighIns() {
        let gap = CheckinGaps.gap(between: date("2026-09-20"), and: date("2026-09-24"))
        #expect(gap?.days == 3)
        #expect(CheckinGaps.gap(between: date("2026-09-20"), and: date("2026-09-21")) == nil)
    }
}

struct BedtimeAndCaffeineTests {
    @Test func smallHoursCountAsTheSameNight() {
        // 00:30 sorts after 23:30, so the typical bedtime isn't dragged to noon.
        let night = [23 * 60 + 30, 24 * 60 + 30, 23 * 60 + 45, 24 * 60 + 10]
        let typical = BedtimeEstimate.typicalBedtime(nightMinutes: night)
        #expect(typical != nil)
        #expect(typical! < 60 || typical! > 23 * 60)
    }

    @Test func needsAFewNightsBeforeCallingItAPattern() {
        #expect(BedtimeEstimate.typicalBedtime(nightMinutes: [1380, 1400]) == nil)
    }

    @Test func caffeineHalvesEveryHalfLife() {
        let now = Date()
        let dose = CaffeineModel.Dose(time: now.addingTimeInterval(-5 * 3600), mg: 200)
        let level = CaffeineModel.level(at: now, doses: [dose], halfLifeHours: 5)
        #expect(abs(level - 100) < 0.001)
    }

    @Test func aFutureDoseHasNotHappenedYet() {
        let now = Date()
        let dose = CaffeineModel.Dose(time: now.addingTimeInterval(3600), mg: 200)
        #expect(CaffeineModel.level(at: now, doses: [dose], halfLifeHours: 5) == 0)
    }
}

struct FoodAndRunFormattingTests {
    @Test func measuredFoodsShowRealAmounts() {
        #expect(AmountLabel.text(quantity: 0.8, servingSize: 100, servingUnit: "g", servingLabel: "100g") == "80g")
        #expect(AmountLabel.text(quantity: 2, servingSize: 1, servingUnit: "egg", servingLabel: "1egg") == "2 egg")
    }

    @Test func proteinHeavyFoodsAreProteinSources() {
        let roles = FoodCategory.suggested(calories: 165, proteinG: 31, carbsG: 0, fatG: 3.6)
        #expect(roles == [.protein])
    }

    @Test func salmonIsBothProteinAndFat() {
        let roles = FoodCategory.suggested(calories: 208, proteinG: 20, carbsG: 0, fatG: 13)
        #expect(roles.contains(.protein) && roles.contains(.fat))
    }

    @Test func pacesParseAndFormatAsMinutesAndSeconds() {
        #expect(PaceText.parse("5:30") == 330)
        #expect(PaceText.parse("5.5") == nil)
        #expect(PaceText.parse("0:30") == nil)
        #expect(PaceText.format(330) == "5:30/km")
    }
}
