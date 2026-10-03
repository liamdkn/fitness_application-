import SwiftUI

// The app's shared motion: rolling numbers, bars that fill, cards that ease
// in, and zoom transitions. Views use these rather than hand-rolling
// animations, so the feel stays the same everywhere and is tuned here.

extension View {
    /// A number that rolls digit by digit when its value changes (and when it
    /// first loads in from zero). Put it on the `Text` showing `value`.
    func rolling(_ value: Double) -> some View {
        self
            .contentTransition(.numericText(value: value))
            .animation(.snappy(duration: 0.5), value: value)
    }

    /// Motion every card gets: it eases up into place the first time it
    /// appears (cards lower on the screen a beat later), and fades and
    /// shrinks slightly as it scrolls off an edge.
    func cardMotion() -> some View {
        self
            .modifier(CardEntrance())
            .scrollTransition(.animated(.smooth).threshold(.visible(0.85))) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.55)
                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
            }
    }

    /// Marks a view as the thing a pushed screen zooms out of.
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        matchedTransitionSource(id: id, in: namespace)
    }

    /// Makes a pushed screen zoom out of (and back into) its source.
    func zoomDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        navigationTransition(.zoom(sourceID: id, in: namespace))
    }
}

/// Fade and rise into place on first appearance, staggered by how far down
/// the screen the card sits so the page builds top to bottom.
private struct CardEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var minY: CGFloat = 0

    private static let stagger = 0.28

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { minY = $0 }
            .task {
                guard !shown, !reduceMotion else { return }
                // Let the first layout pass report the card's position.
                try? await Task.sleep(nanoseconds: 40_000_000)
                let delay = Double(max(0, min(minY / 900, 1))) * Self.stagger
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                withAnimation(.spring(duration: 0.55, bounce: 0.12)) { shown = true }
            }
    }
}

/// A progress bar that fills from empty when it appears and glides to new
/// values, instead of jumping. Takes its colour from `.tint(...)`.
struct AppProgressBar: View {
    let value: Double
    var total: Double = 1

    @State private var shown = 0.0

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(.tint)
                        .frame(width: geometry.size.width * shown)
                }
            }
            .onAppear { withAnimation(.smooth(duration: 0.9)) { shown = fraction } }
            .onChange(of: fraction) { _, new in withAnimation(.smooth(duration: 0.6)) { shown = new } }
            .accessibilityElement()
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}
