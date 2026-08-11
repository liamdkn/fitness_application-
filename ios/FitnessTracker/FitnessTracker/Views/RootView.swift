import SwiftUI

struct RootView: View {
    @ObservedObject private var supabase = SupabaseService.shared

    var body: some View {
        Group {
            if supabase.session != nil {
                MainTabView()
            } else {
                SignInView()
            }
        }
    }
}

#Preview {
    RootView()
}
