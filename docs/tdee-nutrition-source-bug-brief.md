# Maintenance-Calorie Estimate Reading Way Too Low — Root Cause + Fix

Reported: the "Estimated Maintenance Calories" card on My Goals showed ~1,844 kcal/day, implausibly low. Traced it - this is a real, confirmed bug, not a case of the math just looking wrong.

## Root cause

`MyGoalsView.refreshNutritionInsight()` builds the recommendation like this:

```swift
let windowNutrition = try await nutritionRepository.fetchRange(from: windowStart, to: Date())
...
AdaptiveTDEEEngine.evaluate(weightLogs: recentWeights, nutritionLogs: windowNutrition, ...)
```

`NutritionRepository.fetchRange` (and `fetchLog`) only ever query the **legacy `nutrition_logs` table**. Checked - there's no `meal_entries` awareness anywhere in `NutritionRepository`. But the in-house meal-logging system built earlier (`foods`/`meal_entries`/`recipes`) is exactly what real daily intake lives in once someone's using it, and `nutrition_logs` stops being the full picture from that point on.

The app already has the *correct* logic for this - it's just not where it needs to be. Migration `0037_weekly_log_summary.sql`'s `nutrition_combined` CTE does exactly the right thing: sum `meal_entries` (joined to `foods`/`recipes` for macros) per day, and only fall back to `nutrition_logs` for a date that has no `meal_entries` rows at all (i.e. before your cutover to in-house logging). That logic exists in exactly one place - the Weekly Log SQL function - and nowhere on the Swift side. Every other caller, including the one feeding this maintenance estimate, is still reading `nutrition_logs` alone.

**What this does to the number:** for any day in the 21-day window that was actually logged via the new meal-based system, `AdaptiveTDEEEngine` sees zero or near-zero calories for that day (because it's looking in the wrong table), which drags `avgDailyCalories` down. Since `estimatedTDEE = avgCalories - dailyBalance`, an artificially low average intake produces an artificially low maintenance estimate - it isn't measuring what you actually ate, it's measuring whatever fraction of it happened to still be logged in the old table. The `minNutritionLogs = 8` guard doesn't catch this because it only checks *how many* days have a `nutrition_logs` row, not whether those days' totals are actually complete.

**Worth confirming directly:** have any of the last ~21 days been logged through the newer meal-based nutrition screens rather than the old whole-day entry? If yes, that's the smoking gun - the more days logged the new way inside that window, the further off this number would be.

## Fix

Don't duplicate the cutover-aware logic a second time in Swift - pull the exact same "meal_entries wins, nutrition_logs fills any date without one" rule into a single shared place both sides can use:

- Add a method to `NutritionRepository` (or a new small service, if that reads cleaner) that returns the combined daily totals for a date range - same per-day sum-of-`meal_entries`-joined-to-`foods`/`recipes`, same date-level fallback to `nutrition_logs`, mirroring `0037`'s SQL exactly rather than reinventing the rule a third way.
- Point every current caller of `nutritionRepository.fetchRange`/`fetchLog` that's computing something meant to reflect *actual* intake at this new method instead - at minimum `MyGoalsView.refreshNutritionInsight()` (this bug) and `WeeklyInsightsViewModel`'s own nutrition fetch (same gap, same risk, just hasn't produced a visibly wrong number yet - the earlier "weight vs phase pace"/adherence-score wiring runs through the same `nutritionLogs` fetch and has the identical blind spot).
- Once there's one correct source, it's worth asking whether the server-side `weekly_log_summary` RPC's `nutrition_combined` CTE and the new client-side helper should actually be the same code path (e.g. the client calls a matching RPC instead of re-deriving it) rather than two independent implementations of one rule that has to stay in sync by hand.

## Also worth doing regardless of the fix above

The engine currently presents whatever it computes with full confidence - "Estimated maintenance: ~1,844 kcal/day" reads exactly the same whether the input data was solid or badly incomplete. Worth adding a basic plausibility guard to `AdaptiveTDEEEngine.evaluate` (or wherever the result gets displayed): if a new recommendation swings implausibly far from the previous estimate/current target in one step (there's already a `maxStepKcal = 150` cap on how far the *recommended target* can move - but nothing bounds the underlying `estimatedTDEE`/`avgDailyCalories` themselves against anything), surface it as "this estimate looks off - check your logging for the window" rather than a clean, confident number. Not a substitute for the actual fix above, but a real gap on its own - bad input data should never look this authoritative.

## Correction (Sept 18, later) - the root cause above doesn't apply to Liam's setup

Liam's confirmed he's on `healthkit_manual` - importing from Apple Health, not using the in-house meal-logging system. That rules out the `meal_entries`-vs-`nutrition_logs` gap above as the cause of the 1,844 kcal reading specifically: `nutrition_logs` genuinely is his authoritative source, so there's no missing table to fall back to. **The fix in this doc (a shared cutover-aware nutrition helper) is still worth building** - it's a real, separate latent bug for whenever he does switch, or for anyone who does - but it isn't what produced this particular number, and shouldn't be presented to him as the explanation.

What's more likely for someone on `healthkit_manual`: the data in `nutrition_logs` itself is incomplete, not that the app is looking in the wrong table. Under-logging is extremely common and easy to miss - a restaurant meal estimated on the fly, alcohol not logged at all, a day skipped entirely - and every one of those silently drags `avgDailyCalories` down the same way the table-mismatch theory would have, just for a data-quality reason instead of a code reason. `AdaptiveTDEEEngine`'s `minNutritionLogs = 8` gate only checks that 8 days *have an entry* - it has no way to know whether those entries are actually complete. See the new brief below - this is exactly the gap the Apple Watch activity-energy cross-check is aimed at closing.
