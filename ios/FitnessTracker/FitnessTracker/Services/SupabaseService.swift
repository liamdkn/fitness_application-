import Combine
import Foundation
import Supabase

@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    let client: SupabaseClient
    /// Set when the build is missing its Supabase URL or key (a bad or absent
    /// `Config.xcconfig`); `RootView` shows it instead of the app.
    let configurationError: String?
    @Published private(set) var session: Session?

    private init() {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let configuredAnonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        let configuredURL = urlString.flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil }
        if configuredURL == nil || (configuredAnonKey ?? "").isEmpty {
            configurationError = "This build is missing its Supabase settings. Add SUPABASE_URL and SUPABASE_ANON_KEY to Config.xcconfig (see Config.xcconfig.example) and rebuild."
        } else {
            configurationError = nil
        }
        // A harmless placeholder keeps the client constructible; nothing is
        // ever sent to it because the app shows the error instead.
        let url = configuredURL ?? URL(string: "https://invalid.example")!
        let anonKey = configuredAnonKey ?? ""

        // `emitLocalSessionAsInitialSession: true` opts into the library's
        // upcoming default now, rather than leaving it on the deprecated
        // current behavior (see the console's own build-time notice) - the
        // locally stored session is always emitted as the initial one, so
        // callers checking auth state on launch need to check
        // `session.isExpired` themselves rather than assuming "session
        // present" already means "session valid."
        var options = SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
        #if DEBUG
        if NetworkMonitor.simulateOffline {
            // Every request fails the way a real no-signal request does.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OfflineSimulatingURLProtocol.self]
            options = SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true),
                global: .init(session: URLSession(configuration: configuration))
            )
        }
        #endif
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey, options: options)

        Task { await observeAuthChanges() }
    }

    private func observeAuthChanges() async {
        for await (_, session) in client.auth.authStateChanges {
            // Before the app sees a signed-in user: make sure the data on the
            // phone is theirs (see `LocalData`).
            if let userId = session?.user.id { LocalData.claim(userId) }
            self.session = session
        }
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
        LocalData.wipe()
    }
}

#if DEBUG
/// Fails every request with "not connected to the internet" - used only by
/// the `-simulateOffline` launch argument.
final class OfflineSimulatingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
#endif
