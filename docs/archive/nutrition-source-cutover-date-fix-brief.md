# Weekly Log vs Weekly Insights showing different calorie averages

## The bug, confirmed in code

Liam noticed Weekly Insights showed 2310 kcal avg for Sep 14-20 while
Weekly Log showed 1678.3 kcal for the same week - two screens, two
different numbers for the same week.

Root cause: they read from genuinely different sources.

- **Weekly Insights** (`WeeklyInsightsViewModel`, via
  `NutritionRepository.fetchRange`) reads only `nutrition_logs` -
  Liam's real, complete data since he's on `healthkit_manual`
  (Apple Health import). Confirmed the 2310 figure is exactly the
  mean of the 7 daily bars shown, so this screen is internally
  consistent and correct.
- **Weekly Log** (`weekly_log_summary` SQL function, migration
  `0037_weekly_log_summary.sql`) has a per-date cutover rule in its
  `nutrition_combined` CTE: any date with *at least one* `meal_entries`
  row uses that row's total instead of `nutrition_logs` for that
  date, full stop - no blending, no completeness check. This was
  written assuming "a meal_entries row on date X = the user had
  switched to in-house logging by date X," which held until this
  week, when Liam started test-logging individual items via the
  in-house food search/barcode scan while investigating the food-
  database gap (`food-search-verified-sources-brief.md`) -
  while his actual nutrition source is still Apple Health import.
  A single test item logged in-house on one day is enough to fully
  override that day's real, much higher `nutrition_logs` total in
  Weekly Log's average, dragging the whole week down.

## The structural problem

There's no real cutover date anywhere in the schema.
`user_preferences.nutrition_source` (`Models/UserPreferences.swift`)
is a current-value-only toggle - no history of *when* it was set,
confirmed via `UserPreferencesRepository`/the `user_preferences`
table. So `weekly_log_summary`'s per-date heuristic ("does a
meal_entries row exist") is standing in for something that should be
an explicit fact, and gets it wrong the moment meal_entries rows
exist for reasons other than "the user has fully switched."

This isn't just a one-week glitch - it's the same underlying gap
`tdee-nutrition-source-bug-brief.md` flagged earlier (client-
side `NutritionRepository` not mirroring migration 0037's cutover
logic) approached from the other direction: 0037's cutover logic
itself isn't reliable either, since it has no real signal for when
a cutover happened. Worth fixing now rather than after the in-house
revamp (`nutrition-in-house-revamp-brief.md`) ships, since
that's exactly when this starts mattering for real, permanently,
not just during testing.

## Fix

1. **Add a real cutover marker.** New column
   `user_preferences.nutrition_source_changed_at timestamptz`,
   defaulting to null (never switched). `UserPreferencesRepository
   .setNutritionSource` sets it to `now()` every time the source
   actually changes (not on every save - only when the new value
   differs from the current one, so re-saving the same source
   doesn't keep bumping the date).

2. **`weekly_log_summary` reads that instead of guessing.** Join
   `user_preferences` in the SQL function and change
   `nutrition_combined`'s logic from "any date with a meal_entries
   row wins" to "dates on/after `nutrition_source_changed_at` use
   meal_entries (when nutrition_source is currently `in_house`),
   everything before it uses `nutrition_logs` regardless of whether
   a stray meal_entries row exists for that date." If
   `nutrition_source_changed_at` is null (never switched, today's
   actual state for Liam), just always use `nutrition_logs` - exactly
   matching what Weekly Insights already does, closing the gap.

3. **`NutritionRepository`'s own gap** (flagged in the earlier brief -
   it never reads meal_entries at all, even post-cutover) should get
   the same fix at the same time: read `nutrition_source_changed_at`
   and branch per-date the same way, so all three surfaces (Weekly
   Insights, Weekly Log, My Goals TDEE) agree once the in-house
   switch actually flips.

## Immediate, no-code fix for Liam right now

Not a code change - just: whatever was test-logged in-house this
week (the barcode-scan/search testing) can be deleted from that
day's meal log in the app (or left alone once the real fix ships,
since it'll stop being read for that date anyway once
`nutrition_source_changed_at` stays null). No data is wrong, it's
just being read from the wrong place for this one week in Weekly
Log specifically.
