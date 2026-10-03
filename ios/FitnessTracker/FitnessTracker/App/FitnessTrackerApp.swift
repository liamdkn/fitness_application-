import SwiftUI

/// Reads `OrientationLock.shared.mask` for the whole app - the one hook
/// UIKit gives a SwiftUI app to allow rotation on a single screen (Weekly
/// Log's table) while every other screen stays portrait-only.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Also runs when iOS launches the app in the background for new
        // Health data - that's what keeps the step reminders current.
        Task { @MainActor in StepReminderService.shared.startObserving() }
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
