# V1 Wrap-Up + V2 Roadmap

Companion to `nutrition-rebuild-and-apple-health-plan.md`, which is now mostly *built* — this doc covers what's left to close out V1 cleanly, and lays out V2. Prepared for handoff to Claude Code.

## 1. Where V1 actually stands

Good news first, because it's real progress: since the last audit, the entire in-house food-logging system from the plan doc got built and committed (`c6873de`) — `foods`, `meal_slots`, `meal_entries`, `recipes`, `saved_meals`, `saved_days` all exist with migrations `0031`-`0036`, plus `FoodRepository`, `MealEntryRepository`, `OpenFoodFactsService` (barcode/search), `OfflineMealQueue` (the offline pattern reused as planned), and — beyond the original scope — `OffPlanWeightAdvisor.swift`, meaning the off-plan/weight-correlation idea from Section 8 of the other doc got built too. The `nutrition_source` switch is wired correctly: it defaults to `healthkit_manual` (safe — nobody's flipped over to the new system until they choose to), `HealthSyncService` correctly stops syncing HealthKit nutrition once it's set to `in_house`, and the git history shows this was built as a clean, deliberate sequence of commits, not a scramble.

The working tree is clean (nothing uncommitted except a `.claude/` folder and a stray `.env.save`, neither of which are code). So "finish V1" isn't about rescuing half-built work — it's about the cleanup pass you're asking for, plus a couple of real gaps.

## 2. What this pass found — concrete, not guesswork

**2.1 — `NutritionEntryView.swift` is now doing two jobs in one file, and it shows.** It's grown to 897 lines / 31 structs+functions in a single file — by a wide margin the biggest view in the app. The reason: it's the *same file* serving both the old whole-day manual-entry UI and the new meal-based logging UI, switched throughout the view body with `if nutritionSource == .inHouse { ... } else { ... }` at something like eight separate points (macro rings, trend section, recent-entries section, and more). That's not a bug — it's functionally correct and matches the design — but structurally it's the textbook shape of "two features glued together with conditionals in one file," and it will only get harder to touch the longer both paths live inside it. **Recommendation: split it into two focused views** — `LegacyNutritionEntryView` (the old whole-day form, kept only for the pre-cutover history reads Section 4 of the other doc described) and `MealLogNutritionView` (the new one) — with a thin router view picking between them based on the switch. Same behavior, but each file is legible on its own and the legacy one becomes trivially deletable later instead of tangled into the current one.

**2.2 — The legacy `healthkit_manual` path's lifespan needs an actual decision, not just a default.** Right now it's the default for everyone (correct, safe), but there's no stated plan for when — or whether — it goes away. Worth deciding now rather than letting it become permanent-by-inertia: is the intent "flip to `in_house` yourself once you trust it, and the old path quietly retires a few months later," or does it stay indefinitely as a fallback? This directly determines whether 2.1's `LegacyNutritionEntryView` split is worth doing carefully (if it's going away) or worth doing thoroughly (if it's a permanent fixture).

**2.3 — `FitnessTrackerTests` exists as an empty target.** A test target was created at some point but holds zero test files. Either it's scaffolding for tests that haven't been written yet, or a leftover from an Xcode template step — worth a one-line decision (write real tests for it, or remove the empty target so it's not misleading).

**2.4 — I can't do real dead-code detection from here, and it matters that you know that rather than get a false sense of completeness.** I checked for the usual textual tells (TODO/FIXME/`deprecated` comments — none found, which is a good sign of discipline) and traced usage of specific types by hand (confirmed `NutritionLog`/`NutritionRepository` are still genuinely referenced, not orphaned — they're the legacy path from 2.2, still wired in on purpose). But *true* unused-code detection — an unreferenced function, an unused property, a view nobody navigates to anymore — needs a Swift compiler pass or a tool like **Periphery**, which needs Xcode/the Swift toolchain. That's not available to me from this session (I can reach your files, but not a macOS build environment) — it needs to run through Claude Code on your Mac, which does have it. **Concrete first step of the cleanup phase: have Claude Code run a full clean build capturing every compiler warning, and ideally a Periphery scan, and work through what comes back.** That's the actually-reliable way to find dead code, versus my manual grep-based pass, which can miss things or (less likely, but possible) flag something as dead that has a call site I didn't check.

**2.5 — "Features that seem unnecessary, redundant, repetitive" is partly a call only you can make.** I can point at structural redundancy (2.1) and I didn't find duplicate *systems* solving the same problem twice elsewhere in the app — routines/workouts, check-ins, adherence scoring, cardio tracking, and the goals/phases system each look like they're pulling their own weight, not overlapping each other. But "this feature isn't worth what it costs to maintain" is a product judgment about your own usage, not something I can read off the code. Worth you doing a quick pass yourself: which screens do you actually open, and which ones (weekly check-in survey fields, a particular chart, a setting you set once and never touch) have you stopped using since they were built? That list feeds directly into the cleanup backlog below.

## 3. V1 cleanup backlog (for Claude Code)

1. Run a full clean build + capture compiler warnings; run Periphery (or equivalent) for unused-code detection; triage the results.
2. Split `NutritionEntryView.swift` into a legacy view and a meal-log view behind a router (2.1) — do this regardless of 2.2's answer, since it's a maintainability fix either way.
3. Decide and document the `healthkit_manual` path's lifespan (2.2) — even just a line in the repo's docs settles it.
4. Resolve `FitnessTrackerTests` (2.3) — write tests or remove the empty target.
5. Liam's own "what do I actually use" pass (2.5) feeding into a short list of features to trim, simplify, or leave alone.
6. Anything Periphery/warnings turn up in step 1.

This is the "finish V1" phase — it's cleanup and closure, not new features. Good candidate to timebox (e.g. a week) rather than let it expand, since steps 1-4 are concrete and bounded.

## 4. V2 — consolidating everything already on the table

Pulling together every future-facing idea that's come up so it lives in one place rather than scattered across conversations:

- **Apple Health/Watch integration** (full detail in the other doc, Section 5): import HealthKit workouts into the app's DB (cheap, no new target), write the app's own workouts *to* HealthKit (currently never happens), and the WorkoutKit spike for cueing a structured workout onto the Watch before considering a full custom watchOS companion app.
- **Macro-balancing "jigsaw" engine** (other doc, Section 7): starting with the cheap live remaining-budget view, only building the actual constraint solver if that alone doesn't kill the manual-rebalancing itch.
- **Exercise animations / muscle-highlight diagrams**: the cheap version (a body diagram highlighting `primaryMuscleGroup`, which already exists on `Exercise`) versus real movement-demonstration clips (a sourcing/licensing project via something like ExerciseDB or Open Food Facts-style open data, not a coding task) — still an open question on which one you actually want, per the earlier conversation.
- **Legacy nutrition path retirement** (2.2 above) — once you've been on `in_house` for a while and trust it.
- Anything that comes out of the "what do I actually use" pass in 2.5 that isn't a trim but a genuine "replace this with something better" call.

**Recommended sequencing: finish Section 3's cleanup backlog before starting V2 in earnest.** Not a hard rule, but a practical one — building Apple Watch integration or a solver engine on top of a codebase where the biggest view is a two-systems-glued-together file just compounds the debt instead of clearing it. The cleanup phase is short and bounded; V2 isn't.
