# Smart Meal Plan Options — Brief

New feature: a fixed, curated menu per meal slot (e.g. Breakfast: X / Y / Z), each option built from non-negotiable core ingredients plus a small set of optional toppings/add-ons picked at log time — and the app suggests which option best fits what's left of today's macro budget. This is a scoped-down, buildable version of the "macro jigsaw" idea already parked in `nutrition-rebuild-and-apple-health-plan.md` Section 7 — worth knowing that connection exists, but this doesn't require the full solver that idea originally proposed.

## 1. Reuse, don't rebuild — this maps almost exactly onto Saved Meals

Checked the existing food-logging schema and UI before designing this, and it already has nearly everything needed: `saved_meals`/`saved_meal_items` (a named, reusable set of foods/recipes with quantities), `SavedMealsRepository`, and `SavedMealPickerView`/`SaveMealSheet` in `MealLogSection`'s per-slot menu. A "meal plan option" is structurally the same thing as a saved meal — a named list of foods/recipes with quantities — plus two things saved meals don't have: a pin to a specific slot, and a locked-vs-optional flag per item. Rather than a parallel set of tables, extend the existing ones:

- `saved_meals` gains a nullable `meal_slot_id uuid references meal_slots(id) on delete cascade`. Null (today's behavior, unchanged) = a generic reusable saved meal, applicable to any slot via the existing picker. Set = this saved meal is a curated **menu option** pinned to that slot specifically, and shows up in the new picker below instead of the generic one.
- `saved_meal_items` gains `is_locked boolean not null default true`. `true` = a core ingredient, always included, not removable at apply time (the "non-negotiable" part). `false` = an optional topping/add-on — off by default when the option is applied, toggle-able on before confirming.

Everything else — `SavedMealsRepository.fetchAll/fetchItems/save/delete`, the `applySavedMeal` flow already in `MealLogViewModel` — keeps working unchanged for the existing generic saved-meals use case; these two columns just add the slot-pinned, locked-ingredient use case on top.

## 2. Building the menu (X / Y / Z per slot)

New management screen, reachable from a slot's `Menu` in `MealLogSection` (new item: "Manage Meal Plan"), or from Settings > Nutrition. Composing an option looks like `SaveMealSheet` but with one more step per item: after adding a food/recipe (same picker flow as today), a toggle marks it Locked (default) or Optional Topping. Name the option (X/Y/Z can just be whatever name you give it — "Protein Oats," "Eggs & Toast," etc., no need for the app to enforce literal letters). No portion-scaling of locked ingredients in this pass — fixed quantities only, same as saved meals today; if a locked ingredient's amount needs to flex, that's a straight edit to the saved option, not a per-log adjustment.

## 3. Logging flow — picking from the menu

`MealLogSection`'s per-slot `Menu` gains a new item, shown only when that slot has ≥1 pinned option: **"Choose from Menu"** (sits alongside the existing Add Food / Log Recipe / Log Saved Meal / Save This Meal). Opens a new `MealPlanOptionPickerView` (a sibling to `SavedMealPickerView`, filtered to `meal_slot_id` = this slot) showing each option as a card:

- Locked ingredients listed plainly (not editable here).
- Optional toppings listed as toggles, off by default, each with its own macro contribution shown so turning one on visibly moves the running total.
- The option whose **locked-ingredient macros** best fit today's remaining budget (Section 4) gets a "Best fit today" badge — badging is based on locked ingredients only, not a guess at which toppings you'll pick, since toppings are your call after landing on an option.
- Tap to expand/adjust toppings, then Confirm.

Confirming inserts one `meal_entries` row per locked ingredient plus one per toggled-on topping (same shape as `applySavedMeal` today, filtered to locked-or-toggled items instead of all items) — no new `meal_entries` columns needed, this reuses the existing insert path.

## 4. The suggestion — how "best fit" is scored

You asked for this to suggest based on remaining macros, so here's a concrete proposal (flagging it as a real design call, not an obvious given):

1. **Remaining today** = each of calories/protein/carbs/fat target minus what's already logged today across every slot (same "target minus logged-so-far" shape `CalorieRow`/`MacroBarsRow` already use on the Dashboard, just applied to all four macros instead of calories alone).
2. **Per-meal share** = divide that remaining amount by the number of slots not yet logged today, including the one you're about to log — so if there's 1800 kcal left and 3 unlogged slots (this one plus two more), each slot's "fair share" is 600 kcal, and similarly for protein/carbs/fat. This is the same "spread what's left across what's left" logic `NutritionDebtView`'s weekly per-day figures already use, just at the daily/per-slot level instead of weekly/per-day.
3. **Score each option** by summing the absolute percentage deviation of its locked-ingredient macros from that per-meal share, across all four macros, equal weight. Lowest score = best fit, gets the badge.
4. **Honesty check:** if every option's score is bad (proposing a threshold — none within roughly 40% of the target share on average) don't force a badge onto the least-bad one; show the options unranked with something like "none of these fit today's numbers especially well" instead of a falsely confident pick. Better to say nothing than to badge a bad option as "best."

This needs read access to the day's goal targets and today's already-logged totals from wherever `MealLogSection`/`NutritionEntryView` currently gets or can get them — worth a quick check of whether `MealLogViewModel` already has that (it doesn't appear to today, per a look at its current methods) or whether it needs threading in from the Dashboard's existing `goal`/`todayNutrition` pattern.

## 5. Out of scope for this pass

- The full macro-jigsaw solver (freely recomposing meals to hit exact targets) — still parked separately; this is the curated-menu version, not that.
- Locked-ingredient portion scaling (see Section 2) — fixed quantities only.
- Multi-slot menus in one option (e.g. an option that spans breakfast *and* a snack) — each option belongs to exactly one slot.
