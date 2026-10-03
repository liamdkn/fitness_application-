import SwiftUI

/// Every product the user has linked brands of, each with its best brand
/// called out. Groups mostly appear on their own - swapping a brand while
/// building a meal prep links the two - but "New Group" lets one be started
/// by hand too.
struct FoodGroupsView: View {
    @State private var summaries: [FoodGroupSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingNewGroup = false
    @State private var newGroupName = ""
    private let repository = FoodGroupRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            if summaries.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No linked brands yet", systemImage: "arrow.left.arrow.right")
                } description: {
                    Text("When you swap an ingredient's brand in a meal prep, the two are linked here so you can see which has better macros.")
                }
                .listRowBackground(Color.clear)
            }

            ForEach(summaries) { summary in
                NavigationLink {
                    FoodGroupDetailView(summary: summary) {
                        Task { await load() }
                    }
                } label: {
                    row(summary)
                }
            }
        }
        .navigationTitle("Brand Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newGroupName = ""
                    showingNewGroup = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("New Product Group", isPresented: $showingNewGroup) {
            TextField("e.g. Greek yoghurt", text: $newGroupName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await createGroup() } }
        } message: {
            Text("Name the product, then add the brands you buy of it.")
        }
    }

    private func row(_ summary: FoodGroupSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.group.name)
            let ranked = FoodComparator.ranked(summary.foods, by: .proteinPerKcal)
            if let best = ranked.first, ranked.count > 1 {
                Text("Best: \(best.food.displayName) \u{00b7} \(FoodComparator.Metric.proteinPerKcal.formatted(best.proteinPer100Kcal)) protein/100 kcal")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("\(summary.foods.count) brand\(summary.foods.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    private func createGroup() async {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await repository.createGroup(name: name)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One product's brands ranked against each other, best first by the
/// chosen measure, all normalised to per-100g so pot sizes don't skew it.
struct FoodGroupDetailView: View {
    @State private var summary: FoodGroupSummary
    @State private var metric: FoodComparator.Metric = .proteinPerKcal
    @State private var showingAddBrand = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmingDelete = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    private let repository = FoodGroupRepository()
    let onChange: () -> Void

    init(summary: FoodGroupSummary, onChange: @escaping () -> Void) {
        _summary = State(initialValue: summary)
        self.onChange = onChange
    }

    private var ranked: [FoodPer100] {
        FoodComparator.ranked(summary.foods, by: metric)
    }

    /// Foods measured in pieces rather than g/ml - listed but not ranked.
    private var unranked: [Food] {
        let rankedIds = Set(ranked.map(\.food.id))
        return summary.foods.filter { !rankedIds.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                Picker("Rank by", selection: $metric) {
                    ForEach(FoodComparator.Metric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                if let takeaway = FoodComparator.takeaway(ranked, metric: metric) {
                    Text(takeaway)
                }
            }

            Section("Brands") {
                ForEach(Array(ranked.enumerated()), id: \.element.food.id) { index, item in
                    brandRow(item, isBest: index == 0 && ranked.count > 1)
                }
                .onDelete { offsets in
                    let foods = offsets.map { ranked[$0].food }
                    Task { await remove(foods) }
                }
                ForEach(unranked) { food in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.displayName)
                        Text("Measured per \(food.servingLabel) - can't be ranked per 100g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    let foods = offsets.map { unranked[$0] }
                    Task { await remove(foods) }
                }
                Button {
                    showingAddBrand = true
                } label: {
                    Label("Add Brand", systemImage: "plus.circle.fill")
                }
            }

            Section {
                Button("Rename") {
                    renameText = summary.group.name
                    showingRename = true
                }
                Button("Delete Group", role: .destructive) {
                    confirmingDelete = true
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle(summary.group.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddBrand) {
            FoodPickerView(mealSlotName: summary.group.name) { food, _ in
                Task { await add(food) }
            }
        }
        .alert("Rename Group", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await rename() } }
        }
        .confirmationDialog("Delete this group?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Group", role: .destructive) { Task { await deleteGroup() } }
        } message: {
            Text("The foods themselves stay - only the link between them is removed.")
        }
    }

    private func brandRow(_ item: FoodPer100, isBest: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.food.displayName)
                    if isBest {
                        Text("BEST")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(String(format: "per 100g: %d kcal \u{00b7} P %.1f \u{00b7} C %.1f \u{00b7} F %.1f", Int(item.calories.rounded()), item.proteinG, item.carbsG, item.fatG))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(metric.formatted(metric.value(of: item)))
                .font(.subheadline.bold())
        }
    }

    private func reload() async {
        if let updated = try? await repository.fetchSummaries().first(where: { $0.id == summary.id }) {
            summary = updated
        }
        onChange()
    }

    private func add(_ food: Food) async {
        do {
            try await repository.addMember(groupId: summary.group.id, foodId: food.id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ foods: [Food]) async {
        do {
            for food in foods {
                try await repository.removeMember(groupId: summary.group.id, foodId: food.id)
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename() async {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await repository.rename(id: summary.group.id, name: name)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteGroup() async {
        do {
            try await repository.deleteGroup(id: summary.group.id)
            onChange()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
