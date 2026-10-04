import SwiftUI

/// What shows while the app starts: the app's own background and its mark,
/// with a bright arc circling it, soft rings spreading outward and the lifter
/// giving a little bounce - then it fades away into the app. Picks up exactly
/// where the system launch screen (a flat colour, `LaunchBackground`) leaves
/// off, so there's no flash between the two. With Reduce Motion on it holds
/// still.
struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var spinning = false
    @State private var rippling = false

    private let markSize: CGFloat = 124

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 30) {
                mark
                Text("Fitness Tracker")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { spinning = true }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { rippling = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fitness Tracker is starting")
    }

    private var mark: some View {
        ZStack {
            if !reduceMotion {
                // Rings that spread out from the mark and fade, one after the other.
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .stroke(AppColor.accent.opacity(0.55), lineWidth: 2)
                        .frame(width: markSize, height: markSize)
                        .scaleEffect(rippling ? 1.9 : 1)
                        .opacity(rippling ? 0 : 0.7)
                        .animation(
                            .easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(index) * 0.9),
                            value: rippling
                        )
                }
            }

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .repeat(.periodic(delay: 0.5)), isActive: !reduceMotion)
                .frame(width: markSize, height: markSize)
                .glassEffect(.regular, in: Circle())
                .scaleEffect(appeared || reduceMotion ? 1 : 0.88)

            // A bright arc travelling round the edge.
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(
                    AngularGradient(
                        colors: [AppColor.accent.opacity(0), AppColor.accent, .white],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(100)
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .frame(width: markSize + 14, height: markSize + 14)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .opacity(reduceMotion ? 0 : 1)
        }
        .frame(width: markSize * 2, height: markSize * 2)
    }
}

#Preview {
    LaunchView()
}
