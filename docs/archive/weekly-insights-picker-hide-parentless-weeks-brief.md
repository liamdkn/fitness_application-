# Weekly Insights week picker: hide weeks with no goal phase

## Context (Sep 18)

Liam has two weeks of logged data (Aug 3–9 and Aug 10–16, 2026) that
don't fall inside any goal phase - logged before/between phases, not
part of a cut. They currently show up as rows in the Weekly Insights
week picker with just a bare date range instead of a phase label
(e.g. no "Cut week 3" text), because `WeeklyLogViewModel.phaseLabel(for:)`
correctly returns `nil` for a week no goal phase covers.

Originally scoped as a data-deletion request (a one-off SQL script was
drafted for it), but Liam decided he doesn't want the data gone - he
just doesn't want these "parentless" weeks cluttering the picker. This
is a UI filter, not a data change. **The SQL cleanup script
(`supabase/one_off/2026-09-18_delete_aug3_16_orphan_data.sql`) and its
brief (`delete-aug3-16-orphan-data-brief.md`) are superseded by
this doc and should not be run/implemented.**

## Where it lives

`Views/Dashboard/WeeklyInsightsView.swift`, `WeekPickerList` (private
struct, ~line 302). It reads `viewModel.entries` (populated by
`WeeklyLogViewModel.loadInitial()` / `loadMoreIfNeeded()`, backed by
`WeeklyLogRepository.fetchSummary`) and reverses them into
`orderedEntries` for display. `phaseLabel(for:)` already exists on
`WeeklyLogViewModel` and already returns `nil` for exactly this case -
no new phase-detection logic needed.

## Fix

Filter `orderedEntries` to only include entries where
`viewModel.phaseLabel(for: entry) != nil` - i.e. only show weeks that
fall inside a goal phase. Keep the "This Week" special case (current
week should still show even if, unusually, it has no active phase -
or decide to hide that too; Liam's ask was specifically about past
weeks cluttering the list, so leaning toward: always show the current
week row, filter historical rows by phase coverage).

```swift
private var orderedEntries: [WeeklyLogEntry] {
    viewModel.entries
        .filter { entry in
            isCurrentWeek(entry) || viewModel.phaseLabel(for: entry) != nil
        }
        .reversed()
}

private func isCurrentWeek(_ entry: WeeklyLogEntry) -> Bool {
    Calendar.current.isDate(
        entry.weekStartDate,
        equalTo: WeeklyInsightsViewModel.mondayOfWeek(containing: Date()),
        toGranularity: .day
    )
}
```

(`label(for:)` already has this same current-week check inline - fine
to factor it out into the shared `isCurrentWeek` helper above and reuse
it in both places, or leave `label(for:)` as-is if that's simpler.)

## Pagination note

`loadMoreIfNeeded` triggers off `entries.last?.id == currentEntry.id`
inside the `.task` on each row. Since the filter now happens in
`orderedEntries` (a derived view), the underlying `viewModel.entries`
array is untouched - pagination keeps working off the raw unfiltered
data, it's only the picker's rendered list that skips parentless rows.
No change needed there, just confirming it doesn't break by filtering
at the display layer instead of the data layer.

## Scope

Purely additive/filtering, no schema or repository changes. Doesn't
touch `WeeklyLogViewModel.entries` itself, so any other consumer of
that view model (if one exists beyond this picker) is unaffected. Data
for Aug 3–16 stays in the database exactly as-is - it's just not
offered as a selectable week in this specific picker.
