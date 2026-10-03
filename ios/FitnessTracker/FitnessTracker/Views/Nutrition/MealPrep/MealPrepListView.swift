import SwiftUI

/// Recipes: every dish ever made (one row each, with "Make Again"), and
/// what's currently in stock - the batches in the fridge and freezer, with
/// portions left and eat-by dates. A recipe is just the most recent batch of
/// that dish, so making it again is one tap and starts pre-filled. Reached
/// from the Nutrition tab's Meals "..." menu.
struct MealPrepListView: View {
    /// One dish, summarised from every batch made under its name.
    private struct Dish: Identifiable {
        let name: String
        let latest: MealPrepSummary
        let timesMade: Int
        var id: String { name.lowercased() }
    }

    @State private var summaries: [MealPrepSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingBuilder = false
    @State private var makeAgainPrefill: MealPrepBuilderView.Prefill?
    private let repository = MealPrepRepository()

    /// Soonest eat-by first - the batch most at risk of going off leads.
    private var active: [MealPrepSummary] {
        summaries.filter { !$0.isFinished && !$0.prep.isFrozen }.sorted { $0.prep.eatBy < $1.prep.eatBy }
    }

    /// Longest-frozen first - the one to use up before it gets forgotten.
    private var frozen: [MealPrepSummary] {
        summaries
            .filter { !$0.isFinished && $0.prep.isFrozen }
            .sorted { ($0.prep.frozenDate ?? $0.prep.preppedDate) < ($1.prep.frozenDate ?? $1.prep.preppedDate) }
    }

    /// One row per dish name (case-insensitive), most recently made first.
    /// `summaries` arrives newest first, so the first batch seen per name
    /// is its latest.
    private var dishes: [Dish] {
        var seen: [String: Int] = [:]
        var latest: [String: MealPrepSummary] = [:]
        var order: [String] = []
        for summary in summaries {
            let key = summary.prep.name.lowercased()
            if latest[key] == nil {
                latest[key] = summary
                order.append(key)
            }
            seen[key, default: 0] += 1
        }
        return order.compactMap { key in
            latest[key].map { Dish(name: $0.prep.name, latest: $0, timesMade: seen[key] ?? 1) }
        }
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            if summaries.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No recipes yet", systemImage: "takeoutbag.and.cup.and.straw")
                } description: {
                    Text("Cook a batch - overnight oats, a curry, protein balls - and log a portion at a time. Next time, make it again in one tap.")
                } actions: {
                    Button("New Recipe") { showingBuilder = true }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }

            if !active.isEmpty {
                Section("In stock - fridge") {
                    ForEach(active) { summary in
                        link(for: summary)
                    }
                }
            }

            if !frozen.isEmpty {
                Section("In stock - freezer") {
                    ForEach(frozen) { summary in
                        link(for: summary)
                    }
                }
            }

            if !dishes.isEmpty {
                Section {
                    ForEach(dishes) { dish in
                        dishRow(dish)
                    }
                } header: {
                    Text("Recipes")
                } footer: {
                    Text("Make Again starts a new batch with the same ingredients - swap a brand or change an amount before you save.")
                }
            }
        }
        .navigationTitle("Recipes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingBuilder = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingBuilder) {
            MealPrepBuilderView { _ in
                Task { await load() }
            }
        }
        .sheet(item: $makeAgainPrefill) { prefill in
            MealPrepBuilderView(prefill: prefill) { _ in
                Task { await load() }
            }
        }
    }

    private func dishRow(_ dish: Dish) -> some View {
        let summary = dish.latest
        return HStack(alignment: .center, spacing: 10) {
            NavigationLink {
                MealPrepDetailView(summary: summary, previous: previous(of: summary)) {
                    Task { await load() }
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dish.name)
                        .font(.headline)
                    Text("\(Int(summary.recipe.calories.rounded())) kcal \u{00b7} P \(Int(summary.recipe.proteinG.rounded()))g per portion")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Made \(dish.timesMade) time\(dish.timesMade == 1 ? "" : "s") \u{00b7} last \(summary.prep.preppedDate.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Make Again") {
                Task { await makeAgain(summary) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// Starts a new batch pre-filled from a dish's latest one.
    private func makeAgain(_ summary: MealPrepSummary) async {
        do {
            let ingredients = try await repository.fetchIngredients(of: summary.prep)
            makeAgainPrefill = MealPrepBuilderView.Prefill(
                name: summary.prep.name,
                portions: summary.prep.portions,
                eatWithinDays: summary.prep.eatWithinDays,
                ingredients: ingredients
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func link(for summary: MealPrepSummary) -> some View {
        NavigationLink {
            MealPrepDetailView(summary: summary, previous: previous(of: summary)) {
                Task { await load() }
            }
        } label: {
            MealPrepRow(summary: summary)
        }
    }

    /// The batch immediately before this one with the same name - what
    /// "vs last batch" in the detail screen compares against.
    private func previous(of summary: MealPrepSummary) -> MealPrepSummary? {
        let name = summary.prep.name.lowercased()
        return summaries
            .filter { $0.prep.name.lowercased() == name && $0.prep.preppedOn < summary.prep.preppedOn }
            .max { $0.prep.preppedOn < $1.prep.preppedOn }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            summaries = try await repository.fetchSummaries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MealPrepRow: View {
    let summary: MealPrepSummary

    /// Frozen batches never go "past eat-by" - the clock restarts on thaw.
    private var isOverdue: Bool {
        !summary.isFinished && !summary.prep.isFrozen && summary.prep.eatBy < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.prep.name)
                    .font(.headline)
                Spacer()
                if summary.isFinished {
                    Text("Done").foregroundStyle(.secondary)
                } else {
                    Text("\(MealPrepCalculator.label(summary.remainingPortions)) left")
                        .font(.subheadline.bold())
                }
            }
            if !summary.isFinished {
                ProgressView(value: min(summary.eatenPortions, summary.prep.portions), total: summary.prep.portions)
                    .tint(isOverdue ? .red : (summary.prep.isFrozen ? .cyan : .accentColor))
            }
            HStack(spacing: 6) {
                Text("\(Int(summary.recipe.calories)) kcal \u{00b7} P \(Int(summary.recipe.proteinG))g")
                Spacer()
                if isOverdue {
                    Label("Past eat-by", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if summary.prep.isFrozen && !summary.isFinished {
                    Label("Frozen \((summary.prep.frozenDate ?? summary.prep.preppedDate).formatted(.dateTime.day().month(.abbreviated)))", systemImage: "snowflake")
                        .foregroundStyle(.cyan)
                } else if !summary.isFinished {
                    Text("Eat by \(summary.prep.eatBy.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                } else {
                    Text("Made \(summary.prep.preppedDate.formatted(.dateTime.day().month(.abbreviated)))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
