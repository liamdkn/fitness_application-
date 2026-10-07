# Adaptive TDEE v2 — Phase-Length Recency-Weighted Window + Confidence-Weighted Watch Blend

Consolidated brief. Supersedes the window/blend parts of `watch-activity-energy-crosscheck-brief.md` (which stays as the record of the discussion that got here - the HealthKit read/storage plan in that doc's Sections 2-3 is still accurate and unchanged). Triggered by the My Goals maintenance estimate reading ~1,844 kcal/day off a bad week of logging (`tdee-nutrition-source-bug-brief.md`), which exposed two real gaps in `AdaptiveTDEEEngine`: no independent check on intake accuracy, and a fixed 21-day window too short to dilute one bad week.

## 1. What's changing and why, in one paragraph each

**The window** goes from a flat, hard-cutoff 21 days to the current phase-to-date (capped at a max, proposed 12 weeks so a long phase doesn't accumulate an unbounded dataset), with both the intake average and the weight-trend slope computed as **exponentially recency-weighted**, not a flat mean. A longer window dilutes any single bad week; recency weighting keeps the estimate honest about genuine drift instead of going stale - true maintenance calories really do fall over a sustained cut (less mass to maintain, metabolic adaptation), so a flat full-phase average would systematically overstate current maintenance later in a phase. Recency weighting gets both properties in one mechanism, and it also naturally handles a mid-phase calorie adjustment (`AdjustNutritionTargetsView` - same `phaseStartedAt`, later `effectiveFrom`) without a separate reset rule: data from before an adjustment just fades in influence on its own as more recent days accumulate.

**The blend** adds Apple Watch active-energy (`activeEnergyBurned` + `basalEnergyBurned` if populated - see the other doc for the HealthKit read/storage plan, unchanged) as a second, independent expenditure estimate, combined with the existing weight-trend-based one by **confidence, not a flat average**. The weight-trend method is the more validated one when its input (logged intake) is trustworthy - it's calibrated against actual body outcome, not an algorithm's guess. A flat blend would dilute that good number with a noisier one on every ordinary week. Weighting by confidence means the Watch signal only pulls harder when there's actual evidence the intake side is shaky - which is exactly the case that just went wrong.

## 2. The window, concretely

Replace `AdaptiveTDEEEngine.evaluate`'s `windowDays: Int = 21` parameter and its flat-mean calls with:

- `windowStart = max(goal.phaseStartedAt, asOf - maxWindowDays)` (`maxWindowDays` proposed at 84 / 12 weeks).
- `avgDailyCalories`: exponentially weighted, `halfLifeDays` proposed at 21 (so a day 21 days old counts half as much as today; day 42 counts a quarter; etc.) - weight `w(age) = 0.5^(age / halfLifeDays)`, applied to each logged day's calories, normalized by the sum of weights actually used (so early in a phase, before there's much history, this gracefully degenerates toward the same behavior as today's flat window - nothing breaks for a phase that just started).
- Weight-trend change: same weighting, but as a **weighted linear regression slope** of the EWMA trend-weight series against day index, not a two-point before/after difference the way the current 21-day version computes it (`(last.weightKg - first.weightKg) / windowDays`) - a two-point difference is exactly the kind of thing one bad week can distort; a weighted regression over the whole window is what actually benefits from having more days to look at. Convert the daily slope to kg/week the same way as today.
- `minWeighIns`/`minNutritionLogs` gates stay, but worth reconsidering their spirit now that the window can span months - the existing doc comment for this brief's earlier work already flagged that day-count alone doesn't mean the days were representative; not solving that fully here, but the recency-weighted mean is itself a partial answer (a scattered handful of recent logged days will still dominate appropriately relative to a denser but older cluster).

## 3. The blend, concretely

`AdaptiveTDEEEngine.evaluate` gains a second estimate alongside the trend-based one:

```
watchTDEE = recency-weighted average(activeEnergy + basalEnergy) over the same window
```

Then a **confidence weight** for the trend-based estimate, `c ∈ [0, 1]` (1 = fully trust it, 0 = fully defer to Watch), built from signals already available or cheap to compute:

- **Logging completeness in the window** - proportion of days with a logged entry (already computable from `loggedDaysInWindow` vs window length). Fewer logged days -> lower `c`.
- **Recent off-plan proximity** - if the most-recent few days fall inside an off-plan bump window (`OffPlanWeightAdvisor`'s exclusion dates, already being computed for the weight-trend filtering), that's independent evidence the last stretch of logging might be less reliable than usual -> lower `c` for those days' contribution, or a small flat penalty to `c` overall when any recent day is bump-affected.
- **Agreement between the two estimates themselves** - a large trend-vs-Watch gap is itself evidence something's off with one of them; since the trend-based method is the default-more-trusted one, a large gap should move `c` down rather than up (the disagreement is more likely explained by bad intake data than by the Watch being wrong, per Section 1's reasoning - but don't let `c` collapse to near-0 off a single day's gap, weight this signal gently against the other two).

Final estimate: `blendedTDEE = c * trendTDEE + (1 - c) * watchTDEE`. Proposing `c` starts high by default (e.g. floor around 0.7) so a normal, well-logged week barely moves from today's trend-only behavior - the Watch signal is there to pull the number back toward reality specifically when logging looks shaky, not to become an equal partner by default.

**Show the blend's reasoning, not just its output** - ties back to the labeling principle from `off-plan-bump-exclusion-consistency-brief.md`. When `c` is meaningfully below its ceiling, say so: "Blended with Watch activity data (your recent logging looks incomplete)" rather than presenting `blendedTDEE` as if it came from the trend method alone.

## 4. Sequencing

Build the window change first (Section 2) - it's the lower-risk, self-contained improvement and doesn't depend on new HealthKit data existing yet. The Watch blend (Section 3) depends on the HealthKit read/storage work from `watch-activity-energy-crosscheck-brief.md` Sections 2-3 being in place first, and `c`'s exact weighting is the part most worth revisiting once there are a few weeks of real data to see how the two signals actually behave relative to each other.
