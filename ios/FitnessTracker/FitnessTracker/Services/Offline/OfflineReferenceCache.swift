import Foundation

/// Lightweight fallback cache for read-only reference data the active-
/// workout screen needs just to render (today's routine-day exercises, the
/// exercise library) - separate from `OfflineWorkoutQueue`, which handles
/// the write side. This is a "last known good" snapshot: whenever one of
/// these reads succeeds online, it's stashed here, so opening a workout at
/// the gym with no signal still shows what you're supposed to do, as long
/// as you've opened it at least once before with a connection - which is
/// the realistic case (you saw today's exercises on the Train tab, or in a
/// past session, well before you lost signal walking into the gym).
enum OfflineReferenceCache {
    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineReferenceCache", isDirectory: true)
    }

    private static func url(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    /// Best-effort only - if writing the cache fails, the next offline load
    /// simply won't have a fallback, no worse off than without this cache
    /// at all.
    static func save(_ value: some Encodable, key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: url(for: key), options: .atomic)
        } catch {
            // Ignored - see doc comment.
        }
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
