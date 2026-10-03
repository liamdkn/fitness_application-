import SwiftUI

/// The app's one button look. Pick a kind (what it means) and a size (where
/// it sits) instead of reaching for `.bordered` / `.borderedProminent`:
///
/// - `.appPrimary` - the main action on a card or screen: grey button fill.
/// - `.appSecondary` - a lesser action: faint grey fill, normal text.
/// - `.appDestructive` - cancel / delete: red-tinted fill.
///
/// Each has a `Compact` twin for buttons that sit inline with other content
/// (the default sizes fill the width and are tall, like the Start Workout
/// button). Colours come from `AppColor`; the large corner radius matches the
/// cards the buttons sit in, so changing it here keeps the two in step.
struct AppButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    enum Size { case large, compact }

    /// Shared by large buttons and the cards that hold them.
    static let largeCornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 12

    var kind: Kind = .primary
    var size: Size = .large

    @Environment(\.isEnabled) private var isEnabled

    private var tint: Color { kind == .destructive ? AppColor.danger : AppColor.button }
    private var radius: CGFloat { size == .large ? Self.largeCornerRadius : Self.compactCornerRadius }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: .primary
        case .destructive: AppColor.danger
        }
    }

    /// Liquid Glass: the primary button is glass with a light wash of the
    /// button colour (a heavier tint turns it opaque and loses the glass), a
    /// secondary one is plain glass, a destructive one has a red wash.
    /// `interactive` gives the press shimmer, so no separate pressed state is
    /// needed.
    private var glass: Glass {
        switch kind {
        case .primary: .regular.tint(tint.opacity(0.35)).interactive()
        case .secondary: .regular.interactive()
        case .destructive: .regular.tint(tint.opacity(0.35)).interactive()
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size == .large ? .body.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: size == .large ? .infinity : nil)
            .padding(.horizontal, size == .large ? 16 : 14)
            .padding(.vertical, size == .large ? 12 : 8)
            .glassEffect(glass, in: RoundedRectangle(cornerRadius: radius))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var appPrimary: AppButtonStyle { AppButtonStyle(kind: .primary, size: .large) }
    static var appSecondary: AppButtonStyle { AppButtonStyle(kind: .secondary, size: .large) }
    static var appDestructive: AppButtonStyle { AppButtonStyle(kind: .destructive, size: .large) }
    static var appPrimaryCompact: AppButtonStyle { AppButtonStyle(kind: .primary, size: .compact) }
    static var appSecondaryCompact: AppButtonStyle { AppButtonStyle(kind: .secondary, size: .compact) }
    static var appDestructiveCompact: AppButtonStyle { AppButtonStyle(kind: .destructive, size: .compact) }
}

/// A square-ish glass tile button with an icon over a label (the meal screen's
/// Add Food / Recipes / Saved row, the quick-add buttons): accent-coloured
/// content on interactive Liquid Glass.
struct AppTileButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppColor.accent)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: AppButtonStyle.compactCornerRadius))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: AppButtonStyle.compactCornerRadius))
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == AppTileButtonStyle {
    static var appTile: AppTileButtonStyle { AppTileButtonStyle() }
}
