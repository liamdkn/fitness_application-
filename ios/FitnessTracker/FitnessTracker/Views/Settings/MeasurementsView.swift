import SwiftUI

/// Every body measurement on record, whether it came with a check-in or was
/// typed in here, plus a way to add one any day.
struct MeasurementsView: View {
    @State private var measurements: [BodyMeasurement] = []
    @State private var adding = false
    @State private var errorMessage: String?
    @State private var loaded = false
    private let repository = BodyMeasurementRepository()

    var body: some View {
        List {
            if measurements.isEmpty && loaded {
                Text("No measurements yet. Tap + to add one - it doesn't need a check-in.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppRowBackground())
            }
            ForEach(Array(measurements.enumerated()), id: \.element.id) { index, measurement in
                let older = measurements.dropFirst(index + 1).first
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(date(measurement.measuredAt)).font(.headline)
                        Spacer()
                        Text(sourceName(measurement.source))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    line("Waist", measurement.waistCm, older?.waistCm)
                    line("Left bicep", measurement.leftBicepCm, older?.leftBicepCm)
                    line("Right bicep", measurement.rightBicepCm, older?.rightBicepCm)
                }
                .padding(.vertical, 2)
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await delete(measurement) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .listRowBackground(AppRowBackground())
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
                    .listRowBackground(Color.clear)
            }
        }
        .appScreen()
        .navigationTitle("Body Measurements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .appToolbarTint()
            }
        }
        .task { await load() }
        .sheet(isPresented: $adding, onDismiss: { Task { await load() } }) {
            AddMeasurementSheet()
        }
    }

    @ViewBuilder
    private func line(_ label: String, _ value: Double?, _ previous: Double?) -> some View {
        if let value {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f cm", value))
                if let previous {
                    Text(String(format: "%+.1f", value - previous))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
    }

    private func sourceName(_ source: String) -> String {
        switch source {
        case "weekly_checkin": "With a check-in"
        case "phase_start": "Start of a phase"
        default: "Added here"
        }
    }

    private func date(_ iso: String) -> String {
        DateFormatting.date(fromISODate: iso)?.formatted(date: .abbreviated, time: .omitted) ?? iso
    }

    private func load() async {
        do {
            measurements = try await repository.fetchRecent(limit: 100)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        loaded = true
    }

    private func delete(_ measurement: BodyMeasurement) async {
        do {
            try await repository.delete(id: measurement.id)
            measurements.removeAll { $0.id == measurement.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AddMeasurementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var waist = ""
    @State private var leftBicep = ""
    @State private var rightBicep = ""
    @State private var errorMessage: String?
    private let repository = BodyMeasurementRepository()

    private var values: [Double?] { [waist, leftBicep, rightBicep].map { Double($0) } }
    private var hasAny: Bool { values.contains { ($0 ?? 0) > 0 } }
    private var allValid: Bool {
        [waist, leftBicep, rightBicep].allSatisfy { $0.isEmpty || (Double($0) ?? 0) > 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    field("Waist", $waist)
                    field("Left bicep", $leftBicep)
                    field("Right bicep", $rightBicep)
                } footer: {
                    Text("Fill in whichever you measured. This is separate from check-ins.")
                }
                .listRowBackground(AppRowBackground())
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                        .listRowBackground(Color.clear)
                }
            }
            .appScreen()
            .navigationTitle("Add Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(!hasAny || !allValid)
                        .appToolbarTint()
                }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("cm").foregroundStyle(.secondary)
        }
    }

    private func save() async {
        do {
            try await repository.log(
                waistCm: Double(waist), leftBicepCm: Double(leftBicep), rightBicepCm: Double(rightBicep),
                goalId: nil, source: "manual", date: date
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
