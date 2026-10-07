# Food scale: settings cleanup, Tare, units, and scoop-out logging

## Context

The Bluetooth kitchen scale is now paired and its protocol (Icomon-family handshake) is known and working. Two files were built for figuring that out: `Services/Scale/BluetoothScale.swift`/`ScaleDecoding.swift` (the connection + protocol-decoding engine, keep as is) and `Views/Scale/ScaleSetupView.swift` + `Views/Scale/LiveWeighView.swift` (the UI, which still has the reverse-engineering scaffolding from before the protocol was known). This brief is that UI cleanup plus three real behavior changes: Tare rename, per-ingredient units, and a new "scoop from a container" logging mode — the last one genuinely new, the rest are small.

## 1. Strip `ScaleSetupView` down to what's needed day to day

Remove, since the protocol is known and doesn't need re-discovering:
- The "Advanced" section entirely: the handshake buttons (`sendIcomonHandshake`, `sendIcomonHistoryRequest`, `sendFitdaysHandshake`, `sendFitdaysStart`), the raw hex `TextField`/`Send` button, and the `commandId`/`commandHex` state.
- The "What it offers" section (`scale.services` dump).
- The "Live data" section (`scale.log` raw-bytes list).

Keep: scan/found-list/connect, the connected-state `LabeledContent`s (connected-to, reading), and Disconnect. `BluetoothScale` itself (and `ScaleDecoding`) needs no changes — this is UI only, the debug plumbing in the service class can stay (harmless, just no longer surfaced) or be trimmed later if you want, not urgent.

## 2. `LiveWeighView` cleanup

- Remove the `#if DEBUG` "Practice (no scale)" section and its `simulate(adding:)`/`simulate(to:)` helpers.
- Remove `Toggle("Say it out loud", isOn: $speak)`, the `@AppStorage("scale-speak")` property, the `AVSpeechSynthesizer`/`AVFoundation` import, the `say(_:)` function, and the two call sites (`announceNext()`'s `if speak { say(...) }` and `log()`'s same line).
- Rename `Button("Start counting from zero") { engine.rebase(to: 0) }` to `Button("Tare") { engine.rebase(to: 0); message = "Tared." }` — same action, just the label (and message) a scale user actually recognizes.

## 3. Units: follow the ingredient, not a global setting

Today every amount in this screen is hardcoded to "g" (the live number, the plan list, the "Added to" list, the `"\(amount) g added"` message). The scale only ever reports mass, but once an ingredient is picked its own `servingUnit` (`Food.servingUnit`, already `"g"` or `"ml"` per food — e.g. milk is already `"ml"`) tells you how Liam thinks about it. So: for anything tied to a chosen food (plan rows, the "Added to" list, the per-log message), use `food.servingUnit` instead of a literal `"g"`. The one number that stays "g" is the live top-of-screen reading before any ingredient is picked, and the "N g on the scale is waiting" prompt — at that point nothing's been picked yet, so there's no unit to show it in besides the scale's own.

This gets you exactly the oats-recipe case: oats/protein/chia show in g, milk shows in ml, with no toggle to remember to flip. No separate app-wide unit setting needed.

## 4. New: "Scooping from a container" mode

The gap: today, weighing works by adding to an empty bowl — `LiveWeighEngine` reports `.added` when weight goes up, and whoever's picked as `currentFood` gets logged. But Liam's actual yoghurt move is the opposite: the full tub goes on the scale, he spoons some out into the bowl, and the weight that mattered just went *down*. The engine already detects this correctly (`.removed(grams:)` fires on a settled drop) — `LiveWeighView.receive()` just throws that event away today ("`X g taken off - not logged`").

Add a toggle next to "Choose what you're adding": `Toggle("Scooping from a container", isOn: $scoopMode)`. Behavior:
- Turning it on calls `engine.rebase(to: scale.live ?? liveGrams)` — whatever's on the scale right now (the full tub) becomes the new baseline, logged as nothing.
- While on, a `.removed(amount)` event is handled exactly like `.added` is today: if `currentFood` is set, `log(food, grams: amount)`; otherwise it becomes `pendingGrams` waiting for a choice, same as now.
- While on, an `.added` event (weight going up — tub topped back up, or the wrong thing happened) is not logged, just shown as a message ("Weight went up, not down — ignored.").
- Turning it off re-rebases the same way, so switching back to normal pour-in mode doesn't fire a spurious event from the container still sitting there.

