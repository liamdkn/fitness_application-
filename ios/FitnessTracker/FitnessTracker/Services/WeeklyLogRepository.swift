import Foundation
import Supabase

struct WeeklyLogRepository {
    let client = SupabaseService.shared.client

    private struct SummaryParams: Encodable {
        let p_limit: Int
        let p_before: String?
    }

    /// One row per week, most recent first. `before` (a week-start date
    /// string) pages backward through older history - pass the last
    /// already-loaded entry's `weekStart` to fetch the next page, nil for
    /// the first page.
    func fetchSummary(limit: Int, before: String?) async throws -> [WeeklyLogEntry] {
        try await client
            .rpc("weekly_log_summary", params: SummaryParams(p_limit: limit, p_before: before))
            .execute()
            .value
    }
}
