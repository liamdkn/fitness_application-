import UIKit

/// Every screen in this app is portrait-only (see Info.plist's
/// `UISupportedInterfaceOrientations`) except Weekly Log's table, which is
/// far more readable rotated so every column fits at once. There's no
/// per-view-controller orientation override reachable from pure SwiftUI,
/// so this is the one shared switch `AppDelegate.application(_:
/// supportedInterfaceOrientationsFor:)` reads - a screen that wants
/// landscape sets `mask` on appear and restores `.portrait` on disappear
/// (see `WeeklyLogTableView`).
final class OrientationLock {
    static let shared = OrientationLock()
    private init() {}

    var mask: UIInterfaceOrientationMask = .portrait {
        didSet {
            guard mask != oldValue else { return }
            // Without this, changing the mask alone doesn't move the
            // device out of its current orientation - most noticeably on
            // the way back to `.portrait`, where the screen would
            // otherwise stay stuck in landscape until manually rotated.
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
