import Foundation

/// A drink logged as a normal meal entry: a food measured in ml.
struct DrinkEntry: Identifiable {
    let entry: MealEntry
    let food: Food

    var id: UUID { entry.id }
    var volumeMl: Double { food.volumeMl(at: entry.quantity) ?? 0 }
    var caffeineMg: Double { food.caffeineMg(at: entry.quantity) ?? 0 }
    var calories: Double { food.calories(at: entry.quantity) }
    var sodiumMg: Double { food.sodiumMg(at: entry.quantity) ?? 0 }
}

/// One row of the Liquids timeline - plain water or a drink.
struct LiquidItem: Identifiable {
    enum Kind {
        case water(WaterLog)
        case drink(DrinkEntry)
    }

    let kind: Kind

    var id: UUID {
        switch kind {
        case .water(let log): log.id
        case .drink(let drink): drink.id
        }
    }

    var time: Date {
        switch kind {
        case .water(let log): log.loggedAt
        case .drink(let drink): drink.entry.loggedAt
        }
    }

    var volumeMl: Double {
        switch kind {
        case .water(let log): Double(log.amountMl)
        case .drink(let drink): drink.volumeMl
        }
    }

    var caffeineMg: Double {
        switch kind {
        case .water: 0
        case .drink(let drink): drink.caffeineMg
        }
    }
}

/// One day of liquids: water logged directly plus every drink logged as food.
/// Hydration counts both (a coffee or a Pepsi is still fluid); caffeine and
/// calories come only from the drinks.
struct LiquidsDay {
    var waterLogs: [WaterLog] = []
    var drinks: [DrinkEntry] = []

    var items: [LiquidItem] {
        (waterLogs.map { LiquidItem(kind: .water($0)) } + drinks.map { LiquidItem(kind: .drink($0)) })
            .sorted { $0.time > $1.time }
    }

    var hydrationMl: Double { waterLogs.reduce(0) { $0 + Double($1.amountMl) } + drinks.reduce(0) { $0 + $1.volumeMl } }
    var caffeineMg: Double { drinks.reduce(0) { $0 + $1.caffeineMg } }
    var caffeineDoses: [CaffeineModel.Dose] {
        drinks.filter { $0.caffeineMg > 0 }.map { CaffeineModel.Dose(time: $0.entry.loggedAt, mg: $0.caffeineMg) }
    }
}

struct LiquidsRepository {
    private let waterRepository = WaterRepository()
    private let mealEntryRepository = MealEntryRepository()
    private let foodRepository = FoodRepository()
    private let slotsRepository = MealSlotsRepository()

    /// Name of the meal slot drinks are logged into - created the first time
    /// a drink is logged, so a drink shows up as its own card on the
    /// Nutrition tab and counts toward the day's calories like any food.
    static let slotName = "Drinks"

    @MainActor
    func fetchDay(date: Date) async throws -> LiquidsDay {
        async let waterResult = waterRepository.fetchLogs(date: date)
        let entries = try await OfflineMealQueue.shared.fetchEntries(date: date)
        let foodIds = Array(Set(entries.compactMap(\.foodId)))
        let foods = Dictionary(uniqueKeysWithValues: try await foodRepository.fetchByIds(foodIds).map { ($0.id, $0) })
        let drinks = entries.compactMap { entry -> DrinkEntry? in
            guard let food = entry.foodId.flatMap({ foods[$0] }), food.isDrink else { return nil }
            return DrinkEntry(entry: entry, food: food)
        }
        return LiquidsDay(waterLogs: try await waterResult, drinks: drinks)
    }

    /// The Drinks slot, created at the end of the user's slots if missing.
    func drinksSlot() async throws -> MealSlot {
        let slots = try await slotsRepository.fetchAll()
        if let existing = slots.first(where: { $0.name.lowercased() == Self.slotName.lowercased() }) {
            return existing
        }
        return try await slotsRepository.add(name: Self.slotName)
    }

    /// Drinks to offer for a quick log: the user's own saved drinks (a brew
    /// pot, a pod coffee) and whatever drinks they've logged lately, newest
    /// first, without repeats.
    func fetchQuickDrinks(limit: Int = 8) async -> [Food] {
        let recentIds = (try? await mealEntryRepository.fetchRecentlyLoggedFoodIds(limit: 30)) ?? []
        let recent = (try? await foodRepository.fetchByIds(recentIds)) ?? []
        let recentById = Dictionary(uniqueKeysWithValues: recent.map { ($0.id, $0) })
        var ordered = recentIds.compactMap { recentById[$0] }.filter(\.isDrink)
        let mine = (try? await foodRepository.fetchCustomDrinks()) ?? []
        for food in mine where !ordered.contains(where: { $0.id == food.id }) { ordered.append(food) }
        return Array(ordered.prefix(limit))
    }

    /// Daily caffeine totals for a range - what the history chart plots.
    @MainActor
    func fetchCaffeineByDay(from: Date, to: Date) async throws -> [String: Double] {
        let entries = try await mealEntryRepository.fetchEntries(from: from, to: to)
        let foodIds = Array(Set(entries.compactMap(\.foodId)))
        let foods = Dictionary(uniqueKeysWithValues: try await NutritionRepository.fetchInChunks(foodIds) { try await foodRepository.fetchByIds($0) }.map { ($0.id, $0) })
        var totals: [String: Double] = [:]
        for entry in entries {
            guard let mg = entry.foodId.flatMap({ foods[$0] })?.caffeineMg(at: entry.quantity), mg > 0 else { continue }
            totals[entry.date, default: 0] += mg
        }
        return totals
    }

    /// Every dose in a range with its time - for the typical-dose figure.
    @MainActor
    func fetchRecentDoses(days: Int) async -> [Double] {
        let from = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        guard let entries = try? await mealEntryRepository.fetchEntries(from: from, to: Date()) else { return [] }
        let foodIds = Array(Set(entries.compactMap(\.foodId)))
        guard let foods = try? await NutritionRepository.fetchInChunks(foodIds, { try await foodRepository.fetchByIds($0) }) else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        return entries.compactMap { entry in
            entry.foodId.flatMap { byId[$0] }?.caffeineMg(at: entry.quantity)
        }.filter { $0 > 0 }
    }
}
