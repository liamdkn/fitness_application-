import SwiftUI

/// CRUD list of the user's gyms, plus which one a new workout defaults to -
/// see `Gym`'s doc comment on `Workout.gymId` for why this exists: weight
/// suggestions prefer history from the same gym, since equipment (dumbbell
/// jumps, machine brands) commonly differs between them.
struct GymsSettingsView: View {
    @State private var gyms: [Gym] = []
    @State private var preferredGymId: UUID?
    @State private var errorMessage: String?
    @State private var showingAddGym = false
    @State private var newGymName = ""
    @State private var renamingGym: Gym?
    @State private var renameText = ""
    private let gymRepository = GymRepository()
    private let preferencesRepository = UserPreferencesRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            if gyms.isEmpty {
                Section {
                    Text("Add your gym(s) below - tracking which one a workout happened at keeps weight suggestions from mixing up different equipment.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Picker("Preferred Gym", selection: $preferredGymId) {
                        Text("None").tag(UUID?.none)
                        ForEach(gyms) { gym in
                            Text(gym.name).tag(Optional(gym.id))
                        }
                    }
                    .onChange(of: preferredGymId) { _, newValue in
                        Task { await savePreferredGym(newValue) }
                    }
                } header: {
                    Text("Preferred Gym")
                } footer: {
                    Text("What a new workout starts logged against by default - still changeable per session from within the workout itself.")
                }
            }

            Section("Gyms") {
                ForEach(gyms) { gym in
                    Text(gym.name)
                        .contextMenu {
                            Button("Rename") {
                                renamingGym = gym
                                renameText = gym.name
                            }
                        }
                }
                .onDelete(perform: removeGyms)
                Button {
                    showingAddGym = true
                } label: {
                    Label("Add Gym", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Gyms")
        .task { await load() }
        .alert("New Gym", isPresented: $showingAddGym) {
            TextField("e.g. Navan Gym", text: $newGymName)
            Button("Cancel", role: .cancel) { newGymName = "" }
            Button("Add") { Task { await addGym() } }
        } message: {
            Text("What's this gym called?")
        }
        .alert("Rename Gym", isPresented: renamingGymBinding) {
            TextField("e.g. Navan Gym", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await renameGym() } }
        } message: {
            Text("What's this gym called?")
        }
    }

    private var renamingGymBinding: Binding<Bool> {
        Binding(get: { renamingGym != nil }, set: { if !$0 { renamingGym = nil } })
    }

    private func load() async {
        do {
            gyms = try await gymRepository.fetchAll()
            preferredGymId = try? await preferencesRepository.fetch().preferredGymId
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addGym() async {
        guard !newGymName.isEmpty else { return }
        let name = newGymName
        newGymName = ""
        do {
            let gym = try await gymRepository.create(name: name)
            gyms.append(gym)
            gyms.sort { $0.name < $1.name }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameGym() async {
        guard let renamingGym, !renameText.isEmpty else { return }
        do {
            let updated = try await gymRepository.rename(id: renamingGym.id, name: renameText)
            if let index = gyms.firstIndex(where: { $0.id == updated.id }) {
                gyms[index] = updated
            }
            gyms.sort { $0.name < $1.name }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeGyms(at offsets: IndexSet) {
        let toRemove = offsets.map { gyms[$0] }
        gyms.remove(atOffsets: offsets)
        Task {
            for gym in toRemove {
                do {
                    try await gymRepository.delete(id: gym.id)
                    if preferredGymId == gym.id {
                        preferredGymId = nil
                    }
                } catch {
                    // Deletion failed server-side - put it back rather than
                    // leaving the UI showing it as gone when it isn't.
                    errorMessage = error.localizedDescription
                    gyms.append(gym)
                    gyms.sort { $0.name < $1.name }
                }
            }
        }
    }

    private func savePreferredGym(_ gymId: UUID?) async {
        do {
            try await preferencesRepository.setPreferredGym(gymId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
