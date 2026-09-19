# SUPERSEDED - do not implement

This brief (and the one-off SQL script it described,
`supabase/one_off/2026-09-18_delete_aug3_16_orphan_data.sql`) proposed
permanently deleting Liam's logged data for Aug 3-16, 2026 because it
doesn't fall inside any goal phase.

Liam reconsidered (Sep 18): he wants to keep the data, he just doesn't
want those weeks showing up as rows in the Weekly Insights week
picker. That's a UI filter, not a deletion. See
`docs/weekly-insights-picker-hide-parentless-weeks-brief.md` for the
actual fix. The SQL script has been removed from the repo - nothing
was ever deleted (it failed on its first `SELECT COUNT` due to a
`:user_id` syntax error before reaching any `DELETE` statement).
