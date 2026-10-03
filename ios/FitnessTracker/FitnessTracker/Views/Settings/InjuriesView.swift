import SwiftUI

struct InjuriesView: View {
    @State private var injuries: [Injury] = []
    @State private var errorMessage: String?
    @State private var showingAdd = false
    private let injuryRepository = InjuryRepository()

    private var activeInjuries: [Injury] { injuries.filter(\.isActive) }
    private var resolvedInjuries: [Injury] { injuries.filter { !$0.isActive } }

    var body: some View {
        Form {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }

            if !activeInjuries.isEmpty {
                Section("Active") {
                    ForEach(activeInjuries) { injury in
                        injuryRow(injury)
                    }
                }
            }

            if !resolvedInjuries.isEmpty {
                Section("Resolved") {
                    ForEach(resolvedInjuries) { injury in
                        injuryRow(injury)
                    }
                }
            }

            if injuries.isEmpty {
                Text("No injuries logged.")
                    .foregroundStyle(.secondary)
            }
        }
        .appScreen()
        .navigationTitle("Injuries")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingAdd) {
            AddInjurySheet { muscleGroup, notes, startedAt in
                await addInjury(muscleGroup: muscleGroup, notes: notes, startedAt: startedAt)
            }
        }
    }

    @ViewBuilder
    private func injuryRow(_ injury: Injury) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(displayName(for: injury.muscleGroup))
                    .fontWeight(.semibold)
                Spacer()
                if injury.isActive {
                    Button("Mark Resolved") {
                        Task { await resolve(injury) }
                    }
                    .font(.caption)
                }
            }
            if let notes = injury.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(injury.isActive ? "Since \(injury.startedAt)" : "\(injury.startedAt) - \(injury.resolvedAt ?? "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await delete(injury) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func displayName(for muscleGroup: String) -> String {
        MuscleGroup(rawValue: muscleGroup)?.displayName ?? muscleGroup.capitalized
    }

    private func load() async {
        do {
            injuries = try await injuryRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addInjury(muscleGroup: String, notes: String, startedAt: Date) async {
        do {
            let injury = try await injuryRepository.addInjury(muscleGroup: muscleGroup, notes: notes, startedAt: startedAt)
            injuries.insert(injury, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolve(_ injury: Injury) async {
        do {
            let updated = try await injuryRepository.resolveInjury(id: injury.id)
            if let index = injuries.firstIndex(where: { $0.id == updated.id }) {
                injuries[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ injury: Injury) async {
        do {
            try await injuryRepository.deleteInjury(id: injury.id)
            injuries.removeAll { $0.id == injury.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AddInjurySheet: View {
    let onSave: (String, String, Date) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var muscleGroup: MuscleGroup = .shoulders
    @State private var notes = ""
    @State private var startedAt = Date()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Area") {
                    Picker("Muscle Group", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.displayName).tag(group)
                        }
                    }
                }
                Section("Details") {
                    DatePicker("Started", selection: $startedAt, in: ...Date(), displayedComponents: .date)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .appScreen()
            .navigationTitle("Log Injury")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            await onSave(muscleGroup.rawValue, notes, startedAt)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}
