import SwiftUI

/// Log today's water either by tapping a saved container (a hydroflask, a
/// pint glass, ...) or by typing a one-off amount - "Edit" manages the
/// container list itself (`WaterContainersEditView`), reachable from here
/// rather than tucked away in Settings, since it's what actually gets
/// adjusted while logging water day to day.
struct WaterLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var containers: [WaterContainer] = []
    @State private var todayLogs: [WaterLog] = []
    @State private var customAmountText = ""
    @State private var errorMessage: String?
    @State private var showingEditContainers = false
    private let repository = WaterRepository()

    private var totalMl: Int {
        todayLogs.reduce(0) { $0 + $1.amountMl }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(formattedAmount(totalMl))
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(Color.clear)

                if !containers.isEmpty {
                    Section("Add") {
                        ForEach(containers) { container in
                            Button {
                                Task { await addLog(amountMl: container.volumeMl, containerId: container.id) }
                            } label: {
                                HStack {
                                    Text(container.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("+\(container.volumeMl) ml")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Custom Amount") {
                    HStack {
                        TextField("e.g. 250", text: $customAmountText)
                            .keyboardType(.numberPad)
                        Text("ml").foregroundStyle(.secondary)
                        Button("Add") {
                            Task { await addCustomAmount() }
                        }
                        .disabled((Int(customAmountText) ?? 0) <= 0)
                    }
                }

                if !todayLogs.isEmpty {
                    Section("Today") {
                        ForEach(todayLogs) { log in
                            HStack {
                                Text(containerName(for: log))
                                Spacer()
                                Text("\(log.amountMl) ml").foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: removeLogs)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Water")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") { showingEditContainers = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingEditContainers, onDismiss: { Task { await loadContainers() } }) {
                NavigationStack {
                    WaterContainersEditView()
                }
            }
        }
    }

    private func containerName(for log: WaterLog) -> String {
        guard let containerId = log.containerId else { return "Custom" }
        return containers.first { $0.id == containerId }?.name ?? "Custom"
    }

    private func formattedAmount(_ ml: Int) -> String {
        ml >= 1000 ? String(format: "%.2f L", Double(ml) / 1000) : "\(ml) ml"
    }

    private func load() async {
        await loadContainers()
        await loadTodayLogs()
    }

    private func loadContainers() async {
        do {
            containers = try await repository.fetchContainers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadTodayLogs() async {
        do {
            todayLogs = try await repository.fetchLogs(date: Date())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addLog(amountMl: Int, containerId: UUID?) async {
        do {
            let log = try await repository.addLog(date: Date(), amountMl: amountMl, containerId: containerId)
            todayLogs.append(log)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addCustomAmount() async {
        guard let amount = Int(customAmountText), amount > 0 else { return }
        customAmountText = ""
        await addLog(amountMl: amount, containerId: nil)
    }

    private func removeLogs(at offsets: IndexSet) {
        let toRemove = offsets.map { todayLogs[$0] }
        todayLogs.remove(atOffsets: offsets)
        Task {
            for log in toRemove {
                do {
                    try await repository.deleteLog(id: log.id)
                } catch {
                    // Deletion failed server-side - put it back rather than
                    // leaving the UI showing it as gone when it isn't.
                    errorMessage = error.localizedDescription
                    todayLogs.append(log)
                    todayLogs.sort { $0.loggedAt < $1.loggedAt }
                }
            }
        }
    }
}
