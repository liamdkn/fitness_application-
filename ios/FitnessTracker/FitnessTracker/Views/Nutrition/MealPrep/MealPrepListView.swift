import SwiftUI

/// Everything currently prepped - what's left of each batch and when it
/// needs eating by - plus past batches to "prep again" from. Reached from
/// the Nutrition tab's Meals "..." menu.
struct MealPrepListView: View {
    @State private var summaries: [MealPrepSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingBuilder = false
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

    private var finished: [MealPrepSummary] {
        summaries.filter(\.isFinished)
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            if summaries.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No meal preps yet", systemImage: "takeoutbag.and.cup.and.straw")
                } description: {
                    Text("Cook a batch - overnight oats, a curry, protein balls - and log a portion at a time over the next few days.")
                } actions: {
                    Button("Prep a Meal") { showingBuilder = true }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }

            if !active.isEmpty {
                Section("In the fridge") {
                    ForEach(active) { summary in
                        link(for: summary)
                    }
                }
            }

            if !frozen.isEmpty {
                Section("In the freezer") {
                    ForEach(frozen) { summary in
                        link(for: summary)
                    }
                }
            }

            if !finished.isEmpty {
                Section("Finished") {
                    ForEach(finished) { summary in
                        link(for: summary)
                    }
                }
            }
        }
        .navigationTitle("Meal Prep")
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
                    Text("Prepped \(summary.prep.preppedDate.formatted(.dateTime.day().month(.abbreviated)))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
