# Weekly Log — Brief

New feature. Recreates the "trainer's spreadsheet" Liam used to fill in by hand — a scannable, week-by-week table of averages to judge progress across time. This brief also folds in a related IA decision: a three-layer restructure of Dashboard / Weekly Log / Weekly Insights, agreed on alongside this feature rather than after it, so Claude Code builds toward the end state instead of building Weekly Log against the current Weekly Insights and re-splitting it later.

## 0. The three-layer structure (supersedes today's two-layer Dashboard → Weekly Insights setup)

Weekly Insights today mixes two different jobs in one screen: live, current-week, actionable-right-now numbers (steps debt, nutrition debt) alongside whole-week retrospective analysis (adherence score, trend chart, maintenance insight, check-in recap). Splitting those onto the right layer:

- **Dashboard — "right now."** Gains **steps debt** and **nutrition debt**, placed next to their existing related cards (steps debt near wherever today's steps already show, nutrition debt near the existing macro cards) rather than behind a tap-through. Both are inherently current-week-only concepts already (steps debt/nutrition debt only make sense as "what do I need today to hit this week's target" — meaningless for a completed past week), so this isn't just a UI move, it's the correct home for them. Everything else already on the Dashboard is untouched.
- **Weekly Log — "history at a glance" (this brief, Sections 1-5 below).** The new spreadsheet-style table, one row per week.
- **Weekly Insights — "the deep dive on one specific week."** Keeps the weekly adherence score + breakdown, the 8-week adherence trend chart, the maintenance/TDEE insight (already gated to the current week only — no change needed there), and the weekly check-in recap. Loses steps debt and nutrition debt (moved to Dashboard, per above). **Also drop its own avg-calories/protein/carbs/fat/steps summary row** — once Weekly Log exists, that's a straight duplicate of what Weekly Log already shows at a glance for every week; keeping it in both places is exactly the kind of repetition worth cutting rather than carrying forward. Weekly Insights becomes reachable two ways: its existing entry point for the current week, and a row tap from Weekly Log for any past week (Section 3 below) — no separate "current vs. past" UI needed, it already supports navigating to an arbitrary week.

This is a bigger change than just adding a screen, so worth sequencing deliberately: build Weekly Log's data layer first (Section 4), since Dashboard's steps-debt/nutrition-debt move and Weekly Insights' cleanup are just moving/removing existing code, lower-risk than the new aggregate query.

## 1. What Weekly Log is, and why it's not part of Weekly Insights

Weekly Insights (post-split) answers "how did *this specific* week go, in depth." Weekly Log answers a different question — "how did each week compare to the last" — backward-looking, scannable, one row per week, the way a spreadsheet is. Mixing the two would clutter both, so this is a new, separate screen rather than a new mode inside Weekly Insights.

## 2. Entry point

A new link card on the Dashboard, placed alongside the existing `WeeklyInsightsLinkCard` (same visual pattern — a card that opens a deeper screen, not a new tab). Label: "Weekly Log" (or similar — open to a better name).

## 3. Screen: `WeeklyLogView`

A plain list/table, most recent week at the top, one row per week:

| Column | Notes |
|---|---|
| Week | Date range label (e.g. "Sep 8 - Sep 14") |
| Avg Weight | kg, 1 decimal — average of that week's logged weigh-ins |
| Avg Calories | kcal, average of logged days that week |
| Avg Protein / Carbs / Fat | g, same averaging |
| Avg Steps | average of fully-elapsed days that week (matches the existing `avgStepsPerDay` semantics - excludes a still-in-progress day) |

Optional, worth considering but not essential for v1: a small weight-change indicator next to the Avg Weight column (e.g. "71.8 kg (+0.3)") showing the delta from the previous row — cheap to add once the query returns consecutive weeks, and it's the detail that made the original spreadsheet useful for "is this trending the right way," not just a snapshot.

**Row tap → deep-link into the existing `WeeklyInsightsView` for that specific week.** `WeeklyInsightsViewModel` already supports navigating to an arbitrary week (it has a stale-load guard for "flicking through weeks," per its existing code comments), so this should be a small addition — pass the tapped row's week-start date in rather than building new navigation. This is the bridge between the two screens: Weekly Log is the at-a-glance index, Weekly Insights is still where the "why" for any given week lives.

**Pagination:** load a bounded recent window first (e.g. last 12-26 weeks) with a "load more" / infinite-scroll trigger for older history, rather than fetching Liam's entire tracking history in one query.

## 4. Data source — build this as a server-side aggregate, not a client-side loop

The per-week averages aren't new math — `WeeklyInsightsViewModel` already computes essentially this (avg steps, avg calories, avg macros, weight change) for one week at a time. **Don't reuse that by calling it once per row** — that's N round-trips to Supabase to render one screen, fine for a handful of rows, sluggish once there's months of history. Instead, add a Postgres view or RPC function that returns one row per week directly:

- Group by `date_trunc('week', date)` — Postgres's week truncation defaults to a Monday start, which already matches the Monday-anchored week the app's Weekly Insights code uses elsewhere (`Self.mondayOfWeek`) — use the same boundary here for consistency, not the user's separately-configurable check-in weekday (`weekly_checkin_weekday`), which is a different concept (when a *check-in* is due) and would make the two screens disagree about where a week starts if conflated.
- Average `body_weight_logs.weight_kg`, `step_logs.step_count` (only fully-elapsed days, matching existing semantics), and calories/protein/carbs/fat.
- **Nutrition source note:** by the time this is built, pull whichever nutrition source is authoritative per the cutover logic already described in `nutrition-rebuild-and-apple-health-plan.md` Section 4 — the meal-entries-derived sum where present, falling back to `nutrition_logs` for weeks before the switch to in-house logging. Don't hardcode one or the other.

## 5. Out of scope for this pass

- No new logging schema — this is purely a read/aggregate over data that's already captured (weight, steps, nutrition).
- No smart analysis, correlation, or scoring on this screen — it's a plain table by design, that's the whole point (see the "why not Weekly Insights" framing above). Anything resembling automatic correlation belongs to the separate macro-balancing idea already parked in the other doc, not this one.
- No editing from this screen — it's a read-only index into history; corrections happen wherever that data was originally logged (Daily Check-In, Nutrition).
