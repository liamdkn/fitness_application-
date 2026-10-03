import Combine
import Foundation
import Supabase

@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    let client: SupabaseClient
    @Published private(set) var session: Session?

    private init() {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        else {
            fatalError("Missing SUPABASE_URL / SUPABASE_ANON_KEY - check Config.xcconfig")
        }

        // `emitLocalSessionAsInitialSession: true` opts into the library's
        // upcoming default now, rather than leaving it on the deprecated
        // current behavior (see the console's own build-time notice) - the
        // locally stored session is always emitted as the initial one, so
        // callers checking auth state on launch need to check
        // `session.isExpired` themselves rather than assuming "session
        // present" already means "session valid."
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )

        Task { await observeAuthChanges() }
    }

    private func observeAuthChanges() async {
        for await (_, session) in client.auth.authStateChanges {
            self.session = session
        }
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
