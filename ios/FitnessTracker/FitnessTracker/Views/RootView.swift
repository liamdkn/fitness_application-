import Auth
import SwiftUI

struct RootView: View {
    @ObservedObject private var supabase = SupabaseService.shared

    /// Not just `session != nil` - with `emitLocalSessionAsInitialSession`
    /// on (see `SupabaseService.init`), the locally stored session is
    /// always emitted as the initial one, valid or not, so an expired one
    /// needs its own check here rather than being treated as signed-in.
    /// `autoRefreshToken` (on by default) will replace it with a fresh
    /// session shortly after launch if the refresh succeeds, at which
    /// point this flips back on its own via the same `$session` publisher.
    private var isSignedIn: Bool {
        guard let session = supabase.session else { return false }
        return !session.isExpired
    }

    var body: some View {
        Group {
            if isSignedIn {
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
