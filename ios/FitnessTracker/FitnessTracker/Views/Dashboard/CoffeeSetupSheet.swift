import SwiftUI

/// Turns how you actually make coffee into a drink with a caffeine figure,
/// so logging a cup is one tap. Both are estimates - say so rather than
/// pretend precision:
///
/// - **Brew pot**: caffeine is worked out from the grounds, because a pot's
///   strength depends on how much coffee goes in, not on a label. About 10 mg
///   of caffeine ends up in the pot per gram of grounds for a normal drip
///   brew, and a scoop is roughly 10 g - weigh yours once and adjust.
/// - **Pod**: the pod's own caffeine, which varies by brand and size - check
///   the box or the maker's site and enter it.
struct CoffeeSetupSheet: View {
    private enum Mode: Hashable { case pot, pod }

    let onSaved: (Food) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .pot
    // Brew pot
    @State private var potName = "Brew pot coffee"
    @State private var potLitres = "1.6"
    @State private var scoops = "3"
    @State private var gramsPerScoop = "10"
    @State private var mgPerGram = "10"
    // Pod
    @State private var podName = "Pod coffee"
    @State private var podMl = "150"
    @State private var podMg = "80"
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = FoodRepository()

    private var totalPotMg: Double? {
        guard let scoops = Double(scoops), let grams = Double(gramsPerScoop), let mg = Double(mgPerGram),
              scoops > 0, grams > 0, mg > 0 else { return nil }
        return scoops * grams * mg
    }

    /// Per 100 ml of the made-up pot.
    private var potMgPer100Ml: Double? {
        guard let total = totalPotMg, let litres = Double(potLitres), litres > 0 else { return nil }
        return total / (litres * 10)
    }

    private var isValid: Bool {
        switch mode {
        case .pot: return !potName.trimmingCharacters(in: .whitespaces).isEmpty && potMgPer100Ml != nil
        case .pod: return !podName.trimmingCharacters(in: .whitespaces).isEmpty && (Double(podMl) ?? 0) > 0 && (Double(podMg) ?? 0) > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Machine", selection: $mode) {
                    Text("Brew pot").tag(Mode.pot)
                    Text("Pod").tag(Mode.pod)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                switch mode {
                case .pot: potSection
                case .pod: podSection
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Set Up Coffee")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
        }
    }

    @ViewBuilder
    private var potSection: some View {
        Section {
            TextField("Name", text: $potName)
            field("Pot size", text: $potLitres, unit: "L")
            field("Scoops of coffee", text: $scoops, unit: "scoops")
            field("Grams per scoop", text: $gramsPerScoop, unit: "g")
            field("Caffeine per gram of grounds", text: $mgPerGram, unit: "mg/g")
        } footer: {
            Text("Weigh one scoop of your coffee once and enter it. About 10 mg of caffeine per gram of grounds ends up in a drip pot; a darker or stronger bean can differ.")
        }
        if let per100 = potMgPer100Ml, let total = totalPotMg {
            Section("What this makes") {
                LabeledContent("Whole pot", value: "\(Int(total.rounded())) mg")
                LabeledContent("Per 250 ml cup", value: "\(Int((per100 * 2.5).rounded())) mg")
                LabeledContent("Per 100 ml", value: String(format: "%.1f mg", per100))
            }
        }
    }

    @ViewBuilder
    private var podSection: some View {
        Section {
            TextField("Name", text: $podName)
            field("Volume per cup", text: $podMl, unit: "ml")
            field("Caffeine per pod", text: $podMg, unit: "mg")
        } footer: {
            Text("Pods vary a lot by brand and size - check the box or the maker's site for the caffeine in yours. One pod is one serving, so logging 1 serving is one cup.")
        }
    }

    private func field(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
        }
    }

    /// Creates the drink, or updates the one already saved under that name -
    /// re-running setup (a new bag of coffee, a different scoop) shouldn't
    /// leave you with two "Brew pot coffee"s.
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let name: String, servingSize: Double, caffeine: Double
        switch mode {
        case .pot:
            guard let per100 = potMgPer100Ml else { return }
            name = potName.trimmingCharacters(in: .whitespaces)
            servingSize = 100
            caffeine = (per100 * 100).rounded() / 100
        case .pod:
            guard let ml = Double(podMl), let mg = Double(podMg) else { return }
            name = podName.trimmingCharacters(in: .whitespaces)
            servingSize = ml
            caffeine = mg
        }
        do {
            let existing = try await repository.fetchCustomDrinks().first { $0.name.lowercased() == name.lowercased() }
            let food: Food
            if let existing {
                food = try await repository.saveCorrection(
                    of: existing, name: name, brand: existing.brand, servingSize: servingSize, servingUnit: "ml",
                    calories: 1, proteinG: 0, carbsG: 0, fatG: 0, fiberG: nil, sodiumMg: nil,
                    caffeineMg: caffeine, isVerified: true
                )
            } else {
                food = try await repository.createCustom(
                    name: name, brand: nil, servingSize: servingSize, servingUnit: "ml",
                    calories: 1, proteinG: 0, carbsG: 0, fatG: 0, fiberG: nil, sodiumMg: nil,
                    caffeineMg: caffeine, isVerified: true
                )
            }
            onSaved(food)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
