import SwiftUI

/// Log anything you drink. Plain water goes in by container or amount; every
/// other drink - a Pepsi, a Monster, a pot of coffee - is a food measured in
/// ml, found by scanning its barcode, searching, or picking one you've saved.
/// A drink is logged as a normal meal entry (into the Drinks slot), so its
/// calories, sugar and sodium count once in the day's totals, and hydration
/// and caffeine are read from the same entries. "Edit" manages the water
/// containers (`WaterContainersEditView`).
struct LiquidsLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var containers: [WaterContainer] = []
    @State private var day = LiquidsDay()
    @State private var quickDrinks: [Food] = []
    @State private var preferences: UserPreferences?
    @State private var customAmountText = ""
    @State private var errorMessage: String?
    @State private var showingEditContainers = false
    @State private var showingDrinkPicker = false
    @State private var showingNewDrink = false
    @State private var showingCoffeeSetup = false
    @State private var pendingDrink: Food?
    private let waterRepository = WaterRepository()
    private let liquidsRepository = LiquidsRepository()
    private let preferencesRepository = UserPreferencesRepository()

    private var halfLife: Double { preferences?.caffeineHalfLifeHours ?? 5 }
    private var caffeineLimit: Int { preferences?.caffeineLimitMg ?? 400 }
    /// What "a glass" means for catch-up advice: a container called glass, or 250 ml.
    private var glassMl: Int { containers.first { $0.name.localizedCaseInsensitiveContains("glass") }?.volumeMl ?? 250 }

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                WaterPaceSection(day: day, preferences: preferences, glassMl: glassMl)
                waterSection
                drinksSection
                customAmountSection
                todaySection

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle("Liquids")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") { showingEditContainers = true }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                    .appToolbarTint()
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingEditContainers, onDismiss: { Task { await loadContainers() } }) {
                NavigationStack {
                    WaterContainersEditView()
                }
            }
            .sheet(isPresented: $showingDrinkPicker) {
                FoodPickerView(mealSlotName: "Drinks", onLog: { food, quantity in
                    Task { await logDrink(food, quantity: quantity) }
                }, drinksOnly: true)
            }
            .sheet(isPresented: $showingNewDrink) {
                AddCustomFoodView(onCreated: { food in pendingDrink = food }, initialServingUnit: "ml", initialIsDrink: true)
            }
            .sheet(isPresented: $showingCoffeeSetup) {
                CoffeeSetupSheet { food in
                    pendingDrink = food
                    Task { await loadQuickDrinks() }
                }
            }
            .sheet(item: $pendingDrink) { food in
                LogFoodQuantityView(food: food, mealSlotName: LiquidsRepository.slotName) { confirmed, quantity in
                    pendingDrink = nil
                    Task { await logDrink(confirmed, quantity: quantity) }
                }
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            VStack(spacing: 4) {
                Text(formattedAmount(Int(day.hydrationMl.rounded())))
                    .font(.largeTitle.bold())
                Text("today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)

            NavigationLink {
                CaffeineView()
            } label: {
                HStack {
                    Label("Caffeine", systemImage: "cup.and.saucer.fill")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(day.caffeineMg.rounded())) / \(caffeineLimit) mg")
                            .font(.subheadline.bold())
                            .foregroundStyle(day.caffeineMg > Double(caffeineLimit) ? AppColor.danger : .primary)
                        if day.caffeineMg > 0 {
                            Text("~\(Int(CaffeineModel.level(at: Date(), doses: day.caffeineDoses, halfLifeHours: halfLife).rounded())) mg in you now")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listRowBackground(AppRowBackground())
    }

    private var waterSection: some View {
        Section("Water") {
            if containers.isEmpty {
                Text("Add a container with Edit, or type an amount below.")
                    .foregroundStyle(.secondary)
            }
            ForEach(containers) { container in
                Button {
                    Task { await addWater(amountMl: container.volumeMl, containerId: container.id) }
                } label: {
                    HStack {
                        Text(container.name).foregroundStyle(.primary)
                        Spacer()
                        Text("+\(container.volumeMl) ml").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listRowBackground(AppRowBackground())
    }

    private var drinksSection: some View {
        Section {
            ForEach(quickDrinks) { food in
                Button {
                    pendingDrink = food
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.displayName).foregroundStyle(.primary)
                            Text(detail(for: food))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(AppColor.accent)
                    }
                }
            }
            Button {
                showingDrinkPicker = true
            } label: {
                Label("Scan or Search for a Drink", systemImage: "barcode.viewfinder")
            }
            Button {
                showingCoffeeSetup = true
            } label: {
                Label("Set Up Coffee (Brew Pot or Pod)", systemImage: "cup.and.saucer")
            }
            Button {
                showingNewDrink = true
            } label: {
                Label("New Drink", systemImage: "plus")
            }
            NavigationLink {
                MilkAllowanceView()
            } label: {
                Label("Daily Milk Allowance", systemImage: "cup.and.heat.waves")
            }
        } header: {
            Text("Drinks")
        } footer: {
            Text("A drink counts toward your calories, sodium and caffeine like any food - it's logged to a Drinks meal.")
        }
        .listRowBackground(AppRowBackground())
    }

    private var customAmountSection: some View {
        Section("Custom Water Amount") {
            HStack {
                TextField("e.g. 250", text: $customAmountText)
                    .keyboardType(.numberPad)
                Text("ml").foregroundStyle(.secondary)
                Button("Add") {
                    Task { await addCustomWater() }
                }
                .disabled((Int(customAmountText) ?? 0) <= 0)
            }
        }
        .listRowBackground(AppRowBackground())
    }

    @ViewBuilder
    private var todaySection: some View {
        if !day.items.isEmpty {
            Section("Today") {
                ForEach(day.items) { item in
                    itemRow(item)
                }
                .onDelete(perform: removeItems)
            }
            .listRowBackground(AppRowBackground())
        }
    }

    private func itemRow(_ item: LiquidItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: item))
                Text(item.time.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(item.volumeMl.rounded())) ml").foregroundStyle(.secondary)
                if item.caffeineMg > 0 {
                    Text("\(Int(item.caffeineMg.rounded())) mg caffeine")
                        .font(.caption)
                        .foregroundStyle(AppColor.caffeine)
                }
            }
        }
    }

    // MARK: - Text

    private func title(for item: LiquidItem) -> String {
        switch item.kind {
        case .water(let log):
            return containers.first { $0.id == log.containerId }?.name ?? "Water"
        case .drink(let drink):
            return drink.food.displayName
        }
    }

    private func detail(for food: Food) -> String {
        var parts = ["\(Int(food.calories.rounded())) kcal"]
        if let caffeine = food.caffeineMg, caffeine > 0 { parts.append("\(Int(caffeine.rounded())) mg caffeine") }
        return parts.joined(separator: " \u{00b7} ") + " per \(food.servingLabel)"
    }

    private func formattedAmount(_ ml: Int) -> String {
        ml >= 1000 ? String(format: "%.2f L", Double(ml) / 1000) : "\(ml) ml"
    }

    // MARK: - Loading and actions

    private func load() async {
        await MilkAllowanceService.applyIfNeeded()
        async let prefs = try? preferencesRepository.fetch()
        await loadContainers()
        await loadDay()
        await loadQuickDrinks()
        preferences = await prefs
    }

    private func loadContainers() async {
        do {
            containers = try await waterRepository.fetchContainers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDay() async {
        do {
            day = try await liquidsRepository.fetchDay(date: Date())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadQuickDrinks() async {
        quickDrinks = await liquidsRepository.fetchQuickDrinks()
    }

    private func addWater(amountMl: Int, containerId: UUID?) async {
        do {
            try await waterRepository.addLog(date: Date(), amountMl: amountMl, containerId: containerId)
            errorMessage = nil
            await loadDay()
            await WidgetSnapshotService.shared.refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addCustomWater() async {
        guard let amount = Int(customAmountText), amount > 0 else { return }
        customAmountText = ""
        await addWater(amountMl: amount, containerId: nil)
    }

    private func logDrink(_ food: Food, quantity: Double) async {
        do {
            let slot = try await liquidsRepository.drinksSlot()
            try OfflineMealQueue.shared.addFoodEntry(date: Date(), mealSlotId: slot.id, foodId: food.id, quantity: quantity)
            errorMessage = nil
            await loadDay()
            await loadQuickDrinks()
            await CaffeineReminderService.shared.refresh()
            await WidgetSnapshotService.shared.refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeItems(at offsets: IndexSet) {
        let items = day.items
        let toRemove = offsets.map { items[$0] }
        Task {
            for item in toRemove {
                do {
                    switch item.kind {
                    case .water(let log): try await waterRepository.deleteLog(id: log.id)
                    case .drink(let drink): try await OfflineMealQueue.shared.deleteEntry(id: drink.entry.id)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            await loadDay()
            await CaffeineReminderService.shared.refresh()
            await WidgetSnapshotService.shared.refresh(force: true)
        }
    }
}
