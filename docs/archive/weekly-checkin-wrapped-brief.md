# Weekly Check-In "Wrapped" Redesign + Check-In History — Brief

Two related pieces: (1) redesigning the weekly check-in into a Spotify-Wrapped-style data reveal, and (2) a proper history/gallery area to browse past ones, including progress photos. Informed by a research pass on PT-coaching weekly check-in practice (sources at the bottom) — cross-checked against what was already designed in conversation rather than starting over.

## 1. What stays exactly as it is

Body measurements + progress photo capture at the end of the flow (`MeasurementsPhotosCaptureView`) — nothing here needs new data collection, it's already the one part of this that has to be a deliberate moment, Wrapped-style reveal or not.

## 2. New data collection — kept minimal, each one earns its place

- **Self-rating of the week** — one number (e.g. 1-10), nothing else. Not a return of the old mood/stress/discipline survey that got killed for being write-only; this one has an explicit destination (paired against the computed weekly adherence score, Section 3).
- **Off-plan reflection** — no new daily input. Pull whichever days that week had `daily_checkins.yesterday_off_plan = true` (already captured) and surface them back with room for a short added reflection now that the week's over and there's perspective on it. This is a second look at existing data, not a new count or stepper.
- **Self-picked focus for next week** — after the algorithm surfaces its own suggested focus (Section 3), let the pick be overridden/confirmed by Liam rather than just displayed. Research backs this specifically: a self-authored goal sticks better than one just handed over.

Everything else in the reveal (weight, calories, macros, steps, training, habit-consistency) is pulled from data already logged during the week — nothing new asked for.

## 3. The reveal — card sequence

Shown as a swipeable, celebratory sequence immediately after the check-in is saved (not a Form list) — this is the actual "Wrapped" part, the input above is just the fuel for it.

1. **Weight vs. phase pace** — actual weekly weight change vs. `UserGoal.weeklyWeightChangeKg`, framed as ahead/on-track/behind for the active phase (cut/maintain/bulk), not a flat "lost/gained" read.
2. **Off-plan reflection** — the flagged days from Section 2, with the added reflection.
3. **Habit consistency** — days logged this week (a plain completion count — "logged 6/7 days" — distinct from performance, per the research: showing-up is its own win, separate from hitting the number).
4. **Nutrition adherence** — avg calories/protein vs. target for the week.
5. **Steps** — avg vs. target, best day.
6. **Training** — sessions completed vs. target, any PRs hit.
7. **Rating vs. adherence score** — the self-rating from Section 2 next to the computed weekly adherence score. The gap itself is the insight (felt worse/better than the data says) — this is also the data trail for eventually revisiting the adherence-score formula, a separate piece of work already flagged, not solved here.
8. **Focus for next week** — algorithm's pick (weakest-scoring component that week) shown alongside the option to confirm it or pick your own, per Section 2.

## 4. Check-in History — needs to become editable, and needs a proper photo view

Two concrete gaps in what's there today:

- **Reuse the reveal, don't build a second detail format.** Rather than keeping `WeeklyCheckinDetailView`'s current plain Form-of-LabeledContent layout, a tapped history row should open the same card-reveal sequence from Section 3, populated with that past week's numbers instead of the current week's. One UI, two entry points (live, right after saving; historical, from the list) — avoids maintaining two different ways of presenting the same data, the same pattern already used for Weekly Log → Weekly Insights.
- **The photo timeline (below) is the upload entry point — not an edit path on each individual check-in.** Liam has a backlog of photos from the last few weeks to add; requiring a drill-in to each specific past check-in to attach one is the wrong shape for a batch backfill. Instead: a "+" on the photo timeline opens the picker, with a date field (defaults to today, editable to any past date) — no need to navigate to find "the right" check-in first. `ProgressPhoto.weeklyCheckinId` is already nullable, so a photo doesn't strictly require one; on save, best-effort-associate it with whichever weekly check-in falls in that same week if one exists (so it still shows up on that week's reveal), but the photo's own `taken_at` date is what the timeline actually sorts and displays by, not the check-in link. Backend work here is minimal — `ProgressPhotoRepository.upload` already takes `takenAt` and an optional `weeklyCheckinId`, this is a new entry-point UI plus the nearest-check-in lookup, not new storage/schema.
- **The dedicated photo timeline/comparison view itself**, separate from the per-check-in detail — this is the "nice UI format" piece. `ProgressPhotoRepository.fetchRecent` already pulls photos across all check-ins, not just one. A grid or horizontal timeline of every progress photo in chronological order, with a simple two-photo side-by-side compare (pick any two dates, not just consecutive weeks).

## Research notes (PT coaching / weekly check-ins)

Cross-checked the design above against how personal trainers actually run client check-ins. High-level: the plan above already covers the standard ground (sleep, water, nutrition consistency, energy, workout compliance, wins/challenges, forward planning) — the research didn't surface a missing data point so much as validate three specific design choices already folded in above: self-authored next-week focus over an algorithm-only pick, a plain habit/completion count as its own metric separate from performance, and pain/injury tracked separately from general soreness (already handled elsewhere in the app, via Injuries — not a gap). Deliberately not adopting: accountability partners, buddy systems, social leaderboards, badges — these are multi-client/human-coach social mechanics that don't transfer to a solo app.

Sources: [My PT Hub](https://www.mypthub.net/blog/essential-client-check-in-questions/), [HubFit](https://hubfit.com/blog/10-questions-for-weekly-checkins/), [NASM](https://www.nasm.org/resource-center/blog/building-client-habits-that-outlast-training-programs-with-behavior-coaching), [Gymkee](https://gymkee.com/blog/personal-training-client-check-in-template/), [FitBudd](https://www.fitbudd.com/post/workout-accountability-for-clients-10-effective-tactics).
