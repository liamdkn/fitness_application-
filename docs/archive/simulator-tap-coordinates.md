# iOS Simulator MCP: getting reliable tap coordinates

Context: the `mcp__Claude_Code_iOS_Simulator__control` tool's `tap`/`swipe`/`touch_path`
actions take coordinates in **device points**, not screenshot pixels. Confusing the two
is the main cause of failed taps on small targets (e.g. repeatedly missing a
"Set Up My Split"-sized button).

## Key finding: there is no accessibility-tree tool for the simulator

Unlike the in-app Browser tools (which have `read_page` returning a `ref_N`-tagged
accessibility tree you can click by reference), the iOS Simulator MCP server exposes
only two tools: `control` (screenshot/tap/swipe/type/button/open_url) and `build`
(xcodebuild wrapper). Neither returns an accessibility tree or element frames.

Checked and ruled out on this Mac (2026-08-11):
- `xcrun simctl` has no accessibility/UI-hierarchy subcommand. `simctl ui <device> ...`
  only gets/sets appearance, contrast, and content-size settings — not element frames.
- `idb` (Facebook/Meta's `idb` + `idb_companion`, which does provide
  `idb ui describe-all` — an accessibility tree with frames in points) is **not
  installed** (`brew` is available, so it could be added if this capability becomes
  worth the dependency: `brew tap facebook/fb && brew install idb-companion` plus
  `pip install fb-idb`). Not installed proactively since it's a new dependency the user
  hasn't asked for.

So today, coordinate targeting on the simulator is necessarily screenshot-based —
there's no shortcut around visually estimating a point and converting it correctly.

## The actual coordinate mapping (verified empirically)

For the booted iPhone 17 simulator in this session:
- `xcrun simctl io booted screenshot` writes a **1206 × 2622 px** PNG (native/@3x
  framebuffer resolution).
- The `control` tool's tap coordinates are in **device points**: **402 × 874** for
  iPhone 17. That's exactly the pixel size divided by the display scale (3x here:
  1206/3 = 402, 2622/3 = 874).
- Verified live: tapping `(68, 820)` — computed as roughly (17%, 94%) of the screen
  in point-space — landed correctly on the "Dashboard" tab bar item.

The screenshot image *as returned by the `control` tool's `screenshot`/`attach` actions*
may not be at the native 1206×2622 resolution by the time it reaches the model (vision
inputs are often resampled). **Never read pixel coordinates off the displayed image and
pass them to `tap` directly** — that pixel grid's size is not guaranteed to match either
the framebuffer resolution or the point-space the tool expects.

## Reliable procedure

1. Take a screenshot (`control` action `screenshot`, or `attach` for a live view).
2. Estimate the target element's position **as a fraction of the screen**, e.g. "the
   button is about 55% across and 88% down" — judged visually from the image, not from
   pixel coordinates.
3. Get the device's point dimensions. The `launch` action's result reports them
   directly. If you only have a screenshot, they can also be derived once per device
   type via:
   ```bash
   xcrun simctl io booted screenshot /tmp/probe.png
   sips -g pixelWidth -g pixelHeight /tmp/probe.png
   ```
   then dividing by the display scale (3 for all current iPhones except the 2x SE/8-class
   devices — if unsure, the point size is usually documented per device type, or can be
   inferred: recent non-Pro-Max/Pro iPhones and iPads are 3x or 2x respectively).
4. Multiply the fraction from step 2 by the point dimensions from step 3 to get the
   `x`/`y` to pass to `tap`.
5. For small or ambiguous targets, `zoom` on a region first to confirm the exact visual
   position before computing the fraction, then re-derive the point coordinate — don't
   guess twice on the same blind estimate.
6. After tapping, take another screenshot to confirm the expected screen transition
   happened before proceeding (as done here: tap → screenshot → verify "Dashboard"
   rendered).

## Common values for reference

| Device | Point size (pt) | Native px (approx) | Scale |
|---|---|---|---|
| iPhone 17 | 402 × 874 | 1206 × 2622 | 3x |

Add rows here as other simulators get used in this project, using the
`xcrun simctl io booted screenshot` + `sips` probe above to confirm rather than
assuming from memory — Apple's point sizes for new device generations aren't
always obvious.
