import SwiftUI

/// Weigh ingredients one after another into a meal: pick what you're adding,
/// pour, and when the weight settles it's logged - "50 g oats added" - then
/// pick the next and carry on without tapping the scale. The amount added is
/// the change on the scale, so there's no need to tare between ingredients.
struct LiveWeighView: View {
    /// One ingredient of a meal being assembled, with the amount to weigh.
    struct PlannedItem: Identifiable {
        let id = UUID()
        let food: Food
        let targetGrams: Double
        var weighedGrams: Double?
    }

    let mealSlotName: String
    /// Logs a food at a number of servings (grams / serving size).
    let onLog: (Food, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale = BluetoothScale.shared
    @State private var engine = LiveWeighEngine()
    @State private var currentFood: Food?
    @State private var pendingGrams: Double?
    @State private var showingFoodPicker = false
    @State private var added: [(food: Food, grams: Double)] = []
    @State private var message: String?
    @State private var liveGrams: Double = 0
    /// Assembly mode: the ingredients of a saved meal, weighed in order.
    @State private var plan: [PlannedItem] = []
    @State private var showingSavedMeals = false
    private let foodRepository = FoodRepository()
    /// Weighing out of a container: the amount that comes off is what's logged.
    @State private var scoopMode = false
    /// 0...1 fill of the press-and-hold "Confirm & Next" button.
    @State private var holdProgress: Double = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 4) {
                        Text("\(AmountLabel.trimmed(scale.live ?? liveGrams)) g")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(scale.connectedName.map { "Connected to \($0)" } ?? "No scale connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    if scale.connectedName == nil {
                        NavigationLink("Set Up the Scale") { ScaleSetupView() }
                    }
                }
                .listRowBackground(AppRowBackground())

                if !plan.isEmpty {
                    Section {
                        ForEach(Array(plan.enumerated()), id: \.element.id) { index, item in
                            HStack {
                                Image(systemName: item.weighedGrams != nil ? "checkmark.circle.fill" : (index == planIndex ? "circle.inset.filled" : "circle"))
                                    .foregroundStyle(item.weighedGrams != nil ? AppColor.success : (index == planIndex ? AppColor.accent : .secondary))
                                Text(item.food.name)
                                    .fontWeight(index == planIndex ? .semibold : .regular)
                                Spacer()
                                if let weighed = item.weighedGrams {
                                    Text("\(AmountLabel.trimmed(weighed)) \(item.food.servingUnit)")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(AmountLabel.trimmed(item.targetGrams)) \(item.food.servingUnit)").foregroundStyle(.secondary)
                                }
                            }
                        }
                        if planIndex < plan.count {
                            Button("Skip \(plan[planIndex].food.name)") { skipPlanned() }
                            HoldToConfirmButton(title: "Confirm & Next", progress: $holdProgress) { confirmAndAdvance() }
                        }
                    } header: {
                        Text("Building the meal")
                    } footer: {
                        Text(planIndex < plan.count
                             ? "Pour \(plan[planIndex].food.name) - aim for \(AmountLabel.trimmed(plan[planIndex].targetGrams)) \(plan[planIndex].food.servingUnit). It moves to the next ingredient when the weight settles. For a tiny amount that doesn't register, hold Confirm & Next."
                             : "Every ingredient is in.")
                    }
                    .listRowBackground(AppRowBackground())
                }

