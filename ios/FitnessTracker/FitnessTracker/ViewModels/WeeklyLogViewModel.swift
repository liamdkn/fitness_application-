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
    private let goalsRepository = GoalsRepository()
    private let pageSize = 12

    /// Every goal phase the user has ever had, sorted ascending by
    /// `effectiveFrom` - fetched once and reused for every row's phase
    /// label, the same "resolve point-in-time, don't re-query per row"
    /// pattern `WeeklyInsightsViewModel.goalEffective` uses.
    private var allGoals: [UserGoal] = []

    func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
        reachedEnd = false
        do {
            async let goalsResult = try? goalsRepository.fetchPastGoals(limit: 100)
            entries = try await repository.fetchSummary(limit: pageSize, before: nil)
            allGoals = (await goalsResult ?? []).sorted { $0.effectiveFrom < $1.effectiveFrom }
            reachedEnd = entries.count < pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loads every week up front rather than paging as a list scrolls -
    /// for `WeeklyLogTableView`, which wants its full-history weight chart
    /// available immediately rather than built up page by page the way
    /// the compact week picker's `loadMoreIfNeeded` does. A handful of
    /// months of weekly rows is trivial to fetch in full for one user.
    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let goalsResult = try? goalsRepository.fetchPastGoals(limit: 100)
            var all: [WeeklyLogEntry] = []
            var before: String?
            while true {
                let page = try await repository.fetchSummary(limit: pageSize, before: before)
                all.append(contentsOf: page)
                guard page.count == pageSize, let last = page.last else { break }
                before = last.weekStart
            }
            entries = all
            allGoals = (await goalsResult ?? []).sorted { $0.effectiveFrom < $1.effectiveFrom }
            reachedEnd = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// "Cut week 3" - the phase active as of this week (point-in-time, not
    /// whatever phase is active today) and how many weeks into it this
    /// week falls. `nil` if no goal phase covers this week (e.g. logged
    /// before any goal was ever set up), in which case the row falls back
    /// to showing just its date range as the primary label.
    func phaseLabel(for entry: WeeklyLogEntry) -> String? {
        let isoWeekStart = entry.weekStart
        guard let goal = allGoals.last(where: { $0.effectiveFrom <= isoWeekStart }),
              let phaseStart = DateFormatting.date(fromISODate: goal.phaseStartedAt)
        else { return nil }
        let days = Calendar.current.dateComponents([.day], from: phaseStart, to: entry.weekStartDate).day ?? 0
        let weekNumber = max(1, days / 7 + 1)
        return "\(goal.phaseType.displayName) week \(weekNumber)"
    }

    /// The whole goal phase active as of this week - same point-in-time
    /// resolution `phaseLabel` uses (the latest goal whose `effectiveFrom`
    /// doesn't come after this week started), but returning the full goal
    /// rather than just its label - for anything showing goal-vs-actual per
    /// week (see `WeeklyLogTableView`). `nil` before any goal was ever set.
    func goal(for entry: WeeklyLogEntry) -> UserGoal? {
        allGoals.last(where: { $0.effectiveFrom <= entry.weekStart })
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
