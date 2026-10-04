import SwiftUI

/// Reads `OrientationLock.shared.mask` for the whole app - the one hook
/// UIKit gives a SwiftUI app to allow rotation on a single screen (Weekly
/// Log's table) while every other screen stays portrait-only.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Also runs when iOS launches the app in the background for new
        // Health data - that's what keeps the step reminders current.
        Task { @MainActor in
            StepReminderService.shared.startObserving()
            // A tap on the supplements Live Activity runs in this process.
            SupplementReminderService.shared.installIntentHandler()
            WatchBridge.shared.activate()
        }
        // UIKit-hosted pieces (alerts, share sheets, the camera scanner) don't
        // see SwiftUI's `.tint`, so give them the accent too.
        UIView.appearance().tintColor = UIColor(AppColor.accent)
        // Nav-bar buttons (Cancel, Done, New Food...) in the normal text colour
        // - white in dark mode - rather than the accent blue.
        UINavigationBar.appearance().tintColor = .label
        UIBarButtonItem.appearance().tintColor = .label
        for state in [UIControl.State.normal, .highlighted, .disabled] {
            UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: UIColor.label], for: state)
        }
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }
}

@main
struct FitnessTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                .task { await OfflineQueueSelfTest.runIfRequested() }
                #endif
        }
    }
}
