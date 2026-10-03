import SwiftUI

/// Picks a past date to copy every meal entry from, onto whichever date
/// the Nutrition tab currently has selected - "repeat yesterday" is just
/// this pre-filled with yesterday's date, so both live behind the same
/// sheet rather than two separate flows.
struct RepeatDaySheet: View {
    let targetDate: Date
    let onRepeat: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sourceDate: Date

    init(targetDate: Date, onRepeat: @escaping (Date) -> Void) {
        self.targetDate = targetDate
        self.onRepeat = onRepeat
        _sourceDate = State(initialValue: Calendar.current.date(byAdding: .day, value: -1, to: targetDate) ?? targetDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Copy from",
                        selection: $sourceDate,
                        in: ...targetDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                } footer: {
                    Text("Copies every food/recipe logged on that day onto \(targetDate, style: .date). Doesn't touch what's already logged there.")
                }
            }
            .appScreen()
            .navigationTitle("Repeat a Day")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Repeat") {
                        onRepeat(sourceDate)
                        dismiss()
                    }
                }
            }
        }
    }
}
