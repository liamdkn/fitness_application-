import SwiftUI

@main
struct FitnessTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                .task { await OfflineQueueSelfTest.runIfRequested() }
                #endif
        }
    }
}
