# Apple Watch Active Energy as a Cross-Check on the Maintenance Estimate

New data point requested: bring in total calories from Apple Watch activity tracking, alongside the existing weight-trend-based maintenance estimate. This isn't just another number to show - used right, it's a second, independent way to sanity-check the number that was just found to look wrong (`docs/tdee-nutrition-source-bug-brief.md`), including for the more likely real cause once the meal-logging-source theory was ruled out: incomplete self-reported calorie logging.

## 1. Why this actually helps, not just "more data"

`AdaptiveTDEEEngine` currently derives maintenance calories one way: back-calculate expenditure from logged intake plus the observed weight-trend change (`estimatedTDEE = avgCalories - impliedBalance`). That's a solid method, but it has exactly one failure mode - if the *logged intake* itself is wrong (under-reported meals, alcohol not logged, a skipped day), the whole estimate quietly inherits that error with nothing to catch it. That's the leading suspect for the 1,844 reading now that the meal-logging-source bug's been ruled out for Liam's setup.

Apple Watch's activity data gives a second, independent estimate of expenditure that doesn't depend on logged intake at all - active energy burned (plus resting energy) measures the *output* side directly, instead of inferring it from the *input* side. Comparing the two lets the app say "these two independent methods agree" or "these two don't agree, something's off" - which is precisely the plausibility guard the other brief flagged as missing, and a much stronger one than an arbitrary sanity threshold would be.

## 2. What's not built yet

Checked `HealthKitManager` - it currently reads steps, sleep, and dietary (consumed) calories/macros only. There's no `activeEnergyBurned` or `basalEnergyBurned` read anywhere in the codebase. This is genuinely new, not a wiring gap like the last one.

## 3. What to add

**HealthKit read:** add `HKQuantityType(.activeEnergyBurned)` to `HealthKitManager`'s read set (same pattern as the existing dietary types) and a fetch using the same generic `fetchDailySum(for:unit:daysBack:)` helper already used for calories/protein/carbs/fat - no new fetching pattern needed, just a new type passed into an existing one. Basal/resting energy (`HKQuantityType(.basalEnergyBurned)`) is worth pulling too if it's available and populated (Apple Health estimates this even without a Watch, though it's more reliable with one) - active + basal together is the full expenditure picture; active alone under-counts by whatever your body burns just existing.

**Storage:** a new `active_energy_logs` table (date, active_energy_kcal, basal_energy_kcal nullable, source, same RLS-owner-scoped shape every other per-day HealthKit-synced table already uses), synced the same way `HealthSyncService` already syncs steps/sleep - `repository.upsertActiveEnergy(...)` alongside the existing `upsertSteps`/`upsertSleep` calls in its sync pass.

**The cross-check itself, in `AdaptiveTDEEEngine`:** for the same window used for the trend-based estimate, compute `avgWatchExpenditure = average(activeEnergy + basalEnergy)` across days with data. Compare it to `estimatedTDEE` (the existing weight-trend-based figure):

- **Close agreement** (proposing within ~15% of each other, in the same spirit as the 40%-deviation honesty threshold already used elsewhere in this app's off-plan-menu-option scoring) - nothing changes visually, maybe a small "matches your Watch activity data" confirmation line, quietly reassuring rather than another number to parse.
- **Meaningful disagreement** - surface it plainly rather than silently picking one: "Your Watch shows ~2,600 kcal/day of activity, but this estimate is based on ~1,844 kcal/day of logged intake - one of these is probably off. Check for unlogged meals (especially recent off-plan days) before trusting this number." This directly answers the "it can't be that low" reaction by pointing at the actual likely cause instead of just presenting a bare number again.

**Not proposing** replacing or blending the two into a single formula in this pass - that's a bigger methodological step (whose estimate wins when they disagree, by how much, is a real design question) and the disagreement-flagging version above already delivers the actual value: catching exactly the kind of bad-logging-day situation Liam just ran into, without the risk of a blended formula being wrong in a new, harder-to-explain way. Worth revisiting once there's a few weeks of both signals to see how often and how far they actually diverge in practice.

## 4. Data quality caveat, worth being upfront about

Apple Watch active-energy estimates aren't perfect either - they're algorithmic guesses from heart rate/motion, with known error margins, especially for resistance training (which reads differently than steady-state cardio to the Watch's algorithm). This is a cross-check, not a replacement ground truth - the goal is catching a wildly-off logging week, not treating the Watch number as more correct than the trend-based one by default.

## Update (Sept 18, later) - confirmed direction is a blend, not just a flag

Liam confirmed he wants the Watch activity signal actually blended into the number, not just used to flag a disagreement. The concern raised in Section 3 above still holds and shapes how - a naive 50/50 average would dilute a good weight-trend-based estimate with a noisier Watch estimate on every normal week, which is a net loss most of the time. The answer isn't "don't blend," it's **confidence-weighted blending** - full detail and the combined design (this plus the phase-length window change) is in `docs/adaptive-tdee-v2-brief.md`. This file stays as the record of why a flat blend was the wrong first instinct and what it needs to become instead.
