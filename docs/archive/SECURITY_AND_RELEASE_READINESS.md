# Security and V1 release-readiness review

Review basis: source and migration inspection on 2026-10-04. This is a static review, not a penetration test, production Supabase configuration inspection, or Xcode build/release validation. Findings below distinguish confirmed repository facts from production settings that must still be checked.

## Release blockers

### P0 — Resolve the README merge conflict

`README.md` was in an add/add merge conflict. Its working-tree content has now been reconciled, preserving the setup and nutrition-import notes and adding the documentation links. Git still reports it as unmerged until the resolved file is staged; finish that before committing or shipping.

### P0 — Keep the untracked Supabase environment backup out of Git

`supabase/.env.save` is untracked and the ignore rule `*.env` does not match the `.env.save` suffix. It was one byte when inspected, but the filename pattern is unsafe for future backups. Do not commit it; add an explicit ignore rule for this pattern. Check any replacement backup locally without pasting credentials into chat or logs. If a service-role key or other secret has ever been committed/shared, rotate it in Supabase and inspect git history; removing the working file alone does not revoke a credential.

### P0 — Establish reproducible migration deployment

The repository has 69 migration files and the prior project notes describe hand-pasting SQL. V1 needs a repeatable, reviewed migration process and evidence that all migrations apply to a fresh database and upgrade a copy of the current database. Record the expected Supabase CLI/project workflow and backup/restore procedure. Do not ship with untracked dashboard-only schema changes.

## High priority before inviting external users

### P1 — Audit the deployed Supabase security posture

Static inspection found RLS enabled in migrations for all 43 declared application tables, which is a good baseline. The two aggregate views explicitly use `security_invoker = true`, and `weekly_log_summary` is declared `security invoker`; these avoid the common view-owner RLS bypass pattern in the checked migrations. This still does not prove deployed RLS is current or correct. Verify deployed schema matches migrations; test two separate users against every table, nested child record, view, and storage operation (read, insert, update, delete). Check grants, view security-invoker behavior, Auth settings, rate limits, backups, and storage limits. Use automated policy tests in CI before schema changes.

### P1 — Put bounds and moderation around shared catalog writes

`foods_insert_off_lookup` allows any authenticated user to add shared `source='off'` catalog rows. That matches the documented crowdsourcing design, but permits duplicate, misleading, malformed, or abusive catalog growth unless there are constraints and operational controls. Add/verify validation, unique barcode conflict handling, sane numeric limits, deduplication, and a moderation/cleanup path before public release.

### P1 — Document account/data lifecycle

The reviewed app has sign-in but no visible account creation/recovery/deletion journey found in the inspected auth UI. Define how users recover access, export their data, delete their account and photo objects, and what happens to queued/cached device data after sign-out or account switch. Verify local caches and queues are separated by user and cleared appropriately; inspect storage protection for offline files that include health data.

### P1 — Confirm photo and route privacy

Photo objects use a private bucket and owner-scoped policies with signed URLs. Verify URL lifetime, bucket MIME/size limits, metadata cleanup, and account deletion cleanup. Running route coordinates can reveal home/work locations: document purpose and retention, provide deletion controls, and ensure route data cannot be queried across users.

### P1 — Validate offline replay behavior

Queues persist sensitive health/nutrition/training records locally. Verify iOS file protection/encryption assumptions, logout/account-switch isolation, idempotency after partial success, duplicate prevention, data retention, and bounded retry behavior. Include recovery guidance for a corrupt/unreadable queue and observability for repeated failures.

### P1 — Bind local caches and pending writes to the signed-in account

The app has a Sign Out action, while offline stores/caches are process-wide singletons with fixed local keys/paths. The inspected sign-out path only calls Supabase Auth; it does not visibly partition or clear cached records and queued writes by user. On a shared device or after switching accounts, stale records may be shown or pending writes may be replayed under a different session. Namespace local stores by authenticated user ID, make replay verify the original owner, and define safe sign-out behavior (flush or retain explicitly, then lock/clear user-specific data).

## Maintainability / correctness issues to address for V1

- **Stale and contradictory docs:** older design briefs describe features as unbuilt even though later migrations and screens implement them. Add status/date/links to current code or archive superseded briefs; make this documentation set the maintained overview.
- **Code size and repetition:** the app has many repository/service/model types and repeated CRUD/query/encoding patterns. Reduce safely in measured steps: inventory duplicated operations and oversized files, centralize shared validation/date/ownership/query behavior where it improves correctness, remove only proven unused code, and avoid a generic abstraction that hides domain rules. Preserve clear boundaries between UI, calculations, persistence, and HealthKit.
- **Test gap:** do not assume existing self-test scaffolding proves release behavior. Build a focused test plan for deterministic calculations, offline queue replay, date/time-zone boundaries, RLS isolation, migration upgrades, and nutrition snapshot semantics. Test coverage must exist before aggressively merging models or repositories.
- **Force unwraps and fatal failures:** the source contains force unwraps in generated label/index helpers and chart plot-frame access, plus fatal errors for missing config and offline store initialization. Replace user/data-dependent crash paths with safe fallbacks and surface actionable startup/storage errors before release.
- **Input and domain constraints:** audit numeric bounds and database check constraints for calories/macros, quantities, weights, durations, route points, and dates. Validate on both client and server; client-only validation can be bypassed.
- **Build/release controls:** confirm a clean Release build, signing, minimum iOS version, privacy manifests/required-reason APIs as applicable, HealthKit purpose strings, dependency versions, crash reporting policy, and a tagged rollback-ready release. Static inspection here did not run a build.

## Positive controls observed

- The iOS client reads Supabase URL and anon key from build configuration; the source does not show a service-role key embedded in the app.
- The app's central Supabase service uses the authenticated client session.
- Migrations define owner policies on all 43 tables found by static extraction.
- Progress photos use a non-public bucket and UUID-prefixed owner paths.
- HealthKit integration is currently read-only in the inspected code.

## V1 ship checklist

- [ ] Resolve README conflict and document setup, supported iOS version, and known limitations.
- [ ] Confirm no secret is tracked or exposed; rotate any exposed secret.
- [ ] Reconcile local migrations with deployed Supabase schema and prove fresh-install plus upgrade paths.
- [ ] Execute cross-user RLS/storage tests and backup/restore drill.
- [ ] Confirm account recovery, export/deletion, privacy notice, data retention, and local-cache cleanup.
- [ ] Complete Release build and device smoke test for sign-in, core logging, edits/deletes, HealthKit denied/granted, offline queue and reconnect.
- [ ] Resolve crash paths and verify health/nutrition calculations at boundary dates/values.
- [ ] Publish a prioritized issue list for non-blocking cleanup and V2; tag and archive the V1 release.

## Suggested GitHub issues

1. **P0: Resolve conflicted README and publish canonical setup guide.**
2. **P0: Ignore environment backups and audit/rotate exposed secrets.**
3. **P0: Automate Supabase migration, RLS, and upgrade verification.**
4. **P1: Add account export/deletion and clear user-scoped offline data.**
5. **P1: Bound and deduplicate shared Open Food Facts catalog inserts.**
6. **P1: Verify route/photo privacy, retention, and storage constraints.**
7. **P1: Bind local caches/queues to the account and harden replay after partial success.**
8. **P1: Add calculation, persistence, queue, and policy test coverage.**
9. **P2: Reduce code duplication and split oversized UI/repository responsibilities using measured refactors.**
10. **P2: Refresh/archive stale briefs and establish docs maintenance conventions.**
