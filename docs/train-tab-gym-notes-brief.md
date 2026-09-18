# Train Tab — Gym Notes Fixes

A batch of items from notes taken mid-gym-session. All checked directly against the current code before writing this — each one below is a confirmed, diagnosed bug or a precise UI change, not a guess.

## 1. Reorder exercises mid-workout

Not built at all right now — `ActiveWorkoutView`'s exercise list (`displayGroups`, built from `viewModel.activeExercises`) has no drag or move affordance, just static `ForEach` sections. Needs: a drag handle (or up/down buttons, simpler to get right with the superset-grouping complexity already in `displayGroups`) reordering `activeExercises`, for exactly the reason you gave - machine availability, not something plannable in advance. Ties directly into Section 4 below: once removal/addition needs to persist (the resume bug fix), that's the natural place to also persist order, rather than reordering being purely in-memory and reverting on resume the same way removal currently does.

## 2. Warmup weight bug - confirmed, and it's a real cascade bug

Found it in `SetLogGridView.placeholder(forRowAt:)`:

```swift
private func placeholder(forRowAt setIndex: Int) -> (reps: Int, weightKg: Double)? {
    if let last = activeExercise.loggedSets.last {
        return (last.reps, last.weightKg)
    }
    if let previous = activeExercise.previousSets[safe: setIndex - 1] {
        return (previous.reps, previous.weightKg)
    }
    return nil
}
```

The doc comment above it even says the quiet part out loud: "every later unconfirmed row's placeholder cascades from the most recently confirmed set." So log a light warmup set, and every row after it shows that same light weight as its placeholder - and because `resolvedWeight` falls back to the placeholder when the field's left empty (`Double(kgText) ?? placeholder?.weightKg`), leaving a row blank and tapping confirm actually logs the warmup weight, not just displays it as a hint.

**Fix:** stop cascading *weight* from the current session's last logged set. Reps can keep cascading (usually genuinely useful - same rep target across a set group) but weight should always come from `previousSets[safe: setIndex - 1]` - last session's weight for that specific set number - never from whatever was just logged a moment ago this session. Concretely: split the tuple's two fields to different sources instead of both coming from the same `last`/`previous` branch.

## 3. Weight display rounding to 1 decimal - it's a display bug, not a data bug

Checked where 8.75kg actually goes: the text field takes raw input straight through (`Double(kgText)`), and neither `WorkoutRepository` nor `OfflineWorkoutQueue` round it on save - so what's stored is exactly what you typed. The rounding is purely in how it's displayed back to you, and it's a pattern repeated across several files, all doing 1-decimal formatting:

- `SetLogGridView.swift` - the confirmed-row weight (`fractionLength(0...1)`) and the placeholder prompt (`%.1f`)
- `ActiveWorkoutView.swift` - the suggestion headline and "Last time: ..." summary (`%.1f`)
- `ExerciseHistoryView.swift` - past-session weight display (`%.1f kg`)
- `WorkoutDetailView.swift` - logged set weight (`%.1f`)

**Fix:** widen all of these from `fractionLength(0...1)` / `%.1f` to `fractionLength(0...2)` (or `%.2f` with trailing-zero trimming) so an entered 8.75 shows as 8.75, not 8.8, while something like 10.0 still shows as just "10" rather than "10.00" - `fractionLength(0...2)`'s lower bound of 0 already does that trimming for the `Text(_, format:)` call sites; the `%.1f`/`String(format:)` call sites need to switch to the same `.number.precision(.fractionLength(0...2))` style to get the same trimming (a raw `%.2f` would force "10.00"). Left `ExerciseProgressionView`'s estimated-1RM display alone - that's a computed estimate, not something you typed, so 1-decimal rounding there isn't the same complaint.

## 4. Resume-a-workout bug - root cause found

This is a real, precisely diagnosable bug, same class as the earlier SwiftData store-collision one. What happened: you started today's Push (routine template), cleared every exercise out, built your own workout instead, left the view, and resuming brought all the original Push exercises back.

