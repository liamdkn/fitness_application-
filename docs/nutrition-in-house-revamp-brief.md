# In-house nutrition revamp — dedicated screen + meal plan menus

Combines two things into one build for Claude Code: (1) today's request
to give in-house meal logging its own dedicated screen with a new
layout, and (2) yesterday's `docs/meal-plan-options-brief.md` (curated
X/Y/Z menu per slot with a "best fit today" suggestion) - Liam wants
both handed over together since the new screen is where the menu
picker lives anyway.

**Two open items not resolved before writing this** - flagged here
rather than guessed at, resolve with Liam or make a reasonable call
and note the assumption in the PR:
- His message describing this was cut off mid-sentence at "...also
  include we were speaking yesterday about adding" - the meal-plan
  menu doc above is the best guess at what he meant, but confirm.
- He referenced uploading a reference screenshot for the progress-bar/
  card layout ("very like what I'm going to upload") - it never
  attached. The layout description below is written from his text
  description only.

## 1. Turning in-house nutrition on stops HealthKit import, keeps history

Confirmed in code: `UserPreferences.nutritionSource` (`NutritionSource`
enum, values `.inHouse` / `.healthkitManual`) already exists and is
already wired as a Settings toggle (`SettingsView.swift`) that
persists via `UserPreferencesRepository.setNutritionSource`. Today
`NutritionEntryView` branches on this value inline to swap which
macro rings/data source it shows - that inline branch is what's being
replaced by a real separate screen (Section 2).

No HealthKit data needs deleting or migrating when the switch flips -
`nutrition_logs` rows already written from HealthKit imports stay in
the DB exactly as they are; flipping to `.inHouse` just stops writing
new ones and stops reading them for anything current-forward. Nothing
in this brief touches historical HealthKit-sourced rows.

## 2. New dedicated screen, own route

Today `NutritionEntryView.swift` (935 lines) serves both nutrition
sources via inline `if nutritionSource == .inHouse` checks throughout
- exactly the kind of dual-purpose bloat already flagged in the
earlier `docs/v1-wrapup-and-v2-roadmap.md` audit for this same file.
Liam wants the split made real: when `.inHouse` is active, route to a
whole new view (e.g. `MealLogHomeView.swift`) instead of branching
inside `NutritionEntryView`. `NutritionEntryView` keeps serving the
`.healthkitManual` case only, and loses its `.inHouse` branches once
the new screen covers everything they did. Whatever currently
presents `NutritionEntryView` (Dashboard nutrition card / tab, most
likely) picks the destination view based on
`nutritionSource` the same way it does today, just routing to two
separate view types instead of one view with internal branches.

## 3. Layout

Top of the new screen: one progress bar for total calories for the
day (target vs. logged-so-far - same `logged / target` shape the
existing calorie ring already computes, just as a bar instead of a
ring, matching the style Liam described). Below that, three cards in
a horizontal row, one per macro (protein/carbs/fat), each with its
own progress bar the same way. All four numbers already exist today
via `MealLogViewModel.dayTotals` (`DayMacroTotals`) for the logged
side; target side needs whatever the existing goal/macro-target
source is (same one `MacroRingsView`/`CalorieRow` read from today -
reuse that, don't refetch separately).

Below the progress section: a "Log Meals" button navigating to a
list/detail screen with one row per configured meal slot
(`MealSlot`, already ordered by `sortOrder`). Each row is a card
showing:
- Meal title (`MealSlot.name`)
- Protein / carbs / fat / fibre for that slot, under the title
- Calories, right-aligned

All of this is already computed per-slot today via
`MealLogViewModel.slotGroups` (`MealSlotGroup.totalCalories`) - it
just needs protein/carbs/fat/fibre subtotals added alongside calories
(currently only calories is summed per slot in `MealSlotEntry`/
`MealSlotGroup`; `DayMacroTotals` already does this shape for the
whole day, so it's the same reduce logic scoped to one slot's
entries instead of all entries).

Tapping a meal card opens logging for that slot - reuse the existing
`MealLogSection` sheet flow (Add Food / Log Recipe / Log Saved Meal /
**Choose from Menu**, see Section 5 below / Save This Meal) rather
than rebuilding it, just presented from the new card-based entry
point instead of inline in a Form section.

## 4. Meal time - already tracked, just needs surfacing

`MealEntry.loggedAt` is already a stored timestamp on every logged
entry, captured automatically at insert time - no new column or
tracking logic needed for "meal time is tracked automatically."
Nothing in this pass needs to *display* it yet (Liam's own framing -
it's for a future version alongside glucose readings and training
times), so this section is just confirming the data is already
there and forward-compatible, not asking for new UI now.

## 5. Meal plan menus (X / Y / Z) - carried over from yesterday

Full design already written up in `docs/meal-plan-options-brief.md` -
not repeating it here, just noting how it slots into this screen:
the "Choose from Menu" action (Section 3 of that doc) lives in the
same per-slot card/menu described above, and the "rotate through a
carousel of menus" framing from today's message is exactly what that
doc's `MealPlanOptionPickerView` + "Best fit today" badge already
covers - the row/card layout being built here is what makes that
carousel-style browsing make sense visually, per Liam's own
reasoning. No changes needed to that doc's design, just flagging the
dependency: build the new screen's slot cards first (or together),
since the menu picker attaches to them.

## 6. Suggested sequencing

1. New `MealLogHomeView` (or similar) with the top progress bar + 3
   macro cards, reusing `MealLogViewModel.dayTotals` and whatever
   target source `NutritionEntryView` currently reads.
2. Per-slot summary cards (calories done today; protein/carbs/fat/
   fibre subtotals are the one bit of new aggregation logic needed -
   see Section 3).
3. Wire "Log Meals" -> slot list -> tap-in to existing
   `MealLogSection` sheet flow, swap the Settings route so
   `.inHouse` goes to this new screen instead of `NutritionEntryView`.
4. Meal plan menus (`docs/meal-plan-options-brief.md`) on top, once
   the card layout above exists to hang "Choose from Menu" off of.
