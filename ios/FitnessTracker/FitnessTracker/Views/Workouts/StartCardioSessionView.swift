import SwiftUI

struct StartCardioSessionView: View {
    /// Preselects the type when opened from a scheduled active-rest day
    /// (see `StartWorkoutView`'s week carousel) - still changeable, just a
    /// better default than always landing on Incline Walk.
    var initialCardioType: CardioType = .inclineTreadmill

    @State private var cardioType: CardioType = .inclineTreadmill
    @State private var enabledTypes: [CardioType] = [.inclineTreadmill, .stairmaster]
    @State private var showingManageTypes = false
    @State private var stepsBeforeText = ""
    @State private var errorMessage: String?
    @State private var isStarting = false
    @State private var startedSession: CardioTrackingSession?
    private let repository = CardioSessionRepository()
    private let preferencesRepository = UserPreferencesRepository()

    init(initialCardioType: CardioType = .inclineTreadmill) {
        self.initialCardioType = initialCardioType
        _cardioType = State(initialValue: initialCardioType)
    }

    private var stepsBeforeValue: Int? { Int(stepsBeforeText) }

    private var isValid: Bool {
        !cardioType.involvesSteps || stepsBeforeValue != nil
    }

    var body: some View {
        Form {
            Section("Cardio Type") {
                Picker("Type", selection: $cardioType) {
                    ForEach(enabledTypes) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Button("Add to List") {
                    showingManageTypes = true
                }
            }

            if cardioType.involvesSteps {
                Section("Before You Start") {
                    HStack {
                        Text("Current Steps")
                        Spacer()
                        TextField("-", text: $stepsBeforeText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }

            Section {
                Button {
                    Task { await start() }
                } label: {
                    if isStarting {
                        ProgressView()
                    } else {
                        Text("Start")
                    }
                }
                .disabled(!isValid || isStarting)
            }
        }
        .appScreen()
        .navigationTitle("Start Cardio")
        .scrollDismissesKeyboard(.interactively)
        .navigationDestination(item: $startedSession) { session in
            CardioSessionLiveView(session: session)
        }
        .task { await loadEnabledTypes() }
        .sheet(isPresented: $showingManageTypes) {
            ManageCardioTypesView(enabledTypes: enabledTypes) { updated in
                await saveEnabledTypes(updated)
            }
        }
    }

    private func loadEnabledTypes() async {
        do {
            let preferences = try await preferencesRepository.fetch()
            var types = preferences.enabledCardioTypes.compactMap(CardioType.init(rawValue:))
            if types.isEmpty { types = [.inclineTreadmill, .stairmaster] }
            // A day scheduled as Active Rest (e.g. a Run) should preselect
            // that type even if it isn't in the user's usual short list -
            // otherwise `applyEnabledTypes` below would silently swap the
            // selection back to whatever's first the moment this loads.
            if !types.contains(initialCardioType) {
                types.insert(initialCardioType, at: 0)
            }
            applyEnabledTypes(types)
        } catch {
            // Advisory only - the built-in default list still works offline.
        }
    }

    private func saveEnabledTypes(_ types: [CardioType]) async {
        applyEnabledTypes(types)
        do {
            try await preferencesRepository.setEnabledCardioTypes(types)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Keeps the current selection valid whenever the enabled list changes -
    /// otherwise unchecking the currently-selected type in "Add to List"
    /// would leave `cardioType` pointing at a type no longer in the picker.
    private func applyEnabledTypes(_ types: [CardioType]) {
        enabledTypes = types
        if !types.contains(cardioType) {
            cardioType = types.first ?? .other
        }
    }

    private func start() async {
        guard isValid else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let session = try await repository.startSession(
                cardioType: cardioType,
                stepsBefore: cardioType.involvesSteps ? stepsBeforeValue : nil
            )
            CardioSessionMonitor.shared.sessionStarted(session)
            startedSession = session
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
