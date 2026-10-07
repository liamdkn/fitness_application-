import SwiftUI

/// Weigh food into a meal with the Bluetooth scale, two ways:
///
/// - **Open weigh**: pick what you're adding, pour, and press TARE on the scale
///   to log it - or scoop out of a container and hold the button to log what
///   came out. Nothing is planned; you say what each amount was.
/// - **Goal weigh**: a list of ingredients with target amounts (a saved meal, or
///   ingredients you add). Pour towards the target, watch the gauge, and press
///   TARE to capture the *actual* weight - 50.1, 50 or 50.7.
///
/// Nothing is ever logged by the scale settling: pouring little by little is
/// safe, and only TARE (or holding the on-screen button) says "that's the
/// amount". TARE also zeroes the scale, ready for the next ingredient. Amounts
/// are recorded in the food's own unit (g or ml).
struct LiveWeighView: View {
    enum WeighMode: String {
        case open, goal
    }

    /// One ingredient of a goal weigh. Amounts are in the food's own unit.
    struct PlannedItem: Identifiable {
        let id = UUID()
        let food: Food
        let target: Double
        var weighed: Double?
    }

    private enum PickPurpose {
        case open, goalTarget
    }

    let mealSlotName: String
    /// Logs a food at a number of servings (amount / serving size).
    let onLog: (Food, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale = BluetoothScale.shared
    @AppStorage("scale-weigh-mode") private var modeRaw = WeighMode.open.rawValue
    @State private var currentFood: Food?
    @State private var pendingGrams: Double?
    @State private var showingFoodPicker = false
    @State private var pickPurpose: PickPurpose = .open
    @State private var added: [(food: Food, amount: Double)] = []
    @State private var message: String?
    @State private var liveGrams: Double = 0
    /// Open weigh: weighing out of a container - the amount that comes out is logged.
    @State private var scoopMode = false
    /// What was on the scale when counting started (the bowl, the full tub), in grams.
    @State private var baseline: Double = 0
    /// False until the bowl is on and the scale zeroed (or already holding something),
    /// so the first TARE - which zeroes the bowl - isn't taken as an ingredient.
    @State private var ready = false
    /// Goal weigh: the ingredients.
    @State private var plan: [PlannedItem] = []
    @State private var showingSavedMeals = false
    @State private var targetFood: Food?
    @State private var askingTarget = false
    @State private var targetText = ""
    /// 0...1 fill of the press-and-hold log button.
    @State private var holdProgress: Double = 0
    private let foodRepository = FoodRepository()

    private var mode: WeighMode { WeighMode(rawValue: modeRaw) ?? .open }

    /// Mass on the scale right now, in grams - the scale reports mass in every display unit.
    private var currentMass: Double { scale.live ?? liveGrams }

    /// First ingredient of the plan that hasn't been weighed or skipped.
    private var planIndex: Int { plan.firstIndex { $0.weighed == nil } ?? plan.count }
    private var goalItem: PlannedItem? { planIndex < plan.count ? plan[planIndex] : nil }

    private var activeFood: Food? { mode == .goal ? goalItem?.food : currentFood }

    /// Converts mass to the unit a food is counted in (ml uses the scale's milk setting).
    private func amount(_ mass: Double, in food: Food) -> Double {
        ScaleDecoding.amount(forGrams: mass, foodUnit: food.servingUnit, scaleUnit: scale.unit) ?? mass
    }

    /// Mass added (or, when scooping, taken out) since counting started, in grams.
    private func massSinceBaseline(from reading: Double) -> Double {
        max(0, scoopMode && mode == .open ? baseline - reading : reading - baseline)
    }

    /// Added so far for the current goal ingredient, in its own unit.
    private var goalAmount: Double {
        guard let item = goalItem else { return 0 }
        return amount(massSinceBaseline(from: currentMass), in: item.food)
    }

    /// The big number: in ml while a ml food is active, otherwise grams.
    private var bigReading: (value: Double, unit: String) {
        if let food = activeFood, food.servingUnit.lowercased() == "ml" {
            return (amount(currentMass, in: food), "ml")
        }
        return (currentMass, "g")
    }

    var body: some View {
        NavigationStack {
            List {
                readingSection

                Section {
                    Picker("Weigh mode", selection: $modeRaw) {
                        Text("Open weigh").tag(WeighMode.open.rawValue)
                        Text("Goal weigh").tag(WeighMode.goal.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } footer: {
                    Text(mode == .open
                         ? "Open weigh: weigh anything and tell the app what it was. Press TARE on the scale to log each amount."
                         : "Goal weigh: aim for the amounts in a saved meal or ones you set. Press TARE to capture the actual weight.")
                }
                .listRowBackground(AppRowBackground())

                if !ready {
                    Section {
                        Label("Put your bowl on the scale and press TARE to start.", systemImage: "scalemass")
                            .font(.subheadline)
                    } footer: {
                        Text("The first TARE only zeroes the bowl. After that, each TARE logs what you've added.")
                    }
                    .listRowBackground(AppRowBackground())
                }

                if mode == .open { openSection } else { goalSection }

                if let message {
                    Section { Text(message).font(.subheadline) }
                        .listRowBackground(AppRowBackground())
                }

                if !added.isEmpty {
                    Section("Added to \(mealSlotName)") {
                        ForEach(Array(added.enumerated()), id: \.offset) { _, item in
                            LabeledContent(item.food.name, value: "\(AmountLabel.trimmed(item.amount)) \(item.food.servingUnit)")
                        }
                    }
                    .listRowBackground(AppRowBackground())
                }

                Section {
                    Button("Tare") {
                        // Count from whatever is on the scale now (same as pressing TARE on it, without logging).
                        baseline = currentMass
                        ready = true
                        message = "Tared."
                    }
                } footer: {
                    Text("Zeroes the count here without logging anything.")
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
            .sheet(isPresented: $showingFoodPicker, onDismiss: {
                if pickPurpose == .goalTarget, targetFood != nil { askingTarget = true }
            }) {
                NavigationStack {
                    FoodDatabaseView(onSelect: { food in
                        if pickPurpose == .goalTarget {
                            targetFood = food
                            targetText = ""
                        } else {
                            choose(food)
                        }
                    })
                }
            }
            .sheet(isPresented: $showingSavedMeals) {
                SavedMealPickerView(mealSlotName: mealSlotName) { items in
                    Task { await loadPlan(items) }
                }
            }
            .alert("Target amount", isPresented: $askingTarget, presenting: targetFood) { food in
                TextField(food.servingUnit, text: $targetText)
                    .keyboardType(.decimalPad)
                Button("Add") { addTarget(food) }
                Button("Cancel", role: .cancel) { targetFood = nil }
            } message: { food in
                Text("How much \(food.name) are you aiming for, in \(food.servingUnit)?")
            }
            .sensoryFeedback(.success, trigger: added.count)
            .onChange(of: scoopMode) { _, on in
                // Whatever is on the scale now (the full tub) is the starting point.
                restart()
                message = on ? "Scoop mode on - spoon some out, then hold the button to log it." : "Back to pouring in."
            }
            .onChange(of: modeRaw) { _, _ in
                scoopMode = false
                restart()
                message = nil
            }
            .onAppear {
                scale.reconnectKnown()
                scale.onSample = { grams, _ in liveGrams = grams }
                scale.onTare = { massBefore in scaleTared(massBefore: massBefore) }
                if let grams = scale.live ?? scale.grams { liveGrams = grams }
                restart()
            }
            .onDisappear {
                scale.onSample = nil
                scale.onTare = nil
            }
        }
    }

    // MARK: Sections

    private var readingSection: some View {
        Section {
            VStack(spacing: 4) {
                Text("\(AmountLabel.trimmed(bigReading.value)) \(bigReading.unit)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(connectionCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            if scale.connectedName == nil {
                NavigationLink(scale.isPaired ? "Scale Settings" : "Pair the Scale") { ScaleSetupView() }
            }
        }
        .listRowBackground(AppRowBackground())
    }

    private var connectionCaption: String {
        guard let name = scale.connectedName else {
            return scale.isPaired ? "Waiting for the scale - press a button on it" : "No scale paired"
        }
        if let unit = scale.unit, unit != 0 {
            return "Connected to \(name) · scale shows \(ScaleDecoding.unitName(unit))"
        }
        return "Connected to \(name)"
    }

    private var openSection: some View {
        Section {
            Button {
                pickPurpose = .open
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
            if ready {
                let sofar = massSinceBaseline(from: currentMass)
                let unit = currentFood?.servingUnit ?? "g"
                let shown = currentFood.map { amount(sofar, in: $0) } ?? sofar
                LabeledContent(scoopMode ? "Taken out so far" : "Added so far",
                               value: "\(AmountLabel.trimmed(shown)) \(unit)")
                HoldToConfirmButton(title: "Hold to log \(AmountLabel.trimmed(shown)) \(unit)", progress: $holdProgress) {
                    captureOpenByHand()
                }
            }
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
                 ? "Leave the container on the scale and spoon some out. Hold the button to log what came out."
                 : currentFood == nil
                     ? "Pick the ingredient, pour, then press TARE on the scale to log it."
                     : "Pour in \(currentFood?.name ?? "it") as slowly as you like, then press TARE on the scale to log it.")
        }
        .listRowBackground(AppRowBackground())
    }

    @ViewBuilder
    private var goalSection: some View {
        Section {
            ForEach(Array(plan.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Image(systemName: item.weighed != nil ? "checkmark.circle.fill" : (index == planIndex ? "circle.inset.filled" : "circle"))
                        .foregroundStyle(item.weighed != nil ? AppColor.success : (index == planIndex ? AppColor.accent : .secondary))
                    Text(item.food.name)
                        .fontWeight(index == planIndex ? .semibold : .regular)
                    Spacer()
                    if let weighed = item.weighed {
                        Text("\(AmountLabel.trimmed(weighed)) of \(AmountLabel.trimmed(item.target)) \(item.food.servingUnit)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(AmountLabel.trimmed(item.target)) \(item.food.servingUnit)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button(plan.isEmpty ? "Build from a saved meal" : "Switch to a different saved meal") { showingSavedMeals = true }
            Button("Add an ingredient with a target") {
                pickPurpose = .goalTarget
                targetFood = nil
                showingFoodPicker = true
            }
        } header: {
            Text(plan.isEmpty ? "Goal weigh" : "Ingredients")
        } footer: {
            if plan.isEmpty {
                Text("Load a saved meal, or add ingredients one at a time with the amount you're aiming for.")
            } else if goalItem == nil {
                Text("Every ingredient is in.")
            }
        }
        .listRowBackground(AppRowBackground())

        if let item = goalItem {
            Section {
                let status = GoalWeigh.status(amount: goalAmount, target: item.target)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.food.name).font(.headline)
                        Spacer()
                        Text("\(AmountLabel.trimmed(goalAmount)) / \(AmountLabel.trimmed(item.target)) \(item.food.servingUnit)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    ProgressView(value: min(goalAmount, item.target), total: max(item.target, 0.1))
                        .tint(progressColor(status))
                    Text(statusText(status, unit: item.food.servingUnit))
                        .font(.subheadline)
                        .foregroundStyle(progressColor(status))
                }
                HoldToConfirmButton(title: "Hold to capture \(AmountLabel.trimmed(goalAmount)) \(item.food.servingUnit)", progress: $holdProgress) {
                    captureGoalByHand()
                }
                Button("Skip \(item.food.name)") { skipPlanned() }
            } header: {
                Text("Pouring now")
            } footer: {
                Text("Pour towards the target - little by little is fine - then press TARE on the scale to capture the actual weight. Or hold the button here.")
            }
            .listRowBackground(AppRowBackground())
        }
    }

    private func progressColor(_ status: GoalWeigh.Status) -> Color {
        switch status {
        case .under: AppColor.accent
        case .onTarget: AppColor.success
        case .over: AppColor.warning
        }
    }

    private func statusText(_ status: GoalWeigh.Status, unit: String) -> String {
        switch status {
        case .under(let remaining): "\(AmountLabel.trimmed(remaining)) \(unit) to go"
        case .onTarget: "On target"
        case .over(let by): "Over by \(AmountLabel.trimmed(by)) \(unit)"
        }
    }

    // MARK: Capturing

    /// Counting starts from whatever is on the scale now. If it already holds
    /// something (the bowl), the first TARE isn't needed.
    private func restart() {
        baseline = currentMass
        ready = currentMass >= 1
        pendingGrams = nil
    }

    /// TARE was pressed on the scale; `massBefore` is what it held just before zeroing.
    private func scaleTared(massBefore: Double) {
        // The scale now reads zero, so counting restarts from zero either way.
        defer { baseline = 0 }
        guard ready else {
            ready = true
            message = "Zeroed. Choose what you're adding, pour, then press TARE to log it."
            return
        }
        if mode == .open && scoopMode {
            message = "TARE zeroed the scale. When scooping, put the container back and hold the button to log instead."
            return
        }
        let mass = max(0, massBefore - baseline)
        guard (mass * 10).rounded() > 0 else {
            message = "Zeroed - nothing new to log."
            return
        }
        if mode == .goal {
            guard let item = goalItem else { message = "Zeroed."; return }
            capture(item, mass: mass)
        } else {
            guard let food = currentFood else {
                message = "Zeroed. Choose what you're adding before you pour, so TARE can log it."
                return
            }
            log(food, grams: mass)
        }
    }

    /// The press-and-hold in open weigh: logs what's been added (or scooped out) so far.
    private func captureOpenByHand() {
        let mass = massSinceBaseline(from: currentMass)
        guard (mass * 10).rounded() > 0 else { message = "Nothing to log yet."; return }
        claim(mass, verb: scoopMode ? "scooped out" : "added")
        baseline = currentMass
    }

    /// The press-and-hold in goal weigh: capture whatever has been added, even nothing.
    private func captureGoalByHand() {
        guard let item = goalItem else { return }
        capture(item, mass: massSinceBaseline(from: currentMass))
        baseline = currentMass
    }

    private func capture(_ item: PlannedItem, mass: Double) {
        pendingGrams = nil
        if (mass * 10).rounded() > 0 {
            log(item.food, grams: mass)
        } else {
            // Confirmed as nothing: counted as zero, no zero-quantity entry.
            if let index = plan.firstIndex(where: { $0.id == item.id }) { plan[index].weighed = 0 }
            message = "Confirmed - no \(item.food.name) counted."
        }
    }

    /// A captured amount: logged against the chosen food, or held until one is chosen.
    private func claim(_ amount: Double, verb: String) {
        if let food = currentFood {
            log(food, grams: amount)
        } else {
            pendingGrams = amount
            message = "\(AmountLabel.trimmed(amount)) g \(verb) - choose what it is."
        }
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
                planned.append(PlannedItem(food: food, target: item.quantity * food.servingSize))
            }
            plan = planned
            restart()
            message = skipped > 0 ? "\(skipped) item\(skipped == 1 ? "" : "s") can't be weighed (recipes or foods not counted in g or ml) - log those by hand." : nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func addTarget(_ food: Food) {
        defer { targetFood = nil }
        let cleaned = targetText.replacingOccurrences(of: ",", with: ".")
        let unit = food.servingUnit.lowercased()
        guard let target = Double(cleaned), target > 0, unit == "g" || unit == "ml" else {
            message = "\(food.name) needs an amount in \(unit == "ml" ? "ml" : "g") to aim for."
            return
        }
        if goalItem == nil { restart() }
        plan.append(PlannedItem(food: food, target: target))
    }

    private func skipPlanned() {
        guard planIndex < plan.count else { return }
        // A zero marks it done without logging anything.
        plan[planIndex].weighed = 0
    }

    private func choose(_ food: Food) {
        currentFood = food
        if let grams = pendingGrams {
            pendingGrams = nil
            log(food, grams: grams)
        }
    }

    /// Records `grams` of mass as `food`, converted to the food's own unit.
    private func log(_ food: Food, grams: Double) {
        guard food.servingSize > 0,
              let converted = ScaleDecoding.amount(forGrams: grams, foodUnit: food.servingUnit, scaleUnit: scale.unit) else {
            message = "\(food.name) is counted in \(food.servingUnit), not by weight - log it by hand."
            return
        }
        let amount = (converted * 10).rounded() / 10
        onLog(food, converted / food.servingSize)
        added.append((food, amount))
        message = "\(AmountLabel.trimmed(amount)) \(food.servingUnit) \(food.name) added"
        // Ready for the next ingredient.
        currentFood = nil
        if let index = plan.firstIndex(where: { $0.weighed == nil && $0.food.id == food.id }) {
            plan[index].weighed = amount
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
