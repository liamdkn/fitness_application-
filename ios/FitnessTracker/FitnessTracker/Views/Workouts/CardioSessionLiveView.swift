import Combine
import SwiftUI

// Deliberately no .navigationBarBackButtonHidden() here, unlike
// ActiveWorkoutView - the point of this screen is that the user can leave
// and come back. Backing out just pops the view; the session keeps running
// server-side, and the Train tab's resume banner (via CardioSessionMonitor)
// is the way back in.
struct CardioSessionLiveView: View {
    @StateObject private var viewModel: CardioSessionViewModel
    @State private var elapsed: TimeInterval = 0
    @State private var showingEndCapture = false
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: CardioTrackingSession) {
        _viewModel = StateObject(wrappedValue: CardioSessionViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(viewModel.session.cardioType.displayName)
                .font(.title2.bold())

            Text(formattedElapsed)
                .font(.system(size: 56, weight: .bold, design: .monospaced))

            if viewModel.session.isPaused {
                Text("Paused")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                Button {
                    Task {
                        if viewModel.session.isPaused {
                            await viewModel.resume()
                        } else {
                            await viewModel.pause()
                        }
                    }
                } label: {
                    Text(viewModel.session.isPaused ? "Resume" : "Pause")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isMutating)

                Button {
                    showingEndCapture = true
                } label: {
                    Text("End")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isMutating)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 60)
        .navigationTitle("Cardio Session")
        .onReceive(timer) { _ in
            elapsed = viewModel.session.elapsed()
        }
        .onAppear {
            elapsed = viewModel.session.elapsed()
        }
        .sheet(isPresented: $showingEndCapture) {
            CardioSessionEndSheet(
                requiresSteps: viewModel.session.cardioType.involvesSteps,
                onSave: { stepsAfter, avgHeartRate in
                    await viewModel.finish(stepsAfter: stepsAfter, avgHeartRate: avgHeartRate)
                },
                onDiscard: {
                    await viewModel.discard()
                },
                onSaveWithoutDetails: {
                    await viewModel.finishWithoutDetails()
                }
            )
        }
        .onChange(of: viewModel.isFinished) { _, finished in
            if finished { dismiss() }
        }
    }

    private var formattedElapsed: String {
        let total = Int(max(elapsed, 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
