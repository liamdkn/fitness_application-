# Edit a logged meal entry's quantity (tap-to-edit grams)

## The ask

In a meal slot (e.g. Preworkout), tapping an already-logged item
should open the grams/quantity editor pre-filled with what's
currently logged, so a mislogged amount can be corrected without
deleting and re-adding the entry.

## Current state

`MealLogSection.swift` renders each logged item as a plain, non-
tappable `HStack` (name + quantity/serving label + calories) inside
`ForEach(group.entries)`, with only `.onDelete` wired up (swipe to
remove) - no tap gesture, no edit path at all today.

The pieces needed already mostly exist, just not connected:
- `MealEntryRepository.updateQuantity(id:quantity:)` already exists
  and works (`PATCH` on `meal_entries.quantity`) - currently called
  from nowhere in the app.
- `LogFoodQuantityView` (private struct inside `FoodPickerView.swift`)
  is exactly the grams/servings editor UI wanted here - segmented
  Servings/Amount toggle, live macro breakdown ring - but it's scoped
  to the *add new entry* flow (`food: Food`, `onConfirm: (Double) ->
  Void` calling `viewModel.logFood`), it's `private` so it can't be
  reused from another file as-is, and it only accepts a `Food`, not a
  `Recipe` - but a logged slot entry can be either (`MealSlotEntry`
  already carries both `food`/`recipe`, optional).

## What to build

1. **Generalize the editor, don't duplicate it.** Change
   `LogFoodQuantityView` from `private` to `internal` (or extract it
   as its own file) and widen it to accept either a `Food` or a
   `Recipe` as the thing being quantified - it already only needs
   `servingLabel`/`servingUnit`/`servingSize` and the four
   `calories(at:)`/`proteinG(at:)`/etc. methods, which both `Food`
   and `Recipe` already implement independently today (confirmed:
   `MealSlotEntry.calories` already calls `food?.calories(at:) ??
   recipe?.calories(at:)`) - a small protocol (e.g. `Quantifiable`)
   both conform to is the cleanest way to let the view take either
   without an `if food != nil` branch inside it.

2. **Distinguish add vs edit mode.** Same view, two entry points:
   - Add (today): title "Add Food"/pending food, pre-fills from
     `fetchLastQuantity`, confirming calls `logFood`/`logRecipe`
     (insert).
   - Edit (new): title reflects editing the existing entry,
     pre-fills from the entry's *own current* `quantity` (not
     `fetchLastQuantity` - that's "what did I log last time
     historically," this is "what's logged right now"), confirming
     calls the new `MealLogViewModel.updateQuantity` (below) instead
     of inserting.

3. **`MealLogViewModel.updateQuantity(_ entry: MealEntry, quantity:
   Double) async`** - new method, same shape as the existing
   `deleteEntry(_:)` a few lines below it: call
   `mealEntryRepository.updateQuantity(id:quantity:)`, then replace
   the matching row in `@Published var entries` in place (find by
   id, overwrite `quantity`) so the UI updates immediately without a
   full reload.

4. **`MealLogSection` wiring:** wrap each row's content in a `Button`
   (replacing the plain `HStack` label) that sets a new
   `@State private var editingEntry: MealSlotEntry?`, and add a
   `.sheet(item: $editingEntry)` presenting the generalized editor in
   edit mode, passing through whichever of `food`/`recipe` the entry
   has. Swipe-to-delete (`.onDelete`) stays as-is alongside the new
   tap-to-edit - not a replacement for it.

## Scope

Quantity/amount only, matching what was actually asked - not a
"swap this logged item for a different food" editor. If an entry was
logged as the wrong food entirely, delete-and-re-add (existing swipe
gesture) is still the way to fix that.
