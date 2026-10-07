# Use cases and product scope

## Product intent

A durable personal health and training journal, designed to evolve over many years. It brings training, nutrition, daily health signals, and review workflows together while keeping the user in control of their records. The current product is a single-user-per-account app; no sharing, coaching, or multi-tenant team workflow is documented in the UI.

## Primary user journeys

1. **Sign in and review today:** authenticate with Supabase, open the dashboard, see logged training/nutrition and available HealthKit signals, and complete a daily check-in.
2. **Plan and record strength training:** create routines and days, configure exercises and targets, record sets (including supersets/drop sets), review history and progression, and use the workout timer/Live Activity.
3. **Record cardio and running:** log cardio sessions and step-related sessions, track running plans and routes/metrics, and review past sessions.
4. **Log food:** search the local catalog or Open Food Facts, scan a barcode/label, add foods and meal entries, build recipes/meal preps, save meals/days, plan treats, and review macro totals.
5. **Track body and recovery signals:** record weight, measurements, progress photos, hydration, caffeine, sleep, steps, and daily/weekly check-ins; use trends and insights to review progress.
6. **Use the app with intermittent connectivity:** use cached catalog/reference data and supported write queues, then sync queued operations when connectivity returns. Users should be told clearly which operations are queued and which data is only cached.
7. **Review and correct history:** edit or remove incorrect entries and understand how corrections affect aggregates, adherence, and derived insights.

## User expectations to make explicit before V1

- The app provides tracking and calculations, not diagnosis or medical advice. Users can correct source data and should be able to distinguish measured, imported, and estimated values.
- HealthKit access is optional and granular. Denial should not prevent manual tracking. The app should explain what it reads and why in plain language.
- Nutrition data from public food catalogs can be incomplete or inaccurate; show source and allow correction without silently rewriting historical logged values.
- Privacy is central: body metrics, health records, food logs, injuries, routes, and photos are sensitive personal data.
- Define account recovery, account deletion/export, retention, and support expectations before inviting external users.

## Out of scope in the current build

No documented multi-user sharing, coach portal, web client, Android app, watchOS app, medical-grade recommendations, or deployed LLM assistant. These require separate product, privacy, security, and support decisions.
