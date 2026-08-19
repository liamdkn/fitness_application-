import SwiftUI

struct CardioStepsSheet: View {
    let sessions: [CardioStepSession]
    let onSave: (Int, Int) async -> Void
    let onDelete: (UUID) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var beforeText = ""
    @State private var afterText = ""

    private var beforeValue: Int? { Int(beforeText) }
    private var afterValue: Int? { Int(afterText) }

    private var isValid: Bool {
        guard let before = beforeValue, let after = afterValue else { return false }
        return after >= before
    }

    var body: some View {
        NavigationStack {
            List {
                if !sessions.isEmpty {
                    Section("Today's Sessions") {
                        ForEach(sessions) { session in
                            HStack {
                                Text("\(session.stepsBefore) \u{2192} \(session.stepsAfter)")
                                Spacer()
                                Text("+\(session.stepsDelta)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let id = sessions[index].id
                                Task { await onDelete(id) }
                            }
                        }
                    }
                }

                Section("New Session") {
                    TextField("Steps Before Cardio", text: $beforeText)
                        .keyboardType(.numberPad)
                    TextField("Steps After Cardio", text: $afterText)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Cardio Steps")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let before = beforeValue, let after = afterValue else { return }
                        Task {
                            await onSave(before, after)
                            beforeText = ""
                            afterText = ""
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
