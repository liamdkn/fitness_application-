import SwiftUI

/// A small pill at the top of the screen while there's no connection, so empty
/// or out-of-date figures (the dashboard reads from the server) aren't
/// mistaken for real ones - and so it's clear that what you log is being kept
/// on the phone and will sync later.
struct OfflineBanner: View {
    @ObservedObject private var network = NetworkMonitor.shared

    var body: some View {
        Group {
            if !network.isConnected {
                Label("Offline - changes sync when you're back", systemImage: "wifi.slash")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: network.isConnected)
        .allowsHitTesting(false)
    }
}
