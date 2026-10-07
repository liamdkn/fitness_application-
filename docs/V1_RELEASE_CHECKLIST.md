# V1 release checklist

This is a release gate, not a claim that V1 has passed. Source/migration inspection found a strong RLS baseline, but this review did not inspect the live Supabase project, run a security test, build the app, or test it on a device.

## Must close before release

### Repository and secrets

- [ ] Confirm `README.md` and the docs index are the canonical setup path.
- [ ] Add an ignore rule for `supabase/.env.save` and other environment backups. That file was one byte during review; do not commit future copies containing credentials.
- [ ] Check repository history and rotate any service-role or other secret that was ever exposed. The iOS app must contain only the public anon/publishable key.
- [ ] Keep a clean, reviewable release diff. The current working tree has uncommitted code changes and a new database migration; review and commit them deliberately.

### Database and access control

- [ ] Apply migrations using a repeatable, documented process; prove both a blank-database install and an upgrade from a representative existing database. Back up and practice restore first.
- [ ] Review the current untracked migration `0070_harden_inputs_and_storage.sql` before applying it. It scopes shared Open Food Facts and custom-food inserts to authenticated users, adds numeric/string bounds, and limits progress-photo uploads to 10 MB and listed image MIME types. Confirm constraints fit real app data and apply successfully.
- [ ] Compare deployed schema/policies with repository migrations. Static extraction found RLS enabled on all 43 application tables. The two aggregate views use `security_invoker = true`; the weekly summary function uses `security invoker`.
- [ ] Test two accounts against every private table, child relationship, aggregate view/function, and Storage operation (select/insert/update/delete). Check grants, Auth settings, rate limits, and backup retention.
- [ ] Verify route ownership, photo ownership, signed URL expiry, upload content checks, and cleanup when a record/account is removed.

### Local data and account lifecycle

- [ ] Review the current uncommitted `LocalData`/offline-cache changes. They introduce account claiming, cache/queue clearing, and an unsynced-change warning at sign-out; prove that account A's cache or pending writes never appear or replay under account B, including offline launch and token-refresh paths.
- [ ] Decide and implement account recovery, export, deletion, retention, and support expectations before external users. The inspected sign-in UI did not show a complete account lifecycle.
- [ ] Verify file protection for persisted workouts, meals, check-ins, weight, preferences, widget snapshots, and reminders.
- [ ] Test queue idempotency after partial success, duplicate replay, sign-out with pending changes, corrupt local stores, and bounded retries.

### Progress photos: explicit ship gate

- [ ] **Do not ship progress-photo uploads to Supabase.** Before V1, either remove the photo feature or keep photo files on-device only. This is a product security requirement.
- [ ] If keeping on-device photos: store them in the app sandbox with an appropriate strong iOS Data Protection class, exclude the app-support files from device backup if "device only" is literal, partition/clear them on account change, and verify no upload, telemetry, widget, or crash-report path copies photo bytes elsewhere. Explain that a compromised/unlocked device can still expose local data.
- [ ] If removing photos: remove/disable upload and display paths and delete existing rows/objects under a reviewed retention/deletion plan. Remove the Supabase bucket/policies only after confirming no production records remain and backups/retention are handled.
- [ ] CloudKit private storage is a possible later alternative only if the product decision changes to allow iCloud storage. It is still cloud storage and requires an iCloud account, per-user quota, key-reset/recovery handling, and account-bound design; it does not meet the current "device only or no photos" release condition.

### Product behavior and release validation

- [ ] Complete a clean Release build, signing, supported iOS version review, device smoke test, and rollback-ready tag.
- [ ] Reconcile the app/widget deployment-target settings and state the minimum supported iOS release in the setup docs.
- [ ] Smoke-test sign-in, logging/edit/delete for training and nutrition, HealthKit granted/denied, photo upload/view, notifications, widget/Live Activity, offline write/reconnect, and date/time-zone boundaries.
- [ ] Verify input bounds in both client and database for calories, macros, quantities, weight, duration, and route data.
- [ ] Verify missing logging days are shown as unknown with explicit coverage, and suppress/qualify adherence and TDEE claims when coverage is too sparse. Do not infer or silently insert calories for absent days.
- [ ] Replace data-dependent force unwrap/crash paths and make missing configuration/local-store failures actionable.
- [ ] Publish privacy and known-limitations language: tracking/calculations are not medical advice; HealthKit is optional; catalog nutrition values may be incomplete.
- [ ] Add focused automated coverage for calculations, migration upgrades, RLS isolation, offline queue/account behavior, and nutrition-history semantics. Avoid broad refactors until these invariants are protected.

## Findings and current confidence

| Area | What source inspection found | What remains unproven |
|---|---|---|
| RLS | All 43 extracted application tables enable RLS; most user rows use `auth.uid()` policies. Two views and the weekly RPC explicitly use invoker security. | Deployed parity, grants, policy edge cases, and real cross-user isolation. |
| Public catalog | An older policy allowed unauthenticated OFF food inserts. New untracked migration 0070 restricts both OFF and custom insert policies to `authenticated`. | Migration review/application, validation/deduplication abuse resistance. |
| Storage | Progress-photo bucket is private; object paths begin with user UUID; signed URLs are used. Migration 0070 adds limits. | Deployed bucket settings, ownership tests, route/photo retention and deletion. |
| Local data | New uncommitted code introduces account ownership/cleanup and a sign-out warning. | Build/runtime behavior and all offline/account switching cases. |
| Credentials | App reads project URL and anon key from build configuration; no service-role key found in inspected source. | Git-history review and deployed secret rotation status. |

## Release decision

Mark V1 shipped only when every checkbox above that applies to the intended audience is complete and reviewed. For a personal-only release, record any deliberately deferred external-user requirements explicitly; do not describe an unverified production security review as completed.
