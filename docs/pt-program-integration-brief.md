# PT program integration — goal phase, training program, schedule, calorie banking

Source: Liam's PT coaching brief (`liam_pt_brief_1.md`), covering his
current cut, a 4-day upper/lower program, shoulder/hernia training
constraints, weekly schedule, and a weekly "banked calories for one
night out" strategy. This brief translates that into concrete app
changes - mostly data entry into systems that already exist, a couple
of small additions where they don't.

One framing choice up front: everything medical in the source
document (the pain-settling rule, the hernia stop-rule, the A&E red
flags) stays as **reference text for Liam to read and judge himself**,
never as app-enforced logic. The app has no way to know his actual
pain level or whether a bulge feels "hard" - those are his and his
surgeon's calls, not something this software should ever try to
adjudicate. Scope below reflects that: store it, display it, don't
automate decisions from it.

## 1. Goal phase: confirm the cut's end date is set correctly

`UserGoal` already has everything needed - `phaseStartedAt` +
`durationWeeks` defines the phase's end, there's no separate end-date
field to add. Check the **current active cut row** in `user_goals`
(not guessed from the brief's "mid-August" - read the real
`phaseStartedAt` already stored) and confirm/correct `durationWeeks`
so the phase ends exactly on **Sunday 8 November 2026**. Targets
(`dailyCalorieTarget: 2140`, `proteinGTarget: 160`,
`carbsGTarget: 260`, `fatGTarget: 50`) should already match what's
live - worth a quick diff against the brief's numbers in case of
drift (the brief says 260g carbs; a recent Weekly Log screenshot this
session showed a 262.5g target - small enough to be rounding, worth
confirming which is the real stored value rather than assuming).

The maintenance (~2500-2600 kcal) then lean-bulk (+200-250, hard
weight ceiling) phases after Nov 8 aren't something to pre-build or
auto-trigger - no phase-transition automation exists today and adding
it isn't warranted for a one-time date. Simplest: when Nov 8 arrives,
creating that next goal phase through the existing goal-entry flow
with those numbers is a two-minute manual step, not an engineering
task.

## 2. Training program: enter the 4-day routine as real data

`Routine`/`RoutineDay`/`RoutineDayExercise` already model exactly this
shape (a routine, an ordered rotation of days, each day's exercises
with target sets/rep range). Build Upper A / Lower A / Upper B /
Lower B as four `RoutineDay`s (in that rotation order) under either a
new `Routine` or replacing the current active one, with each
exercise/sets/rep-range from the brief's four tables.

Before entering, check the existing exercise library for each named
exercise and create any that don't exist yet (candidates likely
missing based on what's typically seeded: glute drive machine, cable
pull-through, chest-supported row, reverse pec deck, cable external
rotation) - routine data entry, not a design decision, so this is
Claude Code's call on exact exercise-library additions.

Because this routine fully replaces whatever's currently active, the
shoulder/hernia avoid-list (incline press, overhead press, dips,
barbell back squat, overhead triceps extension, incline curls, lat
pulldown, lateral raises, cable crunch, hanging knee raise, hip
thrust) is satisfied simply by the new routine never including them -
confirmed true against the four tables given. Worth a comment in the
commit/PR noting *why* those are absent, so a future edit doesn't
casually reintroduce one without realizing it's injury-related.

## 3. Reference text: where the safety guidance actually lives

No existing field holds durable "read this before training" text -
`Workout.notes` exists but it's per logged session, not per routine.
Smallest addition: a nullable `notes text` column on `routines`
(mirrors the existing `workouts.notes` pattern), surfaced on whatever
screen shows routine details. That's where the pain-settling rule
("0-3/10 during, settles within 24h = fine; otherwise drop/swap"),
the hernia stop-rule, the A&E red-flag list, and the physio/retest
reminder (early November, cable lateral raises) belong - plain text
Liam reads, never a rule the app evaluates or acts on.

## 4. Weekly schedule - informational, not a new scheduling feature

`RoutineDay.position` is already rotation-order, not calendar-day-
locked (confirmed in code - there's no day-of-week field on
`RoutineDay` today), which matches how the brief actually describes
it: a 4-day rotation fit around specific days, not a hard calendar
lock. Nothing new needed here - the Mon/Tue/Thu/Fri gym + Wed/Sat run
+ Sun off structure is just how Liam uses the existing rotation and
the running plan from earlier today, not an app feature by itself.

**One correction to `docs/half-marathon-plan-content.md` from
earlier**: it assumed Wednesday + Sunday as run days with Saturday as
rest. This brief gives the real, authoritative schedule - Wednesday
(easy) and **Saturday** (long run), with **Sunday** fully off, not
Saturday. Swap those two days in that doc before any of it gets
seeded into `planned_runs`.

Monday/Thursday incline walks (20-30 min) need no new mechanism -
`CardioType.inclineTreadmill` already exists for logging them when
done; this is just the plan saying when, which is informational.

## 5. New: calorie banking for the weekly night out

This is the one genuinely new feature in here. The ask: run a small
daily deficit Mon-Fri (~150-200 kcal/day under the 2140 target) to
free up ~750-1000 kcal for one night out, tracked against the 7-day
average rather than a flat daily cap.

Closer to already-built than it first looks:
`WeeklyInsightsViewModel`'s existing `NutritionDebtSummary`/
`MacroDebt` mechanism already computes exactly this shape for
protein/carbs/fat - "given what's banked so far this week, what's
left for the rest of the week to land on target." It just doesn't
cover calories today (only the three macros). Adding a `calories:
MacroDebt?` case to `NutritionDebtSummary`, computed through the
exact same `macroDebt(target:keyPath:)` closure already in that view
model (just called with `dailyCalorieTarget`/`\.calories`), gets a
real "calories banked this week" figure almost for free.

One honest limitation to flag rather than paper over: that mechanism
spreads whatever's banked **evenly across all remaining days**, not
concentrated onto one chosen night-out day - so it'll show "you've
banked some surplus, here's your adjusted daily number for the rest
of the week," which is genuinely useful, but it won't say "here's
exactly how much you have for Saturday specifically" without extra
input. If precise night-out targeting matters (not just directional
awareness), that needs a lightweight addition - e.g. letting a goal
phase optionally mark one weekday as the planned "banked day," and
having that day's effective target be the flat target plus everything
banked since the last banked day, rather than spread evenly. Worth
confirming with Liam whether the simpler always-even-spread version is
good enough before building the extra targeting logic - it's a real
scope decision, not obvious either way.
