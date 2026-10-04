import SwiftUI

@main
struct FitnessTrackerWatchApp: App {
    @State private var connection = PhoneConnection.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connection)
        }
    }
}
