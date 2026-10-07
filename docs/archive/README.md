# Archived project briefs

These documents preserve prior investigations, feature briefs, design decisions, and handoff notes. They are kept for history and research, not as an active work queue. Many describe features that have since been built; some are superseded or contain implementation details that no longer match the code. Before implementing an archived proposal, check the current Swift and SQL source and the [code editor handoff](../CODE_EDITOR_HANDOFF.md).

## Architecture, product direction, and AI

- `nutrition-rebuild-and-apple-health-plan.md` — original in-house nutrition and HealthKit design; major nutrition pieces now exist.
- `v1-wrapup-and-v2-roadmap.md` — earlier V1 cleanup and V2 ideas; superseded by the current [product roadmap](../PRODUCT_AND_ROADMAP.md).
- `ai-insight-assistant-brief.md` — detailed in-app assistant concept; use the current roadmap's server-side/privacy limits as the current direction.
- `adherence-and-insights-audit.md` — score design and gaps for completeness, trend visibility, weekly review, and data use.
- `adaptive-tdee-v2-brief.md`, `watch-activity-energy-crosscheck-brief.md`, `healthkit-signals-v2-brief.md` — future TDEE/Watch/HealthKit experiments; validate data quality and privacy first.
- `mfp-sync-spike.md` — MyFitnessPal import investigation; decision was to abandon automated import.

## Nutrition

- `nutrition-in-house-revamp-brief.md`, `food-search-verified-sources-brief.md`, `nutrition-label-scan-brief.md`, `meal-entry-edit-quantity-brief.md`, `meal-plan-options-brief.md` — nutrition UX/design evolution; compare with current food/meal implementation.
- `tdee-nutrition-source-bug-brief.md`, `nutrition-source-cutover-date-fix-brief.md`, `off-plan-bump-exclusion-consistency-brief.md` — source, date-boundary, and trend-calculation investigations; recheck against current engines and migrations.

## Training, check-ins, and reporting

- `train-tab-gym-notes-brief.md`, `dashboard-checkin-weight-insights-train-brief.md`, `dashboard-weekly-checkin-persist-brief.md`, `weekly-checkin-wrapped-brief.md`, `weekly-log-brief.md`, `weekly-insights-picker-hide-parentless-weeks-brief.md` — training UX, check-in, and weekly reporting requests; several have since changed or shipped.
- `running-plan-brief.md`, `half-marathon-plan-content.md`, `pt-program-integration-brief.md` — running and training-program planning notes.
- `delete-aug3-16-orphan-data-brief.md` — explicitly superseded; do not run the proposed deletion. The decision was to keep data and adjust the picker.

## Reference notes

- `simulator-tap-coordinates.md` — simulator interaction notes, not product documentation.
