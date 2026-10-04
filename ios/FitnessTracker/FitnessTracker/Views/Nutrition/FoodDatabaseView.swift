import SwiftUI

/// The food database: every food the app knows (shared catalogue plus your own
/// foods), searchable and filterable, with a button to add a new one. Tapping
/// a food goes back to the Add Food flow's usual check-then-quantity steps.
struct FoodDatabaseView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case all = "All", verified = "Verified", mine = "Mine"
        var id: String { rawValue }
    }

    /// Called with the chosen food once this screen has closed.
    let onSelect: (Food) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var foods: [Food] = []
    @State private var searchText = ""
    @State private var scope: Scope = .all
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingAddFood = false
    private let repository = FoodRepository()

    private var shown: [Food] {
        foods.filter {
            switch scope {
            case .all: true
            case .verified: $0.isVerified
            case .mine: $0.isCustom
            }
        }
    }

    var body: some View {
        List {
            Button {
                showingAddFood = true
            } label: {
                Label("Add New Food to Database", systemImage: "plus")
            }
            .buttonStyle(.appPrimary)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            Picker("Show", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(AppColor.error)
                    .listRowBackground(Color.clear)
            }

            if shown.isEmpty && !isLoading {
                Text(searchText.isEmpty ? "Nothing here yet." : "No foods match that search.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                Section("\(shown.count) food\(shown.count == 1 ? "" : "s")") {
                    ForEach(shown) { food in
                        row(food)
                    }
                }
                .listRowBackground(AppRowBackground())
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search the database")
        // Re-runs (cancelling the previous run) on every keystroke; the pause
        // keeps a fast typist from firing a request per letter.
        .task(id: searchText) {
            if !searchText.isEmpty { try? await Task.sleep(nanoseconds: 250_000_000) }
            guard !Task.isCancelled else { return }
            await load()
        }
        .sheet(isPresented: $showingAddFood) {
            AddCustomFoodView(onCreated: { _ in Task { await load() } })
        }
        .appScreen()
        .navigationTitle("Food Database")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ food: Food) -> some View {
        Button {
            dismiss()
            // Let this screen finish closing before the picker presents the next sheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onSelect(food) }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.displayName)
                        .foregroundStyle(Color.primary)
                    Text(detail(food))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 8)
                if food.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppColor.success)
                }
            }
        }
    }

    private func detail(_ food: Food) -> String {
        "\(Int(food.calories)) kcal per \(food.servingLabel) \u{00b7} P \(Int(food.proteinG.rounded())) \u{00b7} C \(Int(food.carbsG.rounded())) \u{00b7} F \(Int(food.fatG.rounded()))"
    }

    private func load() async {
        defer { isLoading = false }
        do {
            foods = try await repository.browse(query: searchText)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
