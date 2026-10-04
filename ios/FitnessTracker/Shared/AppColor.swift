import SwiftUI
import UIKit

/// Every colour the app uses, by what it means rather than what it looks
/// like. Views and widgets refer to these names and never to `.blue` or
/// `.green` directly, so changing how protein (or the whole app) looks is a
/// one-line edit here. Shared with the widget extension so the Live Activity
/// and widgets match the app.
nonisolated enum AppColor {
    // MARK: Brand

    /// The app's accent: tab bar, links, primary buttons, selected days,
    /// "Today" badges. Applied app-wide from `RootView` (`.tint`) and UIKit's
    /// appearance, so anything that just says `.tint`/default button follows it.
    static let accent = Color(UIColor.systemBlue)

    /// The default button fill (see `AppButtonStyle`): a cool slate grey,
    /// kept separate from `accent` so buttons and highlights can differ.
    static let button = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.37, green: 0.40, blue: 0.46, alpha: 1)
            : UIColor(red: 0.45, green: 0.48, blue: 0.54, alpha: 1)
    })

    /// The screen background: a faint vertical gradient (deep blue-black to
    /// black in dark mode, cool white to light grey in light mode) rather than
    /// a flat fill, so the glass buttons and cards have something to refract.
    static let backgroundTop = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.11, blue: 0.20, alpha: 1)
            : UIColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1)
    })
    static let backgroundBottom = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
            : UIColor(red: 0.86, green: 0.89, blue: 0.95, alpha: 1)
    })

    /// The glow that swells and fades behind the background gradient (see
    /// `AppBackground`).
    static let backgroundGlow = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.38, blue: 0.95, alpha: 1)
            : UIColor(red: 0.45, green: 0.68, blue: 1.00, alpha: 1)
    })

    /// The light that runs round card edges when the app opens (see
    /// `AppIntro`): brighter than the background glow so it shows on glass.
    static let cardGlow = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.38, green: 0.68, blue: 1.00, alpha: 1)
            : UIColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 1)
    })

    // MARK: Feedback

    /// Done, on target, a good score.
    static let success = Color.green
    /// Close to a limit, off target, worth a second look.
    static let warning = Color.orange
    /// Over a limit, a very low score, destructive actions.
    static let danger = Color.red
    /// Inline error messages.
    static let error = Color.red

    // MARK: Nutrition

    static let protein = Color.blue
    static let carbs = Color.green
    static let fat = Color.yellow
    static let calories = accent
    static let sodium = Color.orange
    static let fibre = Color.mint
    static let caffeine = Color.brown
    static let water = Color.cyan
    /// Calories banked toward a planned treat.
    static let treat = Color.orange

    // MARK: Body and activity

    static let steps = Color.blue
    static let weight = Color.blue
    static let heartRate = Color.red
    static let bedtime = Color.indigo
    /// A meal prep batch in the freezer.
    static let frozen = Color.cyan

    // MARK: Run stats and route

    static let runDistance = Color.cyan
    static let runTime = Color.yellow
    static let runPace = Color.teal
    static let runCalories = Color.pink
    static let runElevation = Color.green
    static let runPower = Color.mint
    static let runCadence = Color.teal
    static let routeStart = Color.green
    static let routeEnd = Color.red
}
