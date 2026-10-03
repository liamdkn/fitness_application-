import SwiftUI

/// A single Apple Watch-style glossy ring for one 0-100 score, with the
/// rounded value in the center (angular gradient fill, glassy end-cap
/// "puck") - so any single score, the daily adherence score today, the
/// weekly one later, can render as a ring on its own.
struct ScoreRingView: View {
    let score: Double
    var color: Color = AppColor.success
    var diameter: CGFloat = 96
    var ringWidth: CGFloat = 12

    private var progress: Double { min(max(score / 100, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.lightened(by: 0.82), lineWidth: ringWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: color.darkened(by: 0.12), location: 0),
                            .init(color: color, location: 0.55),
                            .init(color: color.lightened(by: 0.35), location: 1)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if progress > 0.015 {
                puck
            }

            Text("\(Int(score.rounded()))")
                .font(.system(size: diameter * 0.3, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.3), value: score)
    }

    private var puck: some View {
        let capAngle = Angle.degrees(-90 + 360 * progress)
        let radius = diameter / 2
        return ZStack {
            Capsule()
                .fill(color)
                .frame(width: ringWidth * 0.95, height: ringWidth * 1.35)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: ringWidth * 0.65, height: ringWidth * 0.75)
                .offset(y: -ringWidth * 0.22)
        }
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1.5)
        .rotationEffect(capAngle)
        .offset(x: radius * cos(capAngle.radians), y: radius * sin(capAngle.radians))
    }
}

#Preview {
    ScoreRingView(score: 87, color: AppColor.success)
}