                Section {
                    Button {
                        showingFoodPicker = true
                    } label: {
                        HStack {
                            Text(currentFood?.name ?? "Choose what you're adding")
                                .foregroundStyle(currentFood == nil ? AppColor.accent : .primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    Toggle("Scooping from a container", isOn: $scoopMode)
                    if let pendingGrams {
                        Text("\(AmountLabel.trimmed(pendingGrams)) g on the scale is waiting - choose what it is.")
                            .font(.caption)
                            .foregroundStyle(AppColor.warning)
                        Button("Skip this amount") {
                            self.pendingGrams = nil
                            message = "Skipped \(AmountLabel.trimmed(pendingGrams)) g - not logged."
                        }
                    }
                } header: {
                    Text("Adding now")
                } footer: {
                    Text(scoopMode
                         ? "Leave the container on the scale and spoon some out. The amount that comes off is logged when the weight settles."
                         : currentFood == nil
                             ? "Pick the ingredient, then pour. It's logged when the weight settles."
                             : "Pour in \(currentFood?.name ?? "it"). It's logged when the weight settles.")
                }
                .listRowBackground(AppRowBackground())

                if let message {
                    Section { Text(message).font(.subheadline) }
                        .listRowBackground(AppRowBackground())
                }

                if !added.isEmpty {
                    Section("Added to \(mealSlotName)") {
                        ForEach(Array(added.enumerated()), id: \.offset) { _, item in
                            LabeledContent(item.food.name, value: "\(AmountLabel.trimmed(item.grams)) \(item.food.servingUnit)")
                        }
                    }
                    .listRowBackground(AppRowBackground())
                }

                Section {
                    Button(plan.isEmpty ? "Build a saved meal" : "Pick a different saved meal") { showingSavedMeals = true }
                    Button("Tare") {
                        engine.rebase(to: 0)
                        message = "Tared."
                    }
                }
                .listRowBackground(AppRowBackground())
            }
            .appScreen()
            .navigationTitle("Weigh Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.appToolbarTint()
                }
            }
            .sheet(isPresented: $showingFoodPicker) {
                NavigationStack {
                    FoodDatabaseView(onSelect: { food in choose(food) })
                }
            }
            .sheet(isPresented: $showingSavedMeals) {
                SavedMealPickerView(mealSlotName: mealSlotName) { items in
                    Task { await loadPlan(items) }
                }
            }
            .sensoryFeedback(.success, trigger: added.count)
            .onChange(of: scoopMode) { _, on in
                // Whatever is on the scale now (the full tub) is the new starting
                // point, so switching mode never logs the container itself.
                engine.rebase(to: scale.live ?? liveGrams)
                pendingGrams = nil
                message = on ? "Scoop mode on - counting what comes off." : "Back to pouring in."
            }
            .onAppear {
                scale.reconnectKnown()
                scale.onReading = { grams in receive(grams) }
                if let grams = scale.grams { liveGrams = grams }
            }
            .onDisappear { scale.onReading = nil }
        }
    }

    // MARK: Readings

    private func receive(_ grams: Double) {
        liveGrams = grams
        guard let event = engine.ingest(grams: grams, at: Date()) else { return }
        switch event {
        case .added(let amount):
            if scoopMode {
                message = "Weight went up, not down - ignored."
            } else {
                claim(amount, verb: "added")
            }
        case .removed(let amount):
            if scoopMode {
                claim(amount, verb: "scooped out")
            } else {
                message = "\(AmountLabel.trimmed(amount)) g taken off - not logged."
            }
        case .reset:
            message = "Scale cleared. Counting from zero."
            pendingGrams = nil
        }
    }

    /// A settled change: logged against the chosen food, or held until one is chosen.
    private func claim(_ amount: Double, verb: String) {
        if let food = currentFood {
            log(food, grams: amount)
        } else {
            pendingGrams = amount
            message = "\(AmountLabel.trimmed(amount)) g \(verb) - choose what it is."
        }
    }

    /// First ingredient of the plan that hasn't been weighed or skipped.
    private var planIndex: Int {
        plan.firstIndex { $0.weighedGrams == nil } ?? plan.count
    }

    private func loadPlan(_ items: [SavedMealItem]) async {
        do {
            let foods = try await foodRepository.fetchByIds(items.compactMap(\.foodId))
            var planned: [PlannedItem] = []
            var skipped = 0
            for item in items {
                guard let id = item.foodId, let food = foods.first(where: { $0.id == id }) else { skipped += 1; continue }
                let unit = food.servingUnit.lowercased()
                guard unit == "g" || unit == "ml", food.servingSize > 0 else { skipped += 1; continue }
                planned.append(PlannedItem(food: food, targetGrams: item.quantity * food.servingSize))
            }
            plan = planned
            currentFood = nil
            engine.rebase(to: scale.live ?? liveGrams)
            message = skipped > 0 ? "\(skipped) item\(skipped == 1 ? "" : "s") can't be weighed (recipes or foods not counted in grams) - log those by hand." : nil
            announceNext()
        } catch {
            message = error.localizedDescription
        }
    }

    private func announceNext() {
        guard planIndex < plan.count else { return }
        let next = plan[planIndex]
        currentFood = next.food
    }

    /// The hold is the confirmation: take whatever is on the scale beyond what's
    /// already counted - however small, even nothing - as this ingredient, skipping
    /// the settle and minimum-change checks, and move on.
    private func confirmAndAdvance() {
        guard planIndex < plan.count else { return }
        let item = plan[planIndex]
        let current = scale.live ?? liveGrams
        let delta = max(0, ((current - engine.committed) * 10).rounded() / 10)
        pendingGrams = nil
        if delta > 0 {
            log(item.food, grams: delta)
        } else {
            // Confirmed as negligible: counted as zero, nothing to log.
            plan[planIndex].weighedGrams = 0
            message = "Confirmed - no \(item.food.name) counted."
            announceNext()
        }
        engine.rebase(to: current)
    }

    private func skipPlanned() {
        guard planIndex < plan.count else { return }
        // A zero marks it done without logging anything.
        plan[planIndex].weighedGrams = 0
        announceNext()
    }

    private func choose(_ food: Food) {
        currentFood = food
        if let grams = pendingGrams {
            pendingGrams = nil
            log(food, grams: grams)
        }
    }

    private func log(_ food: Food, grams: Double) {
        let unit = food.servingUnit.lowercased()
        guard (unit == "g" || unit == "ml"), food.servingSize > 0 else {
            message = "\(food.name) is counted in \(food.servingUnit), not grams - log it by hand."
            return
        }
        onLog(food, grams / food.servingSize)
        added.append((food, grams))
        message = "\(AmountLabel.trimmed(grams)) \(food.servingUnit) \(food.name) added"
        // Ready for the next ingredient.
        currentFood = nil
        if let index = plan.firstIndex(where: { $0.weighedGrams == nil && $0.food.id == food.id }) {
            plan[index].weighedGrams = grams
            announceNext()
        }
    }
}

/// A press-and-hold button: the fill tracks the hold and the action only fires
/// after the full three seconds, so it can't be set off by a stray tap.
private struct HoldToConfirmButton: View {
    let title: String
    @Binding var progress: Double
    let action: () -> Void

    @State private var fired = 0

    var body: some View {
        Text(title)
            .foregroundStyle(AppColor.accent)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(AppColor.accent.opacity(0.25))
                        .frame(width: proxy.size.width * progress)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 3, maximumDistance: 40, perform: {
                fired += 1
                action()
                progress = 0
            }, onPressingChanged: { pressing in
                if pressing {
                    withAnimation(.linear(duration: 3)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            })
            .sensoryFeedback(.success, trigger: fired)
            .accessibilityLabel(title)
            .accessibilityHint("Press and hold for three seconds")
    }
}
