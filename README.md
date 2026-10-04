# Fitness Tracker

A personal iOS app for long-term tracking of strength training, cardio/running, nutrition, body measurements, sleep, steps, hydration, and progress. Built with SwiftUI, Supabase, and Apple HealthKit.

The product is intended to evolve over many years. V1 focuses on reliable personal tracking and privacy; the planned V2 direction adds carefully scoped, opt-in LLM assistance. See the documentation index in [`docs/README.md`](docs/README.md).

## Repository layout

- `ios/` — SwiftUI iOS app, widget, and Live Activity.
- `supabase/` — Postgres migrations and backend project configuration.
- `docs/` — use cases, system design, security/release findings, and roadmap.

Nutrition is logged in the app; automated MyFitnessPal import was abandoned. See [`docs/mfp-sync-spike.md`](docs/mfp-sync-spike.md) for the investigation.

## Setup

1. Configure a Supabase project and apply the migrations under `supabase/migrations/` in order using the documented migration workflow.
2. Open `ios/FitnessTracker/FitnessTracker.xcodeproj` in Xcode.
3. Copy `ios/FitnessTracker/Config.xcconfig.example` to `ios/FitnessTracker/Config.xcconfig` and set the Supabase project URL and anon/publishable key. Never put a service-role key in the iOS app.
4. Build and run on an iOS device or simulator. HealthKit features require a supported device and user permission.

See [`docs/SECURITY_AND_RELEASE_READINESS.md`](docs/SECURITY_AND_RELEASE_READINESS.md) before treating this as a public V1 release. The docs describe current implementation findings and release work that remains; they are not a claim that production configuration has been penetration-tested.
