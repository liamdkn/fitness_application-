# Nutrition label scanning (OCR)

## The ask

When a product isn't found through barcode lookup or the search
fallback chain (`food-search-verified-sources-brief.md`), let
the user point the camera at the actual nutrition facts panel on the
pack and have the app read the numbers off it automatically -
Liam's framing: "like a credit card scan" - tied to the barcode
already scanned, saved into the system.

Worth being upfront about scope before Claude Code picks this up:
this is a meaningfully bigger, more speculative build than the
search-fallback work - real computer vision + text parsing, not
another API integration - and first-pass accuracy won't be perfect.
Framing it as auto-fill-then-confirm rather than fully automatic
capture is what makes that acceptable rather than a reliability risk.

## 1. How "credit card style" scanning actually works, applied here

iOS doesn't have a built-in "nutrition label" data type the way
`DataScannerViewController` has built-in recognizers for phone
numbers, emails, and (via `VNRecognizeTextRequest`, matched against
Luhn-check regex) numbers formatted like card numbers. There's no
off-the-shelf equivalent for a nutrition panel's numbers. What
credit-card scanners actually do under the hood is exactly what this
needs to replicate: live OCR of camera frames via the Vision
framework (`VNRecognizeTextRequest`, `.accurate` recognition level),
then regex/keyword matching the recognized text lines against a
known label pattern, updating a live overlay as fields get found
and confirmed - not a fundamentally different technique, just a
different pattern to match against.

Approach:
- `AVCaptureVideoDataOutput` feeding frames into `VNRecognizeTextRequest`
  at a throttled rate (e.g. every 3rd-5th frame - full-rate OCR is
  wasted CPU/battery for text that isn't moving fast).
- Per recognized text line, look for a label field name (see Section
  2 for the format problem) immediately followed by a number and a
  unit token (`g`, `mg`, `kcal`, `kJ`).
- As fields get matched with reasonable confidence, populate a live
  on-screen form (mirrors the credit-card-scan UX Liam described -
  fields fill in as they're recognized, not all-or-nothing).
- User reviews/edits the filled form before confirming - this is the
  accuracy safety net. OCR mis-reads (a smudged "8" as a "3", a
  missed decimal point) are expected sometimes; the user catching
  and fixing an obviously wrong number before saving is what makes
  this trustworthy rather than quietly polluting the shared catalog.

## 2. Irish/EU labels vs US labels - a real format difference

This matters concretely because Liam shops Tesco/Aldi Ireland, which
use EU-format labels, not US ones - the parser needs to target the
right format from the start, not the US layout that's more commonly
assumed:

- **EU/Irish**: "Energy" in kJ *and* kcal, "Fat" / "of which
  saturates", "Carbohydrate" / "of which sugars", "Fibre" (not
  "Fiber"), "Protein", "Salt" (not "Sodium" - salt-to-sodium is a
  simple ×0.4 conversion if sodium is ever needed downstream).
  Numbers are typically given **per 100g/100ml**, often *also* per
  serving in a second column - both present is actually good, since
  it lets the parser cross-check its own reading (per-serving should
  roughly equal per-100g × serving-size/100).
- **US** (for completeness, in case any imported/US products come
  up): "Calories" prominent, "Total Fat", "Total Carbohydrate",
  "Dietary Fiber", "Protein", "Sodium" in mg. Different enough that
  detecting which format is being read (keyword presence: "Energy"
  vs "Calories", "Fibre" vs "Fiber") should happen first, before
  field-matching, rather than trying one universal pattern for both.

Building and tuning this parser against real Irish supermarket
labels (Tesco/Aldi own-brand especially, since that's the actual use
case) is most of the real work here - worth testing against a handful
of Liam's own pantry items early rather than guessing at label
formatting from general knowledge.

## 3. Tied to the barcode, saved as its own source

Flow: barcode scan (existing `BarcodeScannerView`) -> not found
through the fallback chain -> offer "Scan Nutrition Label" instead of
falling straight to manual entry. OCR'd result saves as a new `foods`
row with `barcode` set to the one already scanned (so it's a cache
hit for anyone next time, same as every other source), `source:
"ocr"` (added to the widened check constraint in the companion brief).

On `is_verified`: leave `false` for OCR-sourced entries. It's a real,
useful improvement over a blank manual entry (numbers came off the
actual pack, not guessed), but it isn't professionally verified the
way Nutritionix's data is, and OCR mis-reads are possible even after
one user's confirm step - conflating the two would make `is_verified`
mean less everywhere it's used. If this needs its own signal later
(e.g. "confirmed by pack scan" vs Nutritionix's "dietitian-verified"),
that's a display-label distinction, not the same boolean.

## 4. Not in this pass

- Auto-submitting OCR'd data back to Open Food Facts to help other
  OFF users - a nice idea (this app benefits from OFF's crowdsourcing,
  could give back to it), genuinely out of scope for a first pass.
  Worth a note for later, not now.
- Multi-angle/multi-photo stitching for a label that doesn't fit one
  frame (common on small supplement tub labels, ironically like
  Ghost's) - first pass assumes one frame captures the whole panel;
  flag as a known limitation rather than solving it immediately.
