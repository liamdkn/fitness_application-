import SwiftUI

/// The one form for putting a food into the database - a brand-new food, a
/// scanned label, and the full-screen check every unverified food goes
/// through before it can be logged. The point is an accurate database, so it
/// asks for the things that make a food trustworthy:
///
/// - the serving size *and* what the printed label is per (a 6 g serving off
///   a "per 100 g" label is the normal case - the app works one serving out),
/// - sodium, and
/// - an explicit "this item is verified" tick, which is what lets a food skip
///   this screen from then on (see `FoodPickerView.select`).
///
/// Foods are measured in g or ml (or a custom unit like "egg" for the
/// few foods that are counted rather than weighed).
struct AddCustomFoodView: View {
    private enum UnitChoice: Hashable { case g, ml, other }
    private enum Basis: Hashable { case per100, perServing }

    let onCreated: (Food) -> Void
    private let source: String
    private let barcode: String?
    /// Set when this is the check on an existing food: the form opens
    /// pre-filled from it, and saving only writes anything if something
    /// changed - see `save`.
    private let reviewing: Food?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var brand: String
    @State private var servingSize: String
    @State private var unitChoice: UnitChoice
    @State private var customUnit: String
    @State private var basis: Basis
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var fiber: String
    @State private var sodium: String
    @State private var caffeine: String
    @State private var isVerified: Bool
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = FoodRepository()

    init(
        onCreated: @escaping (Food) -> Void,
        initialName: String = "",
        initialServingSize: String = "100",
        initialServingUnit: String = "g",
        initialCalories: String = "",
        initialProtein: String = "",
        initialCarbs: String = "",
        initialFat: String = "",
        initialFiber: String = "",
        initialSodium: String = "",
        initialCaffeine: String = "",
        source: String = "user",
        barcode: String? = nil,
        reviewing: Food? = nil
    ) {
        self.onCreated = onCreated
        self.source = source
        self.barcode = reviewing?.barcode ?? barcode
        self.reviewing = reviewing

        let size: String
        let unit: String
        if let food = reviewing {
            _name = State(initialValue: food.name)
            _brand = State(initialValue: food.brand ?? "")
            size = Self.formatted(food.servingSize)
            unit = food.servingUnit
            _calories = State(initialValue: Self.formatted(food.calories))
            _protein = State(initialValue: Self.formatted(food.proteinG))
            _carbs = State(initialValue: Self.formatted(food.carbsG))
            _fat = State(initialValue: Self.formatted(food.fatG))
            _fiber = State(initialValue: food.fiberG.map { Self.formatted($0) } ?? "")
            _sodium = State(initialValue: food.sodiumMg.map { Self.formatted($0) } ?? "")
            _caffeine = State(initialValue: food.caffeineMg.map { Self.formatted($0) } ?? "")
            _isVerified = State(initialValue: food.isVerified)
        } else {
            _name = State(initialValue: initialName)
            _brand = State(initialValue: "")
            size = initialServingSize
            unit = initialServingUnit
            _calories = State(initialValue: initialCalories)
            _protein = State(initialValue: initialProtein)
            _carbs = State(initialValue: initialCarbs)
            _fat = State(initialValue: initialFat)
            _fiber = State(initialValue: initialFiber)
            _sodium = State(initialValue: initialSodium)
            _caffeine = State(initialValue: initialCaffeine)
            _isVerified = State(initialValue: false)
        }
        let choice: UnitChoice = unit.lowercased() == "g" ? .g : (unit.lowercased() == "ml" ? .ml : .other)
        _servingSize = State(initialValue: size)
        _unitChoice = State(initialValue: choice)
        _customUnit = State(initialValue: choice == .other ? unit : "")
        // A 100 g / 100 ml serving *is* the per-100 label, so open on that;
        // anything else was stored per serving.
        _basis = State(initialValue: (choice != .other && Double(size) == 100) ? .per100 : .perServing)
    }

    // MARK: - Derived values

    private var unitText: String {
        switch unitChoice {
        case .g: "g"
        case .ml: "ml"
        case .other: customUnit.trimmingCharacters(in: .whitespaces)
        }
    }

    private var size: Double? {
        guard let value = Double(servingSize), value > 0 else { return nil }
        return value
    }

    /// Factor from the numbers as typed to one serving's worth: 1 when the
    /// label is per serving, serving/100 when it's per 100 g/ml.
    private var scale: Double? {
        guard let size else { return nil }
        return (basis == .per100 && unitChoice != .other) ? size / 100 : 1
    }

