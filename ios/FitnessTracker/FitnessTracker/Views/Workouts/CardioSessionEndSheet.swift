import SwiftUI

struct CardioSessionEndSheet: View {
    var initialStepsAfter: Int?
    var initialAvgHeartRate: Int?
    /// Whether this cardio type generates steps at all - types like Bike/
    /// Rowing/Swimming never collected a "steps before," so there's nothing
    /// meaningful to diff against and this field is skipped entirely.
    var requiresSteps = true
    /// True when ending a live session (offers Discard/Save Anyway on
    /// cancel). False when filling in missing details later from history,
    /// where there's nothing to discard - Cancel just dismisses.
    var allowsCancelActions = true
    /// For a soft sanity check on "Steps Now" - either one missing (no
    /// `stepsBefore` to diff against, or the session's duration isn't
    /// known) just skips the check entirely rather than guessing.
    var stepsBefore: Int?
    var elapsedMinutes: Double?
    let onSave: (Int?, Int) async -> Void
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
        requiresSteps: Bool = true,
        allowsCancelActions: Bool = true,
        stepsBefore: Int? = nil,
        elapsedMinutes: Double? = nil,
        onSave: @escaping (Int?, Int) async -> Void,
        onDiscard: (() async -> Void)? = nil,
        onSaveWithoutDetails: (() async -> Void)? = nil
    ) {
        self.initialStepsAfter = initialStepsAfter
        self.initialAvgHeartRate = initialAvgHeartRate
        self.requiresSteps = requiresSteps
        self.allowsCancelActions = allowsCancelActions
        self.stepsBefore = stepsBefore
        self.elapsedMinutes = elapsedMinutes
        self.onSave = onSave
        self.onDiscard = onDiscard
        self.onSaveWithoutDetails = onSaveWithoutDetails
        _stepsAfterText = State(initialValue: initialStepsAfter.map { String($0) } ?? "")
        _avgHeartRateText = State(initialValue: initialAvgHeartRate.map { String($0) } ?? "")
    }

    private var stepsAfterValue: Int? { Int(stepsAfterText) }
    private var avgHeartRateValue: Int? { Int(avgHeartRateText) }

    /// Soft, non-blocking sanity check - flags a steps-now value implying
    /// an unrealistic pace (the classic fat-fingered extra digit, e.g.
    /// 30000 instead of 3000), same "looks off" pattern
    /// `EditableSetRow` already uses for a set's weight/reps. Never blocks
    /// Save - it's just a nudge to double check, not a hard rule.
    private var stepsAfterLooksOff: Bool {
        guard let stepsBefore, let elapsedMinutes, elapsedMinutes > 0, let stepsAfterValue else { return false }
        let delta = stepsAfterValue - stepsBefore
        guard delta > 0 else { return false }
        return Double(delta) / elapsedMinutes > 250
    }

    private var isValid: Bool {
        (!requiresSteps || stepsAfterValue != nil) && avgHeartRateValue != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Finish Session") {
                    if requiresSteps {
                        HStack {
                            Text("Steps Now")
                            Spacer()
                            TextField("-", text: $stepsAfterText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(stepsAfterLooksOff ? Color.orange : Color.clear, lineWidth: 1.5)
                                )
                        }
                        if stepsAfterLooksOff {
                            Text("That's a fast pace for this session's length - double check this number.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
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
                        guard let avgHeartRate = avgHeartRateValue else { return }
                        isSaving = true
                        Task {
                            await onSave(requiresSteps ? stepsAfterValue : nil, avgHeartRate)
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
                Text("You can discard this session entirely, or save it now and fill in details later from Cardio History.")
            }
        }
    }
}
