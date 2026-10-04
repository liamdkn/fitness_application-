import Auth
import SwiftUI

struct RootView: View {
    @ObservedObject private var supabase = SupabaseService.shared
    @ObservedObject private var network = NetworkMonitor.shared

    /// Not just `session != nil` - with `emitLocalSessionAsInitialSession`
    /// on (see `SupabaseService.init`), the locally stored session is
    /// always emitted as the initial one, valid or not, so an expired one
    /// needs its own check here rather than being treated as signed-in.
    /// `autoRefreshToken` (on by default) will replace it with a fresh
    /// session shortly after launch if the refresh succeeds, at which
    /// point this flips back on its own via the same `$session` publisher.
    ///
    /// Offline is the exception: the access token only lasts about an hour,
    /// and with no connection it can't be refreshed, so an "expired" stored
    /// session offline must still count as signed in - otherwise opening the
    /// app in the gym or the kitchen with no signal would drop you at the
    /// sign-in screen with all your offline data out of reach. Everything
    /// that needs the server queues or falls back until it's reachable
    /// again, when the token refreshes on its own.
    private var isSignedIn: Bool {
        guard let session = supabase.session else { return false }
        return !session.isExpired || !network.isConnected
    }

    var body: some View {
        Group {
            if let problem = supabase.configurationError {
                ContentUnavailableView {
                    Label("Setup needed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(problem)
                }
            } else if isSignedIn {
                MainTabView()
            } else {
                SignInView()
            }
        }
        .tint(AppColor.accent)
    }
}

#Preview {
    RootView()
}
