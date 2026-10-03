import SwiftUI
import Combine

/// The "app just opened" moment: card edges glow up and fade out, each card a
/// beat after the one above it. `play()` starts it; `appCard()` (and so every
/// card) listens through `CardGlowOverlay`. Called when the app launches and
/// when it comes back after being away a while - not on every tab switch.
@MainActor
final class AppIntro: ObservableObject {
    static let shared = AppIntro()

    /// Bumped each time the intro plays; cards react to the change.
    @Published private(set) var generation = 0
    private(set) var startedAt = Date.distantPast

    /// How long away counts as "reopening the app".
    static let awayThreshold: TimeInterval = 60
    /// Cards appearing this soon after `play()` join in (a screen that loads
    /// a moment after launch should still glow).
    static let joinWindow: TimeInterval = 3

    private init() {}

    func play() {
        startedAt = Date()
        generation += 1
    }

    var isPlaying: Bool { Date().timeIntervalSince(startedAt) < Self.joinWindow }
}

/// A card's glowing edge: a soft blurred stroke plus a thin crisp one,
/// a fast flash up and a short fade out. Invisible the rest of the time.
struct CardGlowOverlay: View {
    let cornerRadius: CGFloat

    @ObservedObject private var intro = AppIntro.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = 0.0
    @State private var minY: CGFloat = 0

    private static let riseDuration = 0.12
    private static let fadeDuration = 0.55
    /// Total stagger from the top of the screen to the bottom.
    private static let stagger = 0.22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(AppColor.cardGlow, lineWidth: 5)
                .blur(radius: 7)
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(AppColor.cardGlow, lineWidth: 1.5)
        }
        .opacity(glow)
        .allowsHitTesting(false)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { minY = $0 }
        .task(id: intro.generation) { await play() }
    }

    private func play() async {
        guard !reduceMotion, intro.generation > 0, intro.isPlaying else { return }
        glow = 0
        let delay = Double(max(0, min(minY / 900, 1))) * Self.stagger
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: Self.riseDuration)) { glow = 1 }
        try? await Task.sleep(nanoseconds: UInt64((Self.riseDuration + 0.02) * 1_000_000_000))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: Self.fadeDuration)) { glow = 0 }
    }
}
