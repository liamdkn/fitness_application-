# Adherence Score & Dashboard/Weekly Insights Audit

Scope: read-only review of `ios/FitnessTracker` — `AdherenceScoreEngine.swift`, `AdherenceScore.swift`, `WeeklyInsightsViewModel.swift`, `DashboardView.swift`, `WeeklyInsightsView.swift`, `DayAdherenceDetailView.swift`, plus the supporting models (`UserGoal`, `DailyCheckin`, `WeeklyCheckin`, `Routine`) and the two adjacent engines (`AdaptiveTDEEEngine`, `DeloadAdvisor`). Nothing has been changed in the repo — this is analysis only, so you can decide what's worth building.

## How the score works today

A day's score is the average of up to four components, each 0–100, and a component that doesn't apply or isn't logged is left out of the average rather than counted as zero:

Calories is scored two-sided — full marks within 5% of target, decaying linearly to zero at 30% off in either direction — because under-eating on a cut is its own adherence problem, not free progress. Protein and steps are one-sided — hitting or exceeding target is always full marks, only a shortfall costs points. Training is a hit (100) if a workout was logged, excluded (nil) on a declared rest day or a day with no check-in at all, and zero only when there's an explicit check-in saying it wasn't a rest day and nothing was logged.

The weekly score doesn't just average the seven daily scores. Calories/protein/steps do average the days, but training is recomputed from scratch as sessions-completed vs. the phase's required-sessions-per-week (total minus optional) — the code comment explains this well: averaging the daily hit/miss/rest scores would let a string of un-checked-in days quietly count as "not applicable" instead of a missed session, understating a real shortfall. That asymmetry (average for three components, recompute for the fourth) is a deliberate, good design decision.

## What's already right about it

The exclude-don't-zero philosophy for missing or inapplicable data is the correct default — a rest day or an unsynced steps reading genuinely shouldn't drag your score down. The two-sided/one-sided split between calories and protein/steps matches how those actually behave physiologically on a cut. And the weekly training recompute closes a real gaming hole that a naive average would have left open.

## Where it breaks down

**1. Missing data is invisible, and that's the biggest issue.** Because a component with no data is excluded rather than zeroed, a day where you only logged steps — nothing else — averages to just the steps score. If steps hit target, that day shows a clean 100 and a full green ring, visually and numerically identical to a day where you actually hit calories, protein, steps, and training. Nothing in `DailyAdherenceScore.overall`, the ring, or the breakdown row distinguishes "genuinely perfect day" from "we only saw one data point and it happened to be good." Given you explicitly want to avoid noisy/misleading data, this is exactly that failure mode, just hidden by the math rather than caused by bad logging.

**2. Equal weighting across all four components is an unexamined default, not a decision.** Calories, protein, steps, and training are each worth exactly 25% in both the daily and weekly overall, in every phase. On a cut, calorie and protein adherence are the primary levers for the actual outcome (the scale, body comp); a missed step day is comparatively low-stakes if the week's total steps are fine. Right now the formula can't reflect that — a day that nails calories and protein but misses steps scores the same overall as a day that hits steps and training but blows calories by 20%.

**3. No confidence adjustment for partial weeks.** A weekly protein score averaged from 2 logged days is displayed identically to one averaged from 7 — same number, same formatting, no indication one is far less reliable than the other. This compounds issue #1 at the weekly level.

**4. The score has no memory — it's a snapshot, not a trajectory.** Weekly Insights shows exactly one week at a time (this week, or one you've paged back to); there is no rolling view of the last N weeks' scores anywhere. Your project brief's whole premise is "ensure we are following in the correct trajectory," and the one number best positioned to answer that — the weekly adherence score — currently can't be viewed as a trend at all.

**5. Self-reported and recovery data are collected but go nowhere.** `DailyCheckin` already captures `energyLevel` and `sorenessLevel`, and they already feed `DeloadAdvisor` on the Train tab. Separately, the entire `WeeklyCheckin` survey — overall 7-day rating, discipline level, stress level, biggest win, mood notes, self-rated training/nutrition adherence — is written by `WeeklyCheckinFlow` and stored via `WeeklyCheckinRepository`, but I checked every view file and none of it is ever read back and displayed anywhere. It's write-only data right now. That's a shame specifically because a self-rated "how did this week feel" number sitting next to the objective adherence score is a genuinely useful pairing — it's how you'd notice "score says 90 but I logged feeling burnt out and stressed all week," which the objective score alone can't catch.

## A proposed v2

None of this requires ripping up the existing engine — it's additive:

