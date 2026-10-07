# Fitness Tracker

A personal iOS app for long-term tracking of strength training, cardio/running, nutrition, body measurements, sleep, steps, hydration, and progress. Built with SwiftUI, Supabase, and Apple HealthKit.

The product is intended to evolve over many years. V1 focuses on reliable personal tracking and privacy; the planned V2 direction adds carefully scoped, opt-in LLM assistance. Start with the [documentation index](docs/README.md), [product and roadmap](docs/PRODUCT_AND_ROADMAP.md), [V1 release checklist](docs/V1_RELEASE_CHECKLIST.md), and [code editor handoff](docs/CODE_EDITOR_HANDOFF.md).

## Repository layout

- `ios/` — SwiftUI iOS app, widget, and Live Activity.
- `supabase/` — Postgres migrations and backend project configuration.
- `docs/` — product/roadmap, release checklist, and prioritized engineering handoff; older briefs are archived.

Nutrition is logged in the app; automated MyFitnessPal import was abandoned. The investigation is preserved in [`docs/archive/mfp-sync-spike.md`](docs/archive/mfp-sync-spike.md).

## Setup

1. Configure a Supabase project. Review the ordered SQL migrations under `supabase/migrations/`; the repeatable deployment/rollback workflow is a V1 release gate in the [checklist](docs/V1_RELEASE_CHECKLIST.md).
2. Open `ios/FitnessTracker/FitnessTracker.xcodeproj` in Xcode.
3. Copy `ios/FitnessTracker/Config.xcconfig.example` to `ios/FitnessTracker/Config.xcconfig` and set the Supabase project URL and anon/publishable key. Never put a service-role key in the iOS app.
4. Build and run on an iOS device or simulator. HealthKit features require a supported device and user permission.

See [`docs/V1_RELEASE_CHECKLIST.md`](docs/V1_RELEASE_CHECKLIST.md) before treating this as a public V1 release. The docs describe current implementation findings and release work that remains; they are not a claim that production configuration has been penetration-tested.
