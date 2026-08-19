import SwiftUI

struct StartCardioSessionView: View {
    @State private var cardioType: CardioType = .treadmill
    @State private var stepsBeforeText = ""
    @State private var errorMessage: String?
    @State private var isStarting = false
    @State private var startedSession: CardioTrackingSession?
    private let repository = CardioSessionRepository()

    private var stepsBeforeValue: Int? { Int(stepsBeforeText) }

    var body: some View {
        Form {
            Section("Cardio Type") {
                Picker("Type", selection: $cardioType) {
                    ForEach(CardioType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

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

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
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
                .disabled(stepsBeforeValue == nil || isStarting)
            }
        }
        .navigationTitle("Start Cardio")
        .navigationDestination(item: $startedSession) { session in
            CardioSessionLiveView(session: session)
        }
    }

    private func start() async {
        guard let stepsBefore = stepsBeforeValue else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let session = try await repository.startSession(cardioType: cardioType, stepsBefore: stepsBefore)
            CardioSessionMonitor.shared.sessionStarted(session)
            startedSession = session
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
