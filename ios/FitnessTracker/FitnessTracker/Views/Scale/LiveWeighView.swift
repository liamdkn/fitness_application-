import AVFoundation
import SwiftUI

/// Weigh ingredients one after another into a meal: pick what you're adding,
/// pour, and when the weight settles it's logged - "50 g oats added" - then
/// pick the next and carry on without tapping the scale. The amount added is
/// the change on the scale, so there's no need to tare between ingredients.
struct LiveWeighView: View {
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
    @AppStorage("scale-speak") private var speak = true
    private let synthesizer = AVSpeechSynthesizer()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 4) {
                        Text("\(AmountLabel.trimmed(liveGrams)) g")
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
                    if let pendingGrams {
                        Text("\(AmountLabel.trimmed(pendingGrams)) g on the scale is waiting - choose what it is.")
                            .font(.caption)
                            .foregroundStyle(AppColor.warning)
                    }
                } header: {
                    Text("Adding now")
                } footer: {
                    Text(currentFood == nil
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
                            LabeledContent(item.food.name, value: "\(AmountLabel.trimmed(item.grams)) g")
                        }
                    }
                    .listRowBackground(AppRowBackground())
                }

                Section {
                    Toggle("Say it out loud", isOn: $speak)
                    Button("Start counting from zero") {
                        engine.rebase(to: 0)
                        message = "Counting again from zero."
                    }
                }
                .listRowBackground(AppRowBackground())

                #if DEBUG
                Section("Practice (no scale)") {
                    HStack {
                        ForEach([10.0, 50.0, 100.0], id: \.self) { grams in
                            Button("+\(Int(grams)) g") { simulate(adding: grams) }
                                .buttonStyle(.bordered)
                        }
                        Button("Clear") { simulate(to: 0) }
                            .buttonStyle(.bordered)
                    }
                }
                .listRowBackground(AppRowBackground())
                #endif
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
            .onAppear {
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
            if let food = currentFood {
                log(food, grams: amount)
            } else {
                pendingGrams = amount
                message = "\(AmountLabel.trimmed(amount)) g added - choose what it is."
            }
        case .removed(let amount):
            message = "\(AmountLabel.trimmed(amount)) g taken off - not logged."
        case .reset:
            message = "Scale cleared. Counting from zero."
            pendingGrams = nil
        }
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
        message = "\(AmountLabel.trimmed(grams)) g \(food.name) added"
        if speak { say("\(AmountLabel.trimmed(grams)) grams of \(food.name) added") }
        // Ready for the next ingredient.
        currentFood = nil
    }

    private func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    #if DEBUG
    /// Feeds readings the way a real scale would: a steady stream.
    private func simulate(adding grams: Double) { simulate(to: liveGrams + grams) }

    private func simulate(to target: Double) {
        let start = Date()
        Task {
            for step in 0..<12 {
                try? await Task.sleep(nanoseconds: 120_000_000)
                receive(target)
                _ = (start, step)
            }
        }
    }
    #endif
}
