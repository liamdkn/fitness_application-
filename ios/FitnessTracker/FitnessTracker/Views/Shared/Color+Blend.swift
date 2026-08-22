import SwiftUI
import UIKit

extension Color {
    /// Blends toward white by a fixed ratio and returns a fully opaque
    /// result - unlike `.opacity()`, this looks identical regardless of
    /// what's rendered behind it (a light-mode white background vs a
    /// dark-mode near-black one), since there's no transparency for the
    /// backdrop to show through. Used for ring tracks and gradients across
    /// the app's Apple Watch-style progress rings.
    func lightened(by amount: Double) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(
            red: r + (1 - r) * amount,
            green: g + (1 - g) * amount,
            blue: b + (1 - b) * amount
        )
    }

    /// Blends toward black by a fixed ratio - the darker end of the
    /// angular gradient used for ring fills.
    func darkened(by amount: Double) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(
            red: r * (1 - amount),
            green: g * (1 - amount),
            blue: b * (1 - amount)
        )
    }
}