Add a completeness signal alongside the score rather than changing what's scored. Give `DailyAdherenceScore` and `WeeklyAdherenceScore` a `componentsScored` / `componentsTotal` pair (or a computed property), and treat `overall` as nil when fewer than 2 of 4 components have data — the same "not enough to judge" logic already used per-component, just applied one level up. Then surface it in the UI: a small "3/4 tracked" caption under the ring in `DayAdherenceDetailView` and the `WeeklyAdherenceCard`, so a viewer can calibrate trust in the number at a glance instead of a lightly-logged day looking exactly like a fully-logged one.

Move from a plain average to a weighted one, renormalized over whichever components are actually present (so the exclusion behavior is unchanged — you're just changing each component's share of the average, not whether missing ones still get excluded). I'd suggest defaults like calories 35%, protein 25%, training 25%, steps 15% for a cut/bulk phase — reflecting that steps is the most forgiving lever and calories/training the least — declared as named constants next to the existing band constants, with a comment explaining the reasoning the same way the rest of the file already does. These are your numbers to set, not mine — happy to wire up whatever weighting you actually want, including keeping it equal.

Add a rolling score history. Compute and store (or just recompute on demand from existing data) the last 8–12 weeks' `WeeklyAdherenceScore.overall` values and show them as a small Swift Charts line/sparkline at the top of Weekly Insights, above the current single-week card. This is the most direct fix for the "trajectory" gap, and it's a small addition given the weight chart already proves out the Charts plumbing in this codebase.

Surface the weekly check-in survey. Even a compact read-only summary — self-rated adherence, discipline, stress, and biggest win/mood notes for the selected week — displayed in Weekly Insights next to the objective score would close the write-only gap and let you compare "what the data says" against "what it felt like."

## Dashboard & Weekly Insights: what's shown vs. what's tracked

The Dashboard currently shows: check-in status, a link into Weekly Insights, the adaptive-TDEE nutrition-insight card, today's calories/macros/steps/sleep against target, and a weight chart (raw scale-weight points plus a straight-line projected goal line). Weekly Insights shows: the adherence card, training volume and cardio session count, average steps with a "steps debt" pace calculation and daily breakdown, average calories/macros, weight change vs. target rate, and (current week only) the maintenance-calories card.

A few gaps stood out where the data already exists in the app but isn't reaching either screen:

The weight chart is plotting raw, noisy scale weight with no smoothing, even though `AdaptiveTDEEEngine` already computes an EWMA trend weight internally (it's how the TDEE recommendation works) — that trend line is never exposed on the chart itself. Extracting it into a shared utility and plotting it alongside the raw points would directly address the day-to-day noise that's currently the only thing the chart shows, and it's a natural companion to the goal-projection line that's already there.

There's no projected goal date or phase progress anywhere. `UserGoal` has `targetWeightKg`, `weeklyWeightChangeKg`, and `durationWeeks`, but nothing computes "at this rate, target around [date]" or "week 6 of 12" for the current phase. Both are cheap given the fields already exist.

Sleep is tracked daily on the Dashboard (with a target) but never appears in Weekly Insights at all — no weekly average, no vs.-target row, despite every other tracked metric getting one. I'm not suggesting it join the adherence score (you already decided that), just that a weekly sleep summary is a natural fit alongside the other `InsightRow`s.

Cardio has a count target (`cardioSessionsPerWeek`) that's checked, but `cardioMinutesPerSession` is defined on the goal and never used anywhere in Weekly Insights — so three 5-minute "sessions" currently satisfy a "3x30min" target just as well as the real thing.

There's no week-over-week comparison for anything. Every number in Weekly Insights — adherence score, avg steps, avg calories, training volume — is shown in isolation for the selected week only, with no delta against last week and no trend beyond manually paging backward and remembering the old numbers. Given the project's own framing, this is probably the single biggest structural gap in the two screens combined.

Training volume is shown as a bare number ("X kg") with no target and no trend, so it doesn't currently tell you much about whether you're progressing.

## Suggested order of attack

If you want to tackle this, I'd go: fix the missing-data masking and add the completeness badge first (small, and it's a trust issue with the number you already have); then the multi-week adherence trend chart, since it's the most direct answer to the "trajectory" goal in your project brief; then the weight trend line and the weekly check-in survey display, since both are surfacing data the app already computes or collects; and treat the weighting change, cardio-duration check, and projected-goal-date as polish once the above are in.

## Open questions

Do you want to actually set non-equal component weights, and if so what split feels right for how you think about a cut vs. a bulk — or would you rather leave it equal and just fix the missing-data masking? And for the completeness threshold: should a day/week below 2-of-4 components hide the score entirely (shows "not enough logged" like a rest day does now) or just show it visually de-emphasized with the count attached?

Let me know if you want me to go ahead and implement any of this directly in the Swift codebase.