    private func perServing(_ text: String) -> Double? {
        guard let value = Double(text), let scale else { return nil }
        return (value * scale * 100).rounded() / 100
    }

    private var fieldsAreValid: Bool {
        perServing(calories) != nil && perServing(protein) != nil && perServing(carbs) != nil && perServing(fat) != nil
            && (fiber.isEmpty || Double(fiber) != nil)
            && (sodium.isEmpty || Double(sodium) != nil)
            && (caffeine.isEmpty || Double(caffeine) != nil)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && size != nil
            && !unitText.isEmpty && fieldsAreValid
    }

    /// Calories vs macros as typed (so, per whatever the label is per) -
    /// `nil` until all four are filled in. A heads-up only: labels round,
    /// and some count alcohol or sugar alcohols, so a correct label can
    /// legitimately not add up. It never blocks saving or verifying.
    private var energyCheck: MacroEnergy.Check? {
        guard let cal = Double(calories), let p = Double(protein), let c = Double(carbs), let f = Double(fat), cal > 0 else { return nil }
        return MacroEnergy.check(calories: cal, protein: p, carbs: c, fat: f, fiber: Double(fiber), tolerance: .label)
    }

    /// Verifying needs sodium on record - "fully accurate" includes it.
    private var canVerify: Bool {
        Double(sodium) != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                foodSection
                servingSection
                nutritionSection
                if let energyCheck, !energyCheck.isConsistent {
                    energyWarning(energyCheck)
                }
                if basis == .per100, unitChoice != .other, scale != nil, perServing(calories) != nil {
                    perServingPreview
                }
                verifySection
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(reviewing != nil ? "Continue" : "Save") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
            .onChange(of: unitChoice) {
                // A custom unit ("egg") has no per-100 equivalent.
                if unitChoice == .other { basis = .perServing }
            }
            .onChange(of: sodium) {
                if !canVerify { isVerified = false }
            }
        }
    }

    private var title: String {
        if reviewing != nil { return "Check Food" }
        return source == "ocr" ? "Confirm Scanned Label" : "New Food"
    }

    private var foodSection: some View {
        Section {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
            TextField(reviewing != nil && brand.isEmpty ? "Brand - not found, add it" : "Brand (optional)", text: $brand)
                .textInputAutocapitalization(.words)
        } header: {
            Text("Food")
        } footer: {
            if reviewing != nil {
                Text("This food isn't verified yet. Check it against the pack, fix anything that's off, and tick verified at the bottom - then it won't ask again.")
            } else if let barcode {
                Text("Saved against barcode \(barcode), so scanning this product again finds it.")
            }
        }
    }

    private var servingSection: some View {
        Section {
            HStack {
                Text("Serving size")
                Spacer()
                TextField("100", text: $servingSize)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            Picker("Measured in", selection: $unitChoice) {
                Text("g").tag(UnitChoice.g)
                Text("ml").tag(UnitChoice.ml)
                Text("Other").tag(UnitChoice.other)
            }
            .pickerStyle(.segmented)
            if unitChoice == .other {
                TextField("Unit (e.g. egg, slice)", text: $customUnit)
            } else {
                Picker("The label's numbers are", selection: $basis) {
                    Text("Per 100 \(unitText)").tag(Basis.per100)
                    Text("Per serving").tag(Basis.perServing)
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Serving")
        } footer: {
            if unitChoice == .other {
                Text("For things counted rather than weighed. Enter the label's numbers for one serving.")
            } else {
                Text("Type the numbers exactly as printed. If the label is per 100 \(unitText) but a serving is, say, 6 \(unitText), choose Per 100 \(unitText) and set the serving to 6 - the app works out one serving for you.")
            }
        }
    }

    private var nutritionSection: some View {
        Section {
            numberField("Calories", text: $calories, unit: "kcal")
            numberField("Protein", text: $protein, unit: "g")
            numberField("Carbs", text: $carbs, unit: "g")
            numberField("Fat", text: $fat, unit: "g")
            numberField("Fiber (optional)", text: $fiber, unit: "g")
            numberField("Sodium", text: $sodium, unit: "mg")
            numberField("Caffeine (optional)", text: $caffeine, unit: "mg")
        } header: {
            Text(basis == .per100 && unitChoice != .other ? "Per 100 \(unitText) (as on the label)" : "Per serving")
        } footer: {
            Text("Label shows salt, not sodium? Multiply the salt in grams by 400 to get mg of sodium.")
        }
    }

    private func energyWarning(_ check: MacroEnergy.Check) -> some View {
        Section {
            Label {
                Text("The calories and macros don't quite add up: \(Int(check.calories.rounded())) kcal listed, but the macros come to about \(Int(check.macroKcal.rounded())) kcal. Double-check the label. You can still save it - labels round, and some count alcohol or fibre differently.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.warning)
            }
        }
    }

    /// What the typed numbers come to for one serving - makes the per-100
    /// conversion visible instead of silent.
    private var perServingPreview: some View {
        let size = self.size ?? 0
        return Section("One serving (\(Self.formatted(size)) \(unitText))") {
            LabeledContent("Calories", value: "\(Int((perServing(calories) ?? 0).rounded())) kcal")
            LabeledContent("Protein", value: "\(Self.formatted(perServing(protein) ?? 0)) g")
            LabeledContent("Carbs", value: "\(Self.formatted(perServing(carbs) ?? 0)) g")
            LabeledContent("Fat", value: "\(Self.formatted(perServing(fat) ?? 0)) g")
            if let sodiumValue = perServing(sodium) {
                LabeledContent("Sodium", value: "\(Self.formatted(sodiumValue)) mg")
            }
        }
    }

    private var verifySection: some View {
        Section {
            Toggle("This item is verified", isOn: $isVerified)
                .disabled(!canVerify)
        } footer: {
            Text(canVerify
                 ? "Tick once every number matches the pack. A verified food skips this check when you scan or pick it. Untick it any time to be asked again."
                 : "Enter the sodium to be able to verify - a food isn't fully accurate without it.")
        }
    }

    @ViewBuilder
    private func numberField(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    // MARK: - Saving

    /// Up to two decimals, no trailing zeros - "59", "13.2", "7.34".
    private static func formatted(_ value: Double) -> String {
        let text = String(format: "%.2f", value)
        return text.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func save() async {
        guard let size, let cal = perServing(calories), let p = perServing(protein),
              let c = perServing(carbs), let f = perServing(fat)
        else { return }
        let fiberValue = fiber.isEmpty ? nil : perServing(fiber)
        let sodiumValue = sodium.isEmpty ? nil : perServing(sodium)
        let caffeineValue = caffeine.isEmpty ? nil : perServing(caffeine)
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let cleanBrand = brand.trimmingCharacters(in: .whitespaces)
        isSaving = true
        defer { isSaving = false }
        do {
            if let reviewing {
                // Nothing changed: carry on with the food as it is rather
                // than writing a pointless duplicate of it. (Leaving it
                // unverified is allowed - it just asks again next time.)
                let unchanged = cleanName == reviewing.name
                    && cleanBrand == (reviewing.brand ?? "")
                    && abs(size - reviewing.servingSize) < 0.005
                    && unitText == reviewing.servingUnit
                    && abs(cal - reviewing.calories) < 0.005
                    && abs(p - reviewing.proteinG) < 0.005
                    && abs(c - reviewing.carbsG) < 0.005
                    && abs(f - reviewing.fatG) < 0.005
                    && (fiberValue ?? -1) == (reviewing.fiberG ?? -1)
                    && (sodiumValue ?? -1) == (reviewing.sodiumMg ?? -1)
                    && (caffeineValue ?? -1) == (reviewing.caffeineMg ?? -1)
                    && isVerified == reviewing.isVerified
                let result = unchanged ? reviewing : try await repository.saveCorrection(
                    of: reviewing,
                    name: cleanName,
                    brand: cleanBrand.isEmpty ? nil : cleanBrand,
                    servingSize: size,
                    servingUnit: unitText,
                    calories: cal,
                    proteinG: p,
                    carbsG: c,
                    fatG: f,
                    fiberG: fiberValue,
                    sodiumMg: sodiumValue,
                    caffeineMg: caffeineValue,
                    isVerified: isVerified
                )
                onCreated(result)
                dismiss()
                return
            }
            let food = try await repository.createCustom(
                name: cleanName,
                brand: cleanBrand.isEmpty ? nil : cleanBrand,
                servingSize: size,
                servingUnit: unitText,
                calories: cal,
                proteinG: p,
                carbsG: c,
                fatG: f,
                fiberG: fiberValue,
                sodiumMg: sodiumValue,
                caffeineMg: caffeineValue,
                isVerified: isVerified,
                barcode: barcode,
                source: source
            )
            onCreated(food)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
