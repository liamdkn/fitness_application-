import Combine
import Foundation

@MainActor
final class WeeklyLogViewModel: ObservableObject {
    @Published var entries: [WeeklyLogEntry] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isLoadingMore = false

    /// Once a page comes back shorter than requested, there's nothing
    /// older left - stops `loadMore()` from firing another (empty) request
    /// every time the list's bottom row appears.
    private var reachedEnd = false

    private let repository = WeeklyLogRepository()
    private let pageSize = 12

    func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
        reachedEnd = false
        do {
            entries = try await repository.fetchSummary(limit: pageSize, before: nil)
            reachedEnd = entries.count < pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called when the last-loaded row scrolls into view - fetches the
    /// next older page and appends it, rather than fetching Liam's entire
    /// tracking history up front.
    func loadMoreIfNeeded(currentEntry: WeeklyLogEntry) async {
        guard !isLoadingMore, !reachedEnd, entries.last?.id == currentEntry.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let nextPage = try await repository.fetchSummary(limit: pageSize, before: currentEntry.weekStart)
            entries.append(contentsOf: nextPage)
            reachedEnd = nextPage.count < pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
