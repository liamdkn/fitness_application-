# Fitness Tracker

Personal iOS app unifying workout progression, nutrition, and Apple Health
sleep/steps into one dashboard for tracking a cut.

## Layout

- `ios/` — SwiftUI app (Xcode project)
- `supabase/` — Postgres schema/migrations, Auth (shared backend)

Nutrition (calories/macros) is logged manually in the app rather than
imported from MyFitnessPal — see `docs/mfp-sync-spike.md` for why the
automated-import approach was abandoned (Cloudflare blocks scripted access,
including headless-browser automation) if that's ever worth revisiting.

## Setup

1. `supabase/` — apply the migrations in `supabase/migrations/` against your project.
2. `ios/` — open in Xcode, copy `ios/FitnessTracker/Config.xcconfig.example`
   to `Config.xcconfig` and fill in your Supabase URL/anon key.
