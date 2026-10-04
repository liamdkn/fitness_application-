import SwiftUI

/// The app's screen background: the `AppColor.backgroundTop` to
/// `backgroundBottom` gradient with a soft blue glow that slowly swells and
/// fades, like breathing. It holds still when Reduce Motion is on.
struct AppBackground: View {
    /// Seconds for one full breath in and out.
    static let breathPeriod: TimeInterval = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            layers(breath: 0.5)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                // 0 ... 1, easing in and out.
                layers(breath: (sin(t * 2 * .pi / Self.breathPeriod) + 1) / 2)
            }
        }
    }

    private func layers(breath: Double) -> some View {
        ZStack {
            LinearGradient(
                colors: [AppColor.backgroundTop, AppColor.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [AppColor.backgroundGlow.opacity(0.10 + 0.22 * breath), .clear],
                center: UnitPoint(x: 0.5, y: 0.05 + 0.10 * breath),
                startRadius: 0,
                endRadius: 360 + 140 * breath
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Puts the app background behind a screen and everything pushed from it,
    /// and hides the opaque backgrounds lists and forms draw so it shows
    /// through. Must sit inside the `NavigationStack` - use
    /// `AppNavigationStack`, which does.
    func appScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .containerBackground(for: .navigation) { AppBackground() }
    }
}

extension View {
    /// The app's card surface: Liquid Glass in a rounded rectangle. Every card
    /// uses this (`DashboardCard`, the day card, the week strip), so changing
    /// the look of cards is one edit here.
    func appCard(cornerRadius: CGFloat = AppButtonStyle.largeCornerRadius) -> some View {
        self
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay { CardGlowOverlay(cornerRadius: cornerRadius) }
            .cardMotion()
    }
}

extension View {
    /// Nav-bar buttons (Cancel, Done, Save...) in the normal text colour -
    /// white in dark mode - instead of the accent blue. Put on the content of
    /// each `ToolbarItem`. (`Color.primary` rather than `.primary`, which
    /// would pick up the blue tint.)
    func appToolbarTint() -> some View {
        self.tint(Color.primary)
    }
}

/// The background of List and Form rows: frosted, translucent glass instead of
/// the system's opaque grouped grey. Every `Section` applies it with
/// `.listRowBackground(AppRowBackground())`. (Real `glassEffect` per row stacks
/// a bright rim between every pair of rows, so rows use the material.)
struct AppRowBackground: View {
    /// How opaque the frosting is, 0 (clear) to 1 (the full material). Lower
    /// it to see more of the background through the lists.
    static let frost = 0.4

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(Self.frost)
            .overlay(Color.white.opacity(0.03))
    }
}

/// A `NavigationStack` with the app background applied to every screen in it.
/// Each tab's root uses this instead of a plain `NavigationStack`.
struct AppNavigationStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content.appScreen()
        }
        // On the stack as well as its root, so pushed screens get it too.
        .scrollContentBackground(.hidden)
        .containerBackground(for: .navigation) { AppBackground() }
    }
}
