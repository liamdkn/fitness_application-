import SwiftUI

/// The daily milk allowance: which milk, how much, on or off. The amount here
/// is the default each new day starts with - to change it for one day, edit
/// (or remove) that day's milk entry in the Drinks meal.
struct MilkAllowanceView: View {
    @State private var enabled = false
    @State private var ml = 100
    @State private var foodId: UUID?
    @State private var milks: [Food] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    private let preferencesRepository = UserPreferencesRepository()

    var body: some View {
        Form {
            Section {
                Toggle("Add milk every day", isOn: $enabled)
                if enabled {
                    Picker("Milk", selection: $foodId) {
                        Text("Choose...").tag(UUID?.none)
                        ForEach(milks) { milk in
                            Text(milk.displayName).tag(Optional(milk.id))
                        }
                    }
                    Stepper(value: $ml, in: 0...500, step: 25) {
                        LabeledContent("Amount", value: "\(ml) ml")
                    }
                }
            } footer: {
                Text("For the milk that goes in tea and coffee. One entry is added to Drinks each day the app is opened, so its calories and fluid count without logging it. To change it for a single day, edit or remove today's milk entry - the amount here is just each day's starting point.")
            }
            .listRowBackground(AppRowBackground())

            if enabled && foodId == nil {
                Text("Pick a milk to start. Only foods named milk that are marked as drinks are listed - add yours with New Drink if it's missing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
                    .listRowBackground(Color.clear)
            }
        }
        .appScreen()
        .navigationTitle("Daily Milk")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: enabled) { save() }
        .onChange(of: ml) { save() }
        .onChange(of: foodId) { save() }
    }

    private func load() async {
        milks = ((try? await FoodRepository().browse(query: "milk")) ?? [])
            .filter { $0.isDrink && $0.name.localizedCaseInsensitiveContains("milk") }
            .sorted { $0.displayName < $1.displayName }
        if let prefs = try? await preferencesRepository.fetch() {
            enabled = prefs.milkAllowanceEnabled
            ml = prefs.milkAllowanceMl
            foodId = prefs.milkFoodId
            // A previously chosen milk that isn't named "milk" (a custom one)
            // still has to appear in the list.
            if let id = prefs.milkFoodId, !milks.contains(where: { $0.id == id }),
               let chosen = try? await FoodRepository().fetchByIds([id]).first {
                milks.append(chosen)
            }
        }
        // Let the assignments above settle before changes count as the user's own.
        try? await Task.sleep(nanoseconds: 300_000_000)
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        let (enabled, ml, foodId) = (enabled, ml, foodId)
        Task {
            do {
                try await preferencesRepository.setMilkAllowance(enabled: enabled, ml: ml, foodId: foodId)
                errorMessage = nil
                await MilkAllowanceService.applyIfNeeded()
            } catch {
                errorMessage = OfflineError.isConnectivity(error)
                    ? "You're offline - this will need to be saved again when you're back online."
                    : error.localizedDescription
            }
        }
    }
}
