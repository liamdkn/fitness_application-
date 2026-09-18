# Off-Plan Weight-Bump Exclusion — Consistency Fix + Labeling

Follow-up to a question about whether the calorie/weight-trend engine should treat a flagged off-plan day's water-weight bump as an outlier. Checked the code: it already does, in one place, and not in two others that were built more recently. This brief closes that gap and adds the labeling asked for — whenever a displayed number comes from the adjusted trend rather than a raw weigh-in, that needs to be visible, not implicit.

## 1. What's inconsistent today

`AdaptiveTDEEEngine.offPlanBumpDates(from:)` already excludes weigh-ins logged in the 3 days after a flagged off-plan check-in from the trend calculation it uses to estimate maintenance calories and recommend a target - this is correct and already reasoned through in its own doc comments (a temporary water-weight spike isn't real body-mass change and would throw off the estimate).

Two newer pieces don't do this - both compute a weight trend/average straight from raw `BodyWeightLog` rows with no exclusion:

- `DashboardViewModel.loadWeightGlance()` - the Weight card's up/down/stable trend badge (this week's 7-day average vs last week's).
- `WeeklyInsightsViewModel` - `avgWeightThisWeek`/`avgWeightLastWeek`, which feeds the Weekly Wrapped's "weight vs phase pace" card.

Net effect: the app can show a red "trending up" badge on the Dashboard at the same moment `OffPlanWeightAdvisor`'s own note underneath it says "typically water weight, settles in 2-3 days" - two parts of the same screen disagreeing with each other over the same data.

## 2. Fix - share one exclusion helper, use it everywhere a trend is computed

`AdaptiveTDEEEngine`'s bump-date logic is currently a private helper, duplicated nowhere else, which is presumably exactly why the other two pieces don't have it. Pull it out into `OffPlanWeightAdvisor` (the natural owner - it already holds the "off-plan day → date range" concept) as a public function, something like:

```swift
static func excludingBumpDates(
    from weights: [BodyWeightLog],
    checkins: [DailyCheckin],
    settleDays: Int = 3
) -> (filtered: [BodyWeightLog], excludedCount: Int)
```

Returning the excluded count alongside the filtered list, not just the list - the UI labeling in Section 3 needs to know *whether* anything was actually excluded for the window being shown, not just get a silently-shorter array.

Then:

- `AdaptiveTDEEEngine` calls this instead of its own private `offPlanBumpDates` (same behavior, no duplication).
- `DashboardViewModel.loadWeightGlance()` filters its 14-day `logs` through this before computing `thisWeekAvg`/`lastWeekAvg`, and stores the excluded count (e.g. a new `@Published var weightGlanceExcludedBumpDays: Int`).
- `WeeklyInsightsViewModel` does the same for the current week's and prior week's weight fetches feeding `avgWeightThisWeek`/`avgWeightLastWeek`, storing a similar count for that week's Weekly Wrapped card.

**Important: this only affects trend/average calculations, never the underlying data.** The actual off-plan day's weigh-in stays logged and still shows as a real point on any weight chart/history view - it's excluded only from the specific averages that feed a verdict (trending up/down, ahead/behind phase pace, the TDEE estimate). Nothing gets hidden or deleted from the user's own weight history.

## 3. Labeling - make it visible when a figure isn't raw

This is the actual ask: whenever one of these adjusted figures is shown, it needs to read as adjusted, not as the plain scale number.

- **Dashboard Weight card** - when `weightGlanceExcludedBumpDays > 0`, add a small caption near the trend badge, same visual treatment as the existing off-plan note (`.font(.caption).foregroundStyle(.secondary)`): something like "Trend excludes 1 recent off-plan day" (pluralize as needed). Absent entirely when nothing was excluded - this should only appear when it's actually relevant, not as permanent chrome.
- **Weekly Wrapped "weight vs phase pace" card** - same treatment: a short caption under the verdict when that week's average had any exclusions, e.g. "Excludes Tue's post-off-plan reading."
- **Adaptive TDEE recommendation banner** (`MyGoalsView`) - already better off than the other two: it already says "Based on the last X days..." and "From the adaptive calorie engine's weekly estimates," which is real attribution, not a bare number. Worth adding one more clause when `excludedCount > 0` for full consistency now that this is becoming an app-wide pattern - e.g. append "(excludes N off-plan-affected days)" to the existing "trend weight change" sentence.

General rule going forward, worth stating explicitly for consistency: any UI surface that shows a *computed* trend/average/verdict derived from weight data - as opposed to a single logged reading - should say so when that computation excluded something, rather than presenting it as if it read straight off the scale.
