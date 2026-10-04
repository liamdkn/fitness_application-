import SwiftUI

/// What shows while the app starts: the app's own background, its mark, and a
/// quiet progress dot - then it fades away into the app. Picks up exactly
/// where the system launch screen (a flat colour, `LaunchBackground`) leaves
/// off, so there's no flash between the two.
struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 124, height: 124)
                    .glassEffect(.regular, in: Circle())
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                Text("Fitness Tracker")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
                    .padding(.top, 6)
            }
            .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fitness Tracker is starting")
    }
}

#Preview {
    LaunchView()
}
