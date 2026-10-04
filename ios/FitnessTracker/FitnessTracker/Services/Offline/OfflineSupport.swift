import Foundation

/// Shared pieces of the app's offline support: telling a "no connection"
/// failure from a real one, reading reference data with a last-known-good
/// fallback, and caching the catalogue foods you've seen.

enum OfflineError {
    /// True for failures caused by having no usable connection - the cases
    /// where falling back to local data (or queueing a write) is right. A
    /// server rejection or a bug is not one of these and should still show.
    static func isConnectivity(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        // With the network known to be down, any failure counts: an expired
        // login that can't refresh, for one, doesn't surface as a URLError.
        if !NetworkMonitor.shared.isConnected { return true }
        var current: Error? = error
        while let candidate = current {
            if let urlError = candidate as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                     .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
                     .secureConnectionFailed, .callIsActive:
                    return true
                default:
                    break
                }
            }
            current = (candidate as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        }
        return false
    }
}

import SwiftData

/// Opens an on-disk SwiftData store. If it can't be opened (a corrupt or
/// incompatible file), that file is moved aside - kept, not deleted, so it
/// can be recovered by hand - and a fresh store is created; if even that
/// fails the queue runs in memory for this launch. The app never crashes
/// over its offline store: the worst case is that unsynced offline changes
/// from before the failure aren't shown.
@MainActor
func makeResilientContainer(name: String, models: [any PersistentModel.Type]) -> ModelContainer {
    let schema = Schema(models)
    let url = URL.applicationSupportDirectory.appending(path: "\(name).store")
    func open(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(name, schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: configuration)
    }
    if let container = try? open() { return container }
    NSLog("Offline store \(name) could not be opened - moving it aside and starting a fresh one")
    let stamp = ISO8601DateFormatter().string(from: Date())
    for suffix in ["", "-shm", "-wal"] {
        let file = URL(fileURLWithPath: url.path + suffix)
        try? FileManager.default.moveItem(at: file, to: URL(fileURLWithPath: file.path + ".corrupt-\(stamp)"))
    }
    if let container = try? open() { return container }
    NSLog("Offline store \(name) still failing - running in memory this launch")
    if let container = try? open(inMemory: true) { return container }
    // An in-memory store failing means SwiftData itself is broken.
    preconditionFailure("SwiftData is unavailable")
}

/// Runs `fetch`; on success stashes the result under `key`, and if it fails
/// for lack of a connection returns the last stashed copy instead (any other
/// failure still throws). For reference lists - meal slots, saved meals, the
/// routine - where slightly stale beats nothing.
func cachedRead<T: Codable>(key: String, _ fetch: () async throws -> T) async throws -> T {
    do {
        let value = try await fetch()
        OfflineReferenceCache.save(value, key: key)
        return value
    } catch {
        guard OfflineError.isConnectivity(error), let cached = OfflineReferenceCache.load(T.self, key: key) else {
            throw error
        }
        return cached
    }
}

/// An on-disk, id-keyed store of everything of one kind the app has fetched -
/// so foods and recipes you've seen are still there with no signal. Merges as
/// it goes; nothing is ever removed.
@MainActor
final class IdCache<Item: Codable & Identifiable & Hashable> where Item.ID == UUID {
    private let key: String
    private var memory: [UUID: Item]?

    init(key: String) { self.key = key }

    private var store: [UUID: Item] {
        if let memory { return memory }
        let items = OfflineReferenceCache.load([Item].self, key: key) ?? []
        let loaded = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        memory = loaded
        return loaded
    }

    var all: [Item] { Array(store.values) }

    /// Forgets the in-memory copy so the next read goes back to disk (empty,
    /// after `OfflineReferenceCache.removeAll()`).
    func reset() { memory = nil }

    func items(ids: [UUID]) -> [Item] {
        let current = store
        return ids.compactMap { current[$0] }
    }

    func store(_ items: [Item]) {
        guard !items.isEmpty else { return }
        var current = store
        var changed = false
        for item in items where current[item.id] != item {
            current[item.id] = item
            changed = true
        }
        guard changed else { return }
        memory = current
        OfflineReferenceCache.save(Array(current.values), key: key)
    }
}

@MainActor
enum Caches {
    static let foods = IdCache<Food>(key: "food-cache")
    static let recipes = IdCache<Recipe>(key: "recipe-cache")

    static func resetAll() {
        foods.reset()
        recipes.reset()
    }

    /// The same word-by-word, starts-with ranking the online search uses,
    /// run over the foods already on the phone.
    static func searchFoods(query: String, limit: Int) -> [Food] {
        let words = query
            .filter { !",()%*".contains($0) }
            .split(separator: " ")
            .map { String($0).lowercased() }
            .filter { $0.count >= 2 }
        guard !words.isEmpty else { return [] }

        func matchCount(_ food: Food) -> Int {
            let foodWords = "\(food.name) \(food.brand ?? "")"
                .lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            return words.filter { word in foodWords.contains { $0.hasPrefix(word) } }.count
        }

        let everything = foods.all
        let copiedOriginals = Set(everything.compactMap(\.sourceFoodId))
        return everything
            .filter { !$0.isQuickAdd && matchCount($0) > 0 && !copiedOriginals.contains($0.id) }
            .sorted {
                let (a, b) = (matchCount($0), matchCount($1))
                if a != b { return a > b }
                if $0.name.count != $1.name.count { return $0.name.count < $1.name.count }
                return $0.name < $1.name
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Everything cached A-Z, without originals the user has their own copy of.
    static func allFoodsSorted() -> [Food] {
        let everything = foods.all
        let copiedOriginals = Set(everything.compactMap(\.sourceFoodId))
        return everything.filter { !$0.isQuickAdd && !copiedOriginals.contains($0.id) }.sorted { $0.name < $1.name }
    }
}
