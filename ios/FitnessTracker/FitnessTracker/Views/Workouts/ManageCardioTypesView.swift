import SwiftUI

/// Checkbox list over the full `CardioType` catalog, letting the user pick
/// which ones show up in Start Cardio Session's quick-pick list. At least
/// one must stay checked - an empty list would leave that picker with
/// nothing to select.
struct ManageCardioTypesView: View {
    let enabledTypes: [CardioType]
    let onSave: ([CardioType]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<CardioType>

    init(enabledTypes: [CardioType], onSave: @escaping ([CardioType]) async -> Void) {
        self.enabledTypes = enabledTypes
        self.onSave = onSave
        _selected = State(initialValue: Set(enabledTypes))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(CardioType.allCases) { type in
                        Button {
                            toggle(type)
                        } label: {
                            HStack {
                                Text(type.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(type) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Choose which cardio types show up in your quick-pick list.")
                }
            }
            .navigationTitle("Cardio Types")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let ordered = CardioType.allCases.filter { selected.contains($0) }
                        Task {
                            await onSave(ordered)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ type: CardioType) {
        if selected.contains(type) {
            guard selected.count > 1 else { return }
            selected.remove(type)
        } else {
            selected.insert(type)
        }
    }
}