`ActiveWorkoutViewModel.loadTemplate()` runs on every fresh view of an active workout (a new `ActiveWorkoutViewModel` gets created each time `ActiveWorkoutView` is navigated to - including via the Resume banner) and unconditionally rebuilds `activeExercises` from two sources: the routine day's template exercises (queried fresh from `routineRepository.fetchDayExercises`), plus whatever exercise IDs have logged sets against them (`existingSetsByExercise`, used both to restore sets and to detect ad-hoc additions). `removeExercise(exerciseId:)` only deletes that exercise's *sets* (`offlineQueue.deleteSets`) - there's no record anywhere that says "this exercise was deliberately removed from this specific workout." So the moment you leave and come back, `loadTemplate()` has no way to know a template exercise was removed - it just sees the routine day and re-adds every one of its exercises from scratch. Any of your own ad-hoc exercises *with sets already logged* would survive resume (they're picked up via `existingSetsByExercise`), but the removed template ones always come back, and an ad-hoc exercise with zero sets logged yet would also silently vanish on resume - same root cause.

**Fix:** the workout needs its own persisted exercise list, not a live re-derivation from the routine day every time. Concretely: a `workout_exercises` row per exercise actually in a given workout (seeded from the routine day at start-workout time), updated on `removeExercise`/`addAdHocExercise`/reorder (ties into Section 1), and `loadTemplate()` reads *that* list instead of re-fetching the day template. This is the same category of fix as the offline-queue store collision - worth similar priority, since right now removing something mid-workout is silently temporary rather than actually sticking.

## 5. "Remove From Workout" - drop the second confirmation

Checked the flow: it's already two steps before this ask - open the exercise's `...` menu, tap "Remove From Workout," *then* a `confirmationDialog` pops up ("Remove Bench Press From This Workout?" / Remove / Cancel) before anything happens. The dialog's own message already says "This only removes it from this workout, not your split" - it's explicitly low-stakes and reversible (add it back via "Add Exercise"), so the extra dialog is pure friction. **Fix:** drop the `confirmationDialog` entirely: tapping "Remove From Workout" in the menu removes it immediately, same as any other single-tap destructive menu action in this app.

## 6. Exercise history - sort by weight, not chronological set order

`ExerciseHistoryView` groups by session (correctly, most recent session first) but within each session, sets render in `setIndex` order - set 1, 2, 3 as logged, regardless of weight. **Fix:** sort each session's `entry.sets` by `weightKg` descending before rendering, so the heaviest set of that session is always the top row - matches how you actually want to scan it (what did I lift, not what order did I lift it in).

## 7. "Last time" text - more legible, minimal change

`ActiveWorkoutView`'s "Last time: ..." line (shown when there's no progression suggestion yet) is `.font(.caption).foregroundStyle(.secondary)` - matches your ask that this is a light styling tweak, not a redesign. Proposed: keep the caption size, change `.foregroundStyle(.secondary)` to something with more contrast - e.g. `.foregroundStyle(.primary.opacity(0.75))` - closer to fully legible without promoting it to the same visual weight as the suggestion headline above it.

## 8. Unclear - flagging rather than guessing

Your notes had a standalone "No" between the history-sort item and the closing question - not enough context to tell what it was answering or referring to. Left out of this brief; let me know what it was about and it's a quick addition.

## 9. "How are my habits impacting my body?"

This reads like a new feature idea rather than a bug, and it's specific enough (habit consistency vs. body outcomes) that it's worth a real answer on scope before writing a brief for it - a few things it could mean: (a) an extension of the same off-plan/weight-correlation idea already built (`OffPlanWeightAdvisor`) to other logged habits - sleep, steps, training consistency - and their effect on weight trend; (b) something that pulls in the separate HabitTracker app's data, if that's meant to feed into this app rather than stay standalone; or (c) something narrower, just about training habits (workout consistency, volume) vs. body composition. Worth a quick clarification before this becomes its own brief.