This also quietly covers the burrito-bowl case where portions "change slightly each day" — same mechanism, just used on whatever's in hand that day.

## 5. New: a way to discard an unclaimed pending amount

Right now, if weight is added with no `currentFood` chosen (Liam's "throw random cinnamon in," or a splash of water he doesn't want tracked as a food), it sits in `pendingGrams` — and the *next* ingredient he picks silently absorbs it (`choose(_:)` logs `pendingGrams` against whatever food is chosen next), overstating that next ingredient by the untracked amount. Add a small "Skip this amount" button alongside the existing "`N g on the scale is waiting — choose what it is`" message, which just clears `pendingGrams` without logging anything (the engine's own `committed` total is already correct either way, since it updated when the event fired — this is purely about not misattributing it in the UI).

## What already works — no change needed

Two of the three use cases described are already fully covered by the existing additive flow, worth confirming rather than rebuilding:

- **One-off dish, ingredient by ingredient** (onion, peppers, carrots, shallots, garlic, paprika): this is exactly the existing "Adding now" flow outside of any saved-meal plan — pick a food from the picker, pour, it logs when settled, pick the next, repeat. Nothing new needed here beyond the unit and skip fixes above.
- **Meal-prepped burrito bowl + variable daily toppings**: log the prepped bowl itself as its usual fixed-macro meal-prep entry (unrelated to the scale), then open that same meal slot's "Scale" option to weigh the day's salsa/onion/lettuce/cottage cheese/hot sauce on top, ingredient by ingredient, same as above. Both entries land in the same slot. If this turns out to feel clunky in practice (e.g. you want a "weigh toppings" shortcut straight from the meal-prep detail screen rather than going through the slot), that's a small follow-up, not a redesign — flag it if so.

## Split

All of this is Claude Code / Swift work — `ScaleSetupView.swift` and `LiveWeighView.swift`, no new backend/migration needed (no new columns — `scoopMode` is view-local state, and logged entries still go through the existing `onLog(food, grams / food.servingSize)` path unchanged).

## 6. Hold-to-confirm advance, for the "Building the meal" plan flow

The gap this closes: the plan flow (`plan`/`planIndex`, the "Building the meal" section) advances to the next ingredient only when `log()` fires off an auto-detected `.added` event. But `LiveWeighEngine.minimumChange` is 1.0g — a real but tiny add (Liam's example: a recipe calls for 0.5g cinnamon, he actually shakes in 0.75g) can land under that floor and never fire an event at all. Today there's no way to tell the app "yes, I did add a bit, or deliberately nothing — that's correct, move on" — the only escape is `Skip`, which logs a flat 0g regardless of what's actually on the scale, so it's the wrong tool when a few tenths of a gram for real did land in the bowl.

Add a second control next to the existing `Skip` button: a press-and-hold "Confirm & Next" that requires about 3 seconds held down, with a progress bar filling behind the label while it's pressed (reset on early release, `.onLongPressGesture(minimumDuration: 3, pressing: { pressing in ... }, perform: { confirmAndAdvance() })` paired with a `@State private var holdProgress: Double` driven by a short repeating timer/`withAnimation` while `pressing` is true, so the fill actually tracks the hold rather than jumping at the end). The deliberate length and visible fill is the point — it's a different, harder-to-trigger-by-accident gesture from a normal tap, which is what makes it a real confirmation ("I looked at the scale and this is right") rather than a shortcut around the auto-detect.

`confirmAndAdvance()`:
- Reads whatever's currently displayed (`scale.live ?? liveGrams`) and subtracts `engine.committed` to get the real delta, uncapped by the engine's settle/tolerance/minimum-change logic — this is the one place that logic is deliberately bypassed, since the hold itself is the confirmation that would otherwise come from settling.
- Logs that delta (clamped to `max(0, delta)`, rounded to one decimal like elsewhere) against `plan[planIndex].food` — zero is a perfectly valid outcome here, and is exactly the "confirmed negligible, not a mistake" case.
- Calls `engine.rebase(to: scale.live ?? liveGrams)` so the engine's baseline matches reality going forward (this is the one path that updates `committed` outside of `ingest()` itself, since no threshold-clearing event fired to do it automatically).
- Clears `pendingGrams` if set, and advances via the same `plan[index].weighedGrams = ...; announceNext()` path `log()` already uses.

`Skip` stays as is, unchanged, for "not using this ingredient at all" — the new hold button is specifically for "something (possibly nothing, possibly a hair) really did happen and I'm telling you what's actually on the scale right now."
