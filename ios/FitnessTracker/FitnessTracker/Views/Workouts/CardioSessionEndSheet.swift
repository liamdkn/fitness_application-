import SwiftUI

struct CardioSessionEndSheet: View {
    var initialStepsAfter: Int?
    var initialAvgHeartRate: Int?
    /// True when ending a live session (offers Discard/Save Anyway on
    /// cancel). False when filling in missing details later from history,
    /// where there's nothing to discard - Cancel just dismisses.
    var allowsCancelActions = true
    let onSave: (Int, Int) async -> Void
    var onDiscard: (() async -> Void)?
    var onSaveWithoutDetails: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var stepsAfterText: String
    @State private var avgHeartRateText: String
    @State private var isSaving = false
    @State private var showingCancelDialog = false

    init(
        initialStepsAfter: Int? = nil,
        initialAvgHeartRate: Int? = nil,
        allowsCancelActions: Bool = true,
        onSave: @escaping (Int, Int) async -> Void,
        onDiscard: (() async -> Void)? = nil,
        onSaveWithoutDetails: (() async -> Void)? = nil
    ) {
        self.initialStepsAfter = initialStepsAfter
        self.initialAvgHeartRate = initialAvgHeartRate
        self.allowsCancelActions = allowsCancelActions
        self.onSave = onSave
        self.onDiscard = onDiscard
        self.onSaveWithoutDetails = onSaveWithoutDetails
        _stepsAfterText = State(initialValue: initialStepsAfter.map { String($0) } ?? "")
        _avgHeartRateText = State(initialValue: initialAvgHeartRate.map { String($0) } ?? "")
    }

    private var stepsAfterValue: Int? { Int(stepsAfterText) }
    private var avgHeartRateValue: Int? { Int(avgHeartRateText) }

    private var isValid: Bool {
        stepsAfterValue != nil && avgHeartRateValue != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Finish Session") {
                    HStack {
                        Text("Steps Now")
                        Spacer()
                        TextField("-", text: $stepsAfterText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Average Heart Rate")
                        Spacer()
                        TextField("-", text: $avgHeartRateText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("bpm").foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
            .navigationTitle("End Session")
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if allowsCancelActions {
                            showingCancelDialog = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let stepsAfter = stepsAfterValue, let avgHeartRate = avgHeartRateValue else { return }
                        isSaving = true
                        Task {
                            await onSave(stepsAfter, avgHeartRate)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .confirmationDialog("Leave Without Finishing?", isPresented: $showingCancelDialog) {
                Button("Discard Session", role: .destructive) {
                    Task {
                        await onDiscard?()
                        dismiss()
                    }
                }
                Button("Save Anyway") {
                    Task {
                        await onSaveWithoutDetails?()
                        dismiss()
                    }
                }
            } message: {
                Text("You can discard this session entirely, or save it now and fill in steps and heart rate later from Cardio History.")
            }
        }
    }
}
