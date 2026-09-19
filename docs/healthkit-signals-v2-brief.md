# HealthKit Signals v2 — Resting Heart Rate/HRV, Wrist Temperature, Workout Sessions, Body Composition

Four new HealthKit-derived signals to fold into the TDEE/weight-trend work already speced in `docs/adaptive-tdee-v2-brief.md` and `docs/off-plan-bump-exclusion-consistency-brief.md`. Confirmed Liam wears the Watch daily, so there's real history to pull from HealthKit's own retained data, not just going forward. Ranked by how much confidence they actually add, per the earlier conversation - not proposing everything as equally load-bearing.

## 0. Architectural note before building any of this

Right now there's exactly one "exclude this reading, here's why" mechanism in the app - `OffPlanWeightAdvisor`, purpose-built for one cause (a flagged off-plan day). Sections 1-2 below add two more causes for the same underlying idea: a weigh-in shouldn't be trusted at face value on a day something else was going on. Building each as its own bespoke advisor would mean three parallel systems doing the same job with different triggers. **Worth generalizing now instead**, before there's three of them to untangle later: a shared concept - call it a weight-reading anomaly, with a `cause` (`offPlan`, `elevatedRestingHeartRate`, `possibleIllness`, more later) and the date range it covers - that both `AdaptiveTDEEEngine`'s trend calculation and the Dashboard/Weekly Wrapped labeling (per the exclusion-consistency brief) can query generically instead of each cause needing its own bolt-on. `OffPlanWeightAdvisor`'s existing logic becomes the first of several cause-detectors feeding one shared exclusion list, not a special case.

## 1. Resting Heart Rate + HRV — an independent "something's off" signal

Neither is read today - checked `HealthKitManager`, only steps/sleep/dietary types exist. Add `HKQuantityType(.restingHeartRate)` and `HKQuantityType(.heartRateVariabilitySDNN)` to the read set, fetched with the existing `fetchDailySum`-style helper (daily average rather than sum, so a small variant of that helper, not the exact same one).

**Storage:** a new `wellness_metrics` table (date, resting_heart_rate, hrv_sdnn, source, same owner-scoped RLS shape as every other per-day table), synced by `HealthSyncService` alongside steps/sleep.

**Use:** compute a personal rolling baseline for each (e.g. trailing 30-day average) and flag a day as anomalous when RHR is meaningfully elevated above baseline or HRV meaningfully depressed below it - both are well-established proxies for illness, poor recovery, or high stress, all of which cause real water-weight fluctuation that has nothing to do with what was eaten. Feeds into the Section 0 shared anomaly mechanism as `cause: elevatedRestingHeartRate` / `possibleStress`, exact thresholds worth tuning against Liam's own actual baseline once there's a few weeks of real data rather than guessing a fixed bpm/ms cutoff up front.

## 2. Wrist Temperature — a more specific illness signal

`HKQuantityType(.appleSleepingWristTemperature)` - only available on Series 8+/Ultra, and only while asleep, so this one depends on Liam's specific Watch model (worth confirming before building). Apple's own illness-detection feature uses deviation from a personal rolling baseline internally, not a raw absolute value, so this needs the same baseline-and-deviation treatment as Section 1 - store the raw nightly reading, compute the deviation client- or server-side.

**Use:** a meaningful upward deviation is a materially more specific "you're getting sick" signal than RHR/HRV alone (those two are broader stress/recovery proxies; this one is closer to an actual fever signal). Same Section 0 mechanism, `cause: possibleIllness`. Getting sick is one of the most common, least-logged causes of a confusing multi-day weight swing - this catches it without Liam ever having to remember to log "I felt unwell."

## 3. HealthKit Workout Sessions — catching what happens outside this app

Read `HKWorkoutType` sessions (start/end, workout type, any device-estimated energy) for a trailing window. Not for calorie math directly - for **existence-checking** against what's already logged in-app.

**Use, two places:**

- **Today Checklist's "workout" tick** (from the recent Dashboard work) - right now it can only reflect a workout logged through Train. If Liam ever logs a run or ride through the Watch's own Workout app instead, that session exists in Health but the checklist has no way to know about it, so the tick would read "not done" on a day he actually trained. Cross-referencing HealthKit workout sessions fixes this without changing how the tick itself is defined - it's a second source for "was something done today," same as steps already merges Watch + iPhone sources.
- **A gentle catch-up prompt**, not an auto-import - if a HealthKit workout exists for a day with nothing logged in Train/cardio, surface something like "We noticed a workout in Apple Health that isn't in your log - add it?" rather than silently creating a workout row from HealthKit data the app can't fully reconstruct (exercises, sets, weights aren't in a HealthKit workout sample - only duration/type/energy are). Keeps the app's own workout log as the detailed source of truth; HealthKit just flags the gap.

## 4. Body Composition — the strongest signal, but conditional

`HKQuantityType(.bodyFatPercentage)` - **only worth building if Liam actually has a scale that writes this to Health** (a smart scale - Withings, Renpho, etc.). Worth confirming before Claude Code spends time on it; if there's no data source writing to this type, there's nothing to read and this section should be skipped entirely rather than built and sitting unused.

**If confirmed:** add a nullable `body_fat_percent` column to `body_weight_logs` (source already distinguishes `manual`/`healthkit`, so a HealthKit-synced weight row can carry this alongside the weight itself when available). This is the one signal here that doesn't just explain away a bad reading - it changes what a real weight change *means*: separating "1kg down" into how much was fat versus water/glycogen is a fundamentally better answer than raw scale weight for judging whether a phase is actually working, and could sharpen the Weekly Wrapped "weight vs phase pace" card's framing directly (e.g. "1.2kg total change, ~0.9kg of that fat" instead of just the raw number) once there's enough data to say anything meaningful about it.

## Sequencing

1 and 2 both feed the shared anomaly mechanism from Section 0 - build that shared structure once, then both causes plug into it rather than each getting its own parallel logic. 3 is independent and can happen anytime. 4 is gated on confirming Liam has a compatible scale - ask before building, not after.
