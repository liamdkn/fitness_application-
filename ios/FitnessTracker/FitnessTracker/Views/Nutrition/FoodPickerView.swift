import SwiftUI

/// Search-and-pick pattern copied directly from `ExercisePickerView` -
/// search a shared catalog (here: `foods`, seeded + growing via custom
/// additions and later Open Food Facts lookups), fall back to adding your
/// own. The one addition over that pattern is a quantity step after
/// picking, since a food (unlike an exercise) needs "how many servings"
/// before it means anything.
struct FoodPickerView: View {
    let mealSlotName: String
    let onLog: (Food, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [Food] = []
    /// Open Food Facts text-search hits for the current query, shown under
    /// the local results - nothing is stored until one is picked.
    @State private var onlineResults: [OpenFoodFactsService.SearchHit] = []
    @State private var isSearchingOnline = false
    @State private var recentFoods: [Food] = []
    @State private var errorMessage: String?
    @State private var pendingFood: Food?
    @State private var showingAddCustom = false
    @State private var showingScanner = false
    @State private var showingLabelScanner = false
    /// Set right before `showingLabelScanner` when this came from a failed
    /// barcode lookup (see `BarcodeScannerView.onScanLabelInstead`), so the
    /// scanned label still gets attached to that barcode; `nil` for the
    /// standalone "Scan Label" quick action.
    @State private var labelScanBarcode: String?
    @State private var scannedLabelDraft: ScannedLabelDraft?
    /// An unverified food on its way to the full-screen check before the
    /// quantity step - see `select` and `AddCustomFoodView.reviewing`.
    @State private var reviewFood: Food?
    /// A scanned barcode nothing matched, being typed in by hand - the
    /// resulting food is saved against it (see `AddCustomFoodView.barcode`).
    @State private var manualEntry: ManualBarcodeEntry?
    private let repository = FoodRepository()
    private let mealEntryRepository = MealEntryRepository()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                HStack(spacing: 12) {
                    quickActionButton(icon: "barcode.viewfinder", label: "Barcode Scan") { showingScanner = true }
                    quickActionButton(icon: "text.viewfinder", label: "Scan Label") {
                        labelScanBarcode = nil
                        showingLabelScanner = true
                    }
                    quickActionButton(icon: "bolt.fill", label: "Quick Add") { showingAddCustom = true }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                if searchText.isEmpty {
                    if recentFoods.isEmpty {
                        Text("Search for a food to log to \(mealSlotName), or scan a barcode.")
                            .foregroundStyle(.secondary)
                    } else {
                        Section("Recently Used") {
                            ForEach(recentFoods) { food in
                                foodRow(food)
                            }
                        }
                    }
                } else {
                    if !results.isEmpty {
                        ForEach(results) { food in
                            foodRow(food)
                        }
                    }
                    if !onlineResults.isEmpty {
                        Section("More results - Open Food Facts") {
                            ForEach(onlineResults) { hit in
                                onlineRow(hit)
                            }
                        }
                    } else if isSearchingOnline {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Searching online...").foregroundStyle(.secondary)
                        }
                    } else if results.isEmpty {
                        Text("No matches - try a different search, scan the barcode, or add a new food.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
            // `.task(id:)` cancels the previous search when `searchText`
            // changes again before it resolves - without that, an
            // in-flight request for an earlier, shorter keystroke (e.g.
            // "c") can resolve AFTER a later, more specific one (e.g.
            // "chicken") and clobber it with a broader, wrong-looking
            // result list.
            .task(id: searchText) {
                if searchText.isEmpty { onlineResults = [] }
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await search(searchText)
            }
            .task {
                await loadRecentlyUsed()
            }
            .navigationTitle("Add Food")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Food") { showingAddCustom = true }
                }
            }
            .sheet(item: $pendingFood) { food in
                LogFoodQuantityView(food: food, mealSlotName: mealSlotName) { confirmedFood, quantity in
                    onLog(confirmedFood, quantity)
                    dismiss()
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                AddCustomFoodView { food in
                    pendingFood = food
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView(
                    onFound: { food in select(food) },
                    onScanLabelInstead: { barcode in
                        labelScanBarcode = barcode
                        showingScanner = false
                        showingLabelScanner = true
                    },
                    onEnterManually: { barcode in
                        showingScanner = false
                        manualEntry = ManualBarcodeEntry(barcode: barcode)
                    }
                )
            }
            .sheet(item: $manualEntry) { entry in
                AddCustomFoodView(onCreated: { food in pendingFood = food }, barcode: entry.barcode)
            }
            // Full screen, not a sheet: this is the "is this food right?"
            // check every unverified food goes through, and it needs the
            // whole screen to compare against the pack.
            .fullScreenCover(item: $reviewFood) { food in
                AddCustomFoodView(onCreated: { confirmed in pendingFood = confirmed }, reviewing: food)
            }
            .sheet(isPresented: $showingLabelScanner) {
                NutritionLabelScannerView(barcode: labelScanBarcode) { parsed, barcode in
                    scannedLabelDraft = ScannedLabelDraft(parsed: parsed, barcode: barcode)
                }
            }
            .sheet(item: $scannedLabelDraft) { draft in
                AddCustomFoodView(
                    onCreated: { food in pendingFood = food },
                    initialServingSize: draft.parsed.servingSize.map { formattedOCRValue($0) } ?? "100",
                    initialServingUnit: draft.parsed.servingUnit ?? "g",
                    initialCalories: draft.parsed.caloriesKcal.map { formattedOCRValue($0) } ?? "",
                    initialProtein: draft.parsed.proteinG.map { formattedOCRValue($0) } ?? "",
                    initialCarbs: draft.parsed.carbsG.map { formattedOCRValue($0) } ?? "",
                    initialFat: draft.parsed.fatG.map { formattedOCRValue($0) } ?? "",
                    initialFiber: draft.parsed.fiberG.map { formattedOCRValue($0) } ?? "",
                    initialSodium: draft.parsed.sodiumMg.map { formattedOCRValue($0) } ?? "",
                    source: "ocr",
                    barcode: draft.barcode
                )
            }
        }
    }

    private func formattedOCRValue(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    /// "Quick Add" opens the exact same custom-food sheet as the "New Food"
    /// toolbar button - a name plus calories/macros, no catalog lookup -
    /// which is exactly what a "quick add" means in other food-logging
    /// apps: skip search entirely and just type the numbers. No separate
    /// flow needed.
    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
    }

    /// A verified food goes straight to the quantity step; anything else -
    /// scanned, searched, a recent, an online hit - opens the full-screen
    /// check first, every time, until it's been verified. That's what keeps
    /// the database honest: nothing unchecked gets logged without a look
    /// at its numbers.
    private func select(_ food: Food) {
        if food.isVerified {
            pendingFood = food
        } else {
            reviewFood = food
        }
    }

    @ViewBuilder
    private func foodRow(_ food: Food) -> some View {
        Button {
            select(food)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.displayName)
                    .foregroundStyle(.primary)
                Text("\(Int(food.calories)) kcal per \(food.servingLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func onlineRow(_ hit: OpenFoodFactsService.SearchHit) -> some View {
        Button {
            Task { await pickOnline(hit) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.lookup.brand.map { "\(hit.lookup.name) (\($0))" } ?? hit.lookup.name)
                    .foregroundStyle(.primary)
                Text("\(Int(hit.lookup.calories)) kcal per 100\(hit.lookup.servingUnit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Stores the picked hit (or finds the copy already stored) and sends it
    /// through the same confirm-then-quantity steps a barcode scan uses, so
    /// its brand and numbers can be checked before logging.
    private func pickOnline(_ hit: OpenFoodFactsService.SearchHit) async {
        do {
            select(try await repository.food(for: hit))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A keystroke arriving while an earlier search is still in flight
    /// cancels that older `.task(id:)` mid-request (see its own doc
    /// comment) - the underlying network call surfaces that as a thrown
    /// `CancellationError`, not a real failure, so it's dropped here rather
    /// than shown as one. A newer search is already on its way to replace
    /// these `results` regardless.
    private func search(_ query: String) async {
        do {
            results = try await repository.search(query: query)
            errorMessage = nil
        } catch is CancellationError {
            // Superseded by a newer keystroke - nothing to show.
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        await searchOnline(query)
    }

    /// Runs after the (instant) local search so local results are never held
    /// up by the network. A failed/offline lookup just leaves the section
    /// empty - local results are still there - rather than raising an error.
    private func searchOnline(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            onlineResults = []
            return
        }
        isSearchingOnline = true
        defer { isSearchingOnline = false }
        guard let hits = try? await OpenFoodFactsService.search(query: trimmed), !Task.isCancelled else { return }
        let localBarcodes = Set(results.compactMap(\.barcode))
        onlineResults = hits.filter { !localBarcodes.contains($0.barcode) }
    }

    /// Most-recently-logged foods, most recent first - `fetchByIds` doesn't
    /// preserve the order its ids were passed in (a plain SQL `IN`), so the
    /// fetched foods are re-sorted back into that recency order rather than
    /// whatever order the database happened to return them in.
    private func loadRecentlyUsed() async {
        do {
            let ids = try await mealEntryRepository.fetchRecentlyLoggedFoodIds()
            let foods = try await repository.fetchByIds(ids)
            let foodsById = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
            recentFoods = ids.compactMap { foodsById[$0] }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Which unit the quantity `TextField` is being entered in - `.servings` is
/// a multiplier on the food's own defined serving (e.g. "1.5 \u{00d7} 100g"),
/// `.amount` is a raw number in the food's own serving unit (e.g. "137",
/// meaning 137g) so a user who thinks in grams doesn't have to do the
/// division themselves. Both ultimately resolve to the same servings
/// multiplier `onConfirm` expects - this only changes what the field
/// displays and how what's typed in it is interpreted.
enum QuantityInputMode: Hashable {
    case servings, amount
}

/// A completed label scan, on its way to the confirm/edit form
/// (`AddCustomFoodView`) - wrapped just to give `.sheet(item:)` an
/// `Identifiable` to key off, since `ParsedNutritionLabel` itself has no
/// natural identity.
private struct ManualBarcodeEntry: Identifiable {
    let barcode: String
    var id: String { barcode }
}

private struct ScannedLabelDraft: Identifiable {
    let id = UUID()
    let parsed: ParsedNutritionLabel
    let barcode: String?
}

private struct LogFoodQuantityView: View {
    /// State, not `let`: "Edit Food Details" can replace it with the
    /// corrected copy, and what gets logged is whatever it ends up as.
    @State private var food: Food
    /// Context only, not a picker - which slot this logs into is already
    /// fixed by which slot's card was tapped to get here, so this is a
    /// read-only label rather than a reassignment control.
    let mealSlotName: String
    let onConfirm: (Food, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editingFood = false
    @State private var quantityText = "1"
    @State private var inputMode: QuantityInputMode = .servings
    private let mealEntryRepository = MealEntryRepository()

    init(food: Food, mealSlotName: String, onConfirm: @escaping (Food, Double) -> Void) {
        _food = State(initialValue: food)
        self.mealSlotName = mealSlotName
        self.onConfirm = onConfirm
    }

    /// Keyed per-food so switching foods never leaks one food's preferred
    /// mode onto another - a food you always weigh in grams and a food you
    /// always log as "2 slices" can each keep their own default.
    private var inputModeDefaultsKey: String { "foodQuantityInputMode.\(food.id.uuidString)" }

    private var quantity: Double? {
        guard let entered = Double(quantityText) else { return nil }
        switch inputMode {
        case .servings: return entered
        case .amount: return food.servingSize > 0 ? entered / food.servingSize : nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Meal", value: mealSlotName)
                    if let brand = food.brand, !brand.isEmpty {
                        LabeledContent("Brand", value: brand)
                    }
                    if food.isVerified {
                        Label("Verified", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    Picker("Enter as", selection: $inputMode) {
                        Text("Servings").tag(QuantityInputMode.servings)
                        Text(food.servingUnit.capitalized).tag(QuantityInputMode.amount)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: inputMode) { oldMode, newMode in
                        convertQuantityText(from: oldMode, to: newMode)
                        UserDefaults.standard.set(newMode == .amount, forKey: inputModeDefaultsKey)
                    }
                    HStack {
                        Text(inputMode == .servings ? "Servings" : "Amount")
                        Spacer()
                        TextField("1", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text(inputMode == .servings ? "\u{00d7} \(food.servingLabel)" : food.servingUnit)
                            .foregroundStyle(.secondary)
                    }
                }
                if let quantity, quantity > 0 {
                    Section {
                        MacroBreakdownRing(
                            calories: food.calories(at: quantity),
                            carbsG: food.carbsG(at: quantity),
                            fatG: food.fatG(at: quantity),
                            proteinG: food.proteinG(at: quantity)
                        )
                        .padding(.vertical, 8)
                    }
                    Section("Adds") {
                        LabeledContent("Calories", value: "\(Int(food.calories(at: quantity))) kcal")
                        LabeledContent("Protein", value: "\(Int(food.proteinG(at: quantity)))g")
                        LabeledContent("Carbs", value: "\(Int(food.carbsG(at: quantity)))g")
                        LabeledContent("Fat", value: "\(Int(food.fatG(at: quantity)))g")
                        if let fiber = food.fiberG(at: quantity) {
                            LabeledContent("Fiber", value: "\(Int(fiber))g")
                        }
                        if let sodium = food.sodiumMg(at: quantity) {
                            LabeledContent("Sodium", value: "\(Int(sodium.rounded())) mg")
                        }
                    }
                }
                Section {
                    Button {
                        editingFood = true
                    } label: {
                        Label("Edit Food Details", systemImage: "pencil")
                    }
                } footer: {
                    Text("Something not matching the pack? Correct it here - and untick verified if it needs another look.")
                }
            }
            .navigationTitle(food.name)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        if let quantity { onConfirm(food, quantity) }
                    }
                    .disabled(!(quantity.map { $0 > 0 } ?? false))
                }
            }
            .task {
                await loadDefaults()
            }
            .fullScreenCover(isPresented: $editingFood) {
                AddCustomFoodView(onCreated: { updated in food = updated }, reviewing: food)
            }
        }
    }

    /// Pre-fills with whatever this food was logged as last time, instead
    /// of always resetting to "1 serving" - the mode preference is a local,
    /// per-food `UserDefaults` flag (just a display choice, not something
    /// worth a sync round-trip), while the actual last-used amount comes
    /// from this user's own `meal_entries` history so it's consistent
    /// across devices.
    private func loadDefaults() async {
        inputMode = UserDefaults.standard.bool(forKey: inputModeDefaultsKey) ? .amount : .servings
        guard let lastQuantity = try? await mealEntryRepository.fetchLastQuantity(foodId: food.id) else { return }
        quantityText = formattedQuantity(inputMode == .amount ? lastQuantity * food.servingSize : lastQuantity)
    }

    private func convertQuantityText(from oldMode: QuantityInputMode, to newMode: QuantityInputMode) {
        guard oldMode != newMode, let entered = Double(quantityText), food.servingSize > 0 else { return }
        switch newMode {
        case .servings: quantityText = formattedQuantity(entered / food.servingSize)
        case .amount: quantityText = formattedQuantity(entered * food.servingSize)
        }
    }

    private func formattedQuantity(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

/// Calories at center, ringed by carbs/fat/protein's share of those
/// calories (4/9/4 kcal-per-gram, standard macro energy factors) - not
/// their share of a daily target, since this view has no target context,
/// just "what this one food/quantity adds."
struct MacroBreakdownRing: View {
    let calories: Double
    let carbsG: Double
    let fatG: Double
    let proteinG: Double

    private var carbsCal: Double { carbsG * 4 }
    private var fatCal: Double { fatG * 9 }
    private var proteinCal: Double { proteinG * 4 }
    private var totalMacroCal: Double { max(carbsCal + fatCal + proteinCal, 1) }

    private var carbsFraction: Double { carbsCal / totalMacroCal }
    private var fatFraction: Double { fatCal / totalMacroCal }
    private var proteinFraction: Double { proteinCal / totalMacroCal }

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: carbsFraction)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                    Circle()
                        .trim(from: carbsFraction, to: carbsFraction + fatFraction)
                        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                    Circle()
                        .trim(from: carbsFraction + fatFraction, to: min(carbsFraction + fatFraction + proteinFraction, 1))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                }
                .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(Int(calories))")
                        .font(.title2.bold())
                    Text("cal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 8) {
                macroPercentRow("Carbs", carbsFraction, .green)
                macroPercentRow("Fat", fatFraction, .yellow)
                macroPercentRow("Protein", proteinFraction, .blue)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func macroPercentRow(_ label: String, _ fraction: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption)
            Spacer(minLength: 20)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.caption.bold())
        }
    }
}
