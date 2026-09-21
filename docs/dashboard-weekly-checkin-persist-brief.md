# Weekly Check-In row shouldn't disappear from the Dashboard once done

## The bug

Confirmed in code: `CheckInsCard` (`Views/Dashboard/DashboardView.swift`)
only renders the Weekly Check-In row `if weeklyDue`, and `weeklyDue`
comes from `CheckinAvailabilityService.weeklyDue`, which is set to
`false` the moment a check-in exists for the current week -
`refresh()` computes it as `!hasWeeklyCheckin`, and
`checkinCompleted(.weekly)` also sets it to `false` directly right
after the flow finishes. So the row is only ever visible *before*
you've done it, and vanishes from the Check-Ins card entirely for
the rest of the week the second it's completed (or on next
`refresh()`, e.g. reopening the app) - matches what Liam's seeing.

Related, smaller bug while in there: even before it disappears, the
row is built with `checkinRow(label: "Weekly Check-In", completed:
false)` - hardcoded `false`. The Daily Check-In row correctly reflects
`dailyCompleted`; the weekly one never shows a checkmark at all, even
on a week where it's already done and still momentarily visible.

## Fix

Same pattern as the daily row, which already gets this right:

1. **`CheckinAvailabilityService`**: keep `weeklyDue` if something
   else still needs "not yet done this week" as a boolean, but the
   Dashboard card needs the row to always render regardless - add
   (or repurpose) a published `weeklyCompletedThisWeek` that's simply
   `!weeklyDue`, mirroring `dailyCompletedToday`.

2. **`CheckInsCard`**: drop the `if weeklyDue` wrapper around the
   Weekly Check-In `Button`/`Divider` - render it unconditionally,
   same as the Daily row. Pass `completed: weeklyCompletedThisWeek`
   into `checkinRow` instead of the hardcoded `false`.

3. **Tap behavior when already completed**: the existing code
   comment above `checkinRow` says tapping a completed row should
   reopen "the same sheet, pre-filled with today's saved answers" -
   true for Daily (`DailyCheckinSheet` presumably supports this
   already, matches the comment), but `WeeklyCheckinFlow` has no such
   mode - it only ever starts blank (`weightText = ""`, no loading of
   an existing check-in). Don't build prefill-editing into
   `WeeklyCheckinFlow` for this fix - simpler and already-available:
   route `onTapWeekly` to `WeeklyCheckinDetailView(checkin:)` instead
   of `WeeklyCheckinFlow` when already completed this week.
   `WeeklyCheckinDetailView` already exists and already does exactly
   this (currently only reached via Settings -> Weekly Check-In ->
   Check-In History) - it just needs the current week's `WeeklyCheckin`
   row passed in, which `CheckinAvailabilityService.refresh()` already
   fetches the existence of (`hasCheckinSince`) and can be widened to
   also hand back the actual row, not just a bool.
   `WeeklyCheckinFlow` still opens as today when `weeklyCompletedThisWeek`
   is `false` (nothing due yet this week).

This view is explicitly read-only today per its own doc comment
("nothing here is editable") - if "just viewed" should also mean
"and can fix a mistake," that's the earlier-parked check-in-editing
work from `docs/weekly-checkin-wrapped-brief.md` (history becoming
editable), not this fix. This brief only stops the row from
disappearing and shows the right completed state; turning
`WeeklyCheckinDetailView` itself editable is a separate, bigger
change already scoped elsewhere.
