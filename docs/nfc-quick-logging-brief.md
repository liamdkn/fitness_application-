# NFC quick-logging (water, supplements) — brief

## Context

Liam has a box of NFC coin tags and wants to place them around the house/places so logging is one tap instead of opening the app and navigating to a screen — starting with water, and "logging things" more generally.

## What already exists (no new code needed for water)

The widgets target already ships a real `AppIntent`:

- `FitnessTrackerWidgets/AddWaterIntent.swift` — `AddWaterIntent: AppIntent`, title "Log Water", parameters `amountMl: Int` and `containerId: String?`. `perform()` writes to `PendingWater` (an App Group queue, `Shared/PendingWater.swift`) and reloads the widget timeline.
- The main app drains that queue (`WaterRepository.importWidgetWater()`, called from `MainTabView` on launch/foreground) and logs each entry to Supabase with its original tap timestamp, not the time the app happened to open.

Any `AppIntent` in the app or its extensions is automatically discoverable in the Shortcuts app as an action for "FitnessTracker" — no `AppShortcutsProvider` is needed for that, it's only needed for Siri phrases / the Shortcuts gallery card, neither of which matters here. That means **water logging via NFC works today with zero Swift changes**:

1. In Shortcuts, create a shortcut per amount you want a tag to log (e.g. "Log 500ml Water"): add the "Log Water" action (search for FitnessTracker), set Amount to 500, leave Container empty (or pick one if you want it tied to a specific bottle/mug).
2. Automation tab → + → NFC → scan the tag → choose that shortcut → turn off "Ask Before Running" so it fires silently.
3. Repeat for however many tags/amounts you want (e.g. a 500ml "big bottle" tag by the fridge, a 250ml "glass" tag by the sink).

One real caveat worth knowing before you wire this up: the widget extension has no network/backend access, so the tap only writes to the local queue — it reaches Supabase (and so other devices/widgets) the next time the app is foregrounded, not instantly. Fine if you open the app regularly through the day; if a tag sits untouched for a day it'll just show up late rather than not at all.

## What's new: a supplement/creatine tag

There's no equivalent intent for supplements yet, and the existing `SupplementRepository`/`Supplement` model (`unit`, `amountPerServing`, `servingsPerDay`) has everything needed to log a single serving taken. Proposed, mirroring `AddWaterIntent` exactly:

- New `FitnessTrackerWidgets/LogSupplementIntent.swift`: `LogSupplementIntent: AppIntent`, title "Log Supplement", one parameter `supplementId: String` (use an `AppEntity`-backed `SupplementEntity` so Shortcuts shows supplement names to pick from, rather than a raw UUID string field — same idea as `containerId` on water but friendlier since there's no sensible numeric default to type).
- New `Shared/PendingSupplement.swift`, same shape as `PendingWater.swift` (App Group queue entry: `id`, `supplementId`, `at`).
- `MainTabView`'s existing drain-on-foreground call gets a second line: `await SupplementRepository().importWidgetSupplementLogs()` (new method, same pattern as `importWidgetWater()` — one `LogWrite` insert per queued entry, using the entry's `at` as the logged time).

Once that intent exists, the Shortcuts/NFC setup is identical to water: a shortcut with "Log Supplement" → pick the supplement → bind to a tag wherever that supplement actually lives (e.g. the kitchen counter next to it, or your gym bag for a pre-workout).

## What I'd skip for now

Cardio/incline-walk start-stop over NFC isn't a good fit for the same pattern: a session has live state (pause/resume, steps-during, HR) that only means something while the app or Watch is actually tracking it, so a fire-and-forget queued "start" wouldn't give you anything a Watch-detected session (which the running-plan work already covers) doesn't. If there's a specific friction point there later it's worth its own look, but it's a different shape of problem than "log a fixed amount of something."

## Split

- **Claude Code**: `LogSupplementIntent.swift`, `PendingSupplement.swift`, `SupplementEntity` (AppEntity conformance for the picker), `SupplementRepository.importWidgetSupplementLogs()`, wire the drain call into `MainTabView`.
- **You, one-time, no code**: water logging today — build the Shortcuts actions and NFC automations per tag as above; same again for supplements once the intent ships.
