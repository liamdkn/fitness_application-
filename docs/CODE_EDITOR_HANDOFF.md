# Code editor handoff: V1 hardening and cleanup

Use this as the implementation brief. Preserve unrelated user changes. The current working tree already contains uncommitted work in offline/account handling, HealthKit, weekly insights, workout behavior, and migration `0070`; inspect and build on that work rather than replacing it. Do not assume it is correct until reviewed. The broad goal is to make V1 safe and maintainable, then start V2 LLM work.

## P0 — release safety

1. **Secrets and ignore rules**
   - Add an explicit `.gitignore` entry for `supabase/.env.save` / environment backups.
   - Review tracked files and Git history for secrets without printing credentials. Rotate anything exposed; never use a service-role key in iOS.
   - Current `.env.save` is one byte, but its suffix currently bypasses `*.env`.

2. **Migration workflow and migration 0070**
   - Review `supabase/migrations/0070_harden_inputs_and_storage.sql` for valid constraints, compatibility with existing data, role scope, and bucket update behavior.
   - Test blank install and upgrade paths, including existing out-of-range rows (the constraints are `NOT VALID` so legacy rows are not checked until validated; new writes should still obey them).
   - Document a repeatable local/CI deployment and rollback/backup procedure. Do not rely on hand-pasted SQL or untracked dashboard changes.

3. **RLS and Storage proof**
   - Add automated tests with two users for every private table, nested child, view/RPC, and photo object operation.
   - Confirm live project parity, grants, function/view invoker security, auth configuration, rate limits, and backups.
   - Keep the shared OFF catalog policy intentional: only authenticated inserts, with server/database validation, deduplication, and cleanup path.

## P1 — account and local-data isolation

The dirty working tree currently introduces `LocalData.swift`, owner-aware outbox entries, queue/cache wipes, widget clearing, an auth-session claim hook, and a sign-out warning. Review this implementation end to end:

- Verify account A's cached content cannot render for account B after switching, reinstall/restore, offline launch, expired-session refresh, or sign-out.
- Verify pending writes always retain their original owner and are never sent under another account. Explicitly decide how legacy ownerless queue entries are handled; do not silently assign ambiguous health data to an account without a justified migration rule.
- Confirm the warning count exactly represents data that will be discarded, and that queue flush completion/errors are observable before sign-out proceeds.
- Check all local stores, including caches, workout/meal SwiftData containers, water/check-in outbox, UserDefaults, widget snapshots, notifications, HealthKit sync state, and Live Activities.
- Add tests for offline sign-out, partial flush, account switch, and replay after reconnect.

Also define account recovery, data export, account deletion (including Storage objects), and retention before inviting other users.

## P0 — honor the progress-photo release boundary

The product owner has set a firm V1 condition: photos must stay on the device or the photo feature must be absent. Current code uploads photos to Supabase Storage, so this is not satisfied yet.

- For a local-only choice, remove the Supabase upload/read path for photos, save inside the app sandbox with a strong data-protection level, exclude files from backups if "on device only" is literal, clear them on account switch/delete, and verify no secondary upload path exists.
- For no photos, disable/remove the UI and code path and plan deletion of existing Storage objects/metadata, including applicable backups/retention.
- Do not treat CloudKit as device-only. It may be considered later only if the owner changes the boundary to allow cloud storage. If considered, use each user's **private** CloudKit database (never public), account-bind records, use `CKAsset`, and explain iCloud requirements, storage quota, and recovery/key-reset behavior.
- Keep progress-photo handling out of V1 until one of the two allowed options is implemented and verified.

## P1 — correctness and resilience

- Replace user/data-dependent force unwraps and fatal startup/storage failures with safe behavior and actionable errors.
- Validate numeric bounds on both client and server; review migration 0070's limits against UI-supported values and old records.
- Verify weight/meal history uses stable date semantics and logged nutrition does not silently change when a catalog food is edited.
- Verify HealthKit permission denial leaves manual flows usable. Communicate imported vs. entered vs. estimated values.
- Review route privacy (location can reveal home/work), signed photo URLs, upload type/size limits, and orphan/deletion cleanup.
- Test offline queue replay after partial success, duplicate operations, retries, cancellation, corrupt persistence, and restored sessions.

## P1 — make missing nutrition days visible and stop overstating weekly estimates

The user's screenshots show three unlogged days, while Weekly Insights says "4 of 4 tracked this week" and reports a 1,714 kcal/day weekly average and a confident deficit/weight-loss pace. Current behavior explains the mismatch:

- `AdherenceScoreEngine.weeklyScore` averages calories/protein/steps over days with data and excludes missing days. This is appropriate for avoiding fabricated zeros, but a low-coverage week can still receive a normal-looking score.
- `WeeklyAdherenceScore.scoredCount/totalCount` counts the four component types (calories, protein, steps, training), not the number of days. The current label can be mistaken for day coverage.
- `WeeklyInsightsViewModel` averages `nutritionLogs` rows that exist; the week label does not disclose how many calendar days those rows cover. Its maintenance copy says "this week" and "on pace" without qualifying sparse logging.
- `AdaptiveTDEEEngine` averages only nutrition rows that exist and currently allows an estimate with 8 logged days in a 21-day window. It combines that intake average with weight-trend change spanning the date window, even if many dates have no intake record. Missing high-intake days can therefore bias the estimated TDEE and later advice.

### Proposed fix

1. **Never manufacture calorie values for absent days.** Keep missing as unknown. Offer a low-friction retrospective action to add an approximate entry or mark the day explicitly as "untracked/off-plan"; an explicit mark communicates coverage, but is not a numeric calorie value.
2. **Show coverage next to every aggregate.** For the selected week, display nutrition days logged out of elapsed days (and each metric's own coverage where applicable). Change "4 of 4 tracked this week" to an explicit metric label or, preferably, a day-coverage statement. Do not imply all four categories were tracked on all seven days.
3. **Qualify or suppress weak estimates.** For sparse current-week coverage, replace "on pace" with a clear message such as "Based on 4/7 logged days; missing days may change this estimate." For the TDEE engine, require adequate and reasonably distributed intake coverage before creating/updating an estimate; expose `loggedDaysInWindow/windowDays` and use a confidence/coverage state. Set the threshold deliberately and test gaps clustered into one week as well as evenly distributed gaps.
4. **Keep score semantics honest.** Continue treating an unmarked day as unknown rather than a zero, but show how many days/components actually contributed. If coverage is below the product's minimum for a meaningful weekly score, label it "not enough data" rather than showing a standalone score. Make explicit off-plan status visible separately from numeric intake.
5. **Check the existing insight lifecycle.** The Maintenance Calories card uses a previously saved TDEE estimate and this week's logged-day average; ensure stale estimates cannot be presented as current truth when recent logging coverage is poor.

Do not infer precise calories from a scale spike: alcohol, sodium, glycogen, hydration, and gut contents can move short-term body weight. Weight trend can add context, but cannot reconstruct intake or establish that a gap was overeating.

## P2 — reduce code size and duplication safely

Do a measured inventory before deleting or merging types. The app's many model/repository/service files mostly map to distinct database entities and lifecycles; lower file/model count is not itself the goal.

1. Use compiler/reference analysis to identify dead code and duplicate query/encoding/date-validation patterns.
2. Split oversized views by user journey; keep UI composition thin and business calculations in small pure functions.
3. Centralize repeated mechanics only where behavior is truly shared (date handling, validation, pagination, error mapping, ownership checks). Keep feature rules explicit in domain code.
4. Add focused tests before moving calculations or repositories. Preserve schema/migration history and avoid generic abstractions that hide table ownership or sync behavior.
5. Record before/after file-size/duplication evidence and remove only proven unused code.

## P2 — product backlog distilled from archived briefs

These items are proposals, not verified defects. Check current code first; several have since been implemented or revised.

- **Trust in insights:** show adherence-data completeness, handle partial weeks clearly, provide multi-week trends/comparisons, expose weekly self-report context, and surface weight trend/phase progress. Decide weighting only with the product owner.
- **Weekly review/photos:** consider a unified check-in reveal/history and dated photo timeline/comparison if the current flow still lacks them.
- **Training polish:** verify the old warmup-placeholder bug, workout resume/order persistence, weight precision in display, and history navigation. The current tree appears to contain fixes for several; regression-test before reopening.
- **Nutrition:** verify quantity editing, food-source provenance, label scanning and saved-meal workflows. MyFitnessPal automated diary import was abandoned. Macro-fit/menu suggestions should use deterministic scoring/optimization, not LLM arithmetic.
- **HealthKit/TDEE:** validate current estimates before changing formulas. Longer recency windows, Watch-energy cross-checks, RHR/HRV/temperature, importing/writing workouts, and a watchOS app are future work with added privacy and support costs.
- **Running/PT plans:** current models and views already cover running plans, gyms, schedules, goal phases, and training programs; revalidate briefs before adding duplicate systems.
- **Retire superseded asks:** do not run the orphan-data deletion proposal. The later decision is to keep that data and hide unassigned historical weeks from the picker. MyFitnessPal import is also explicitly abandoned.

## V2 LLM implementation boundary

Begin after V1 gates are closed. First deliver an opt-in, read-only weekly reflection via an authenticated server-side endpoint. Give the model minimal date-bounded aggregates and provenance; deterministic code performs all math. No automatic writes. Later, if valuable, add a small allowlist of read/proposal tools and require explicit confirmation for each mutation. Include rate/cost limits, structured output, prompt-injection evaluation, privacy disclosures, source citations, uncertainty, deletion behavior, and a kill switch.

## Definition of done

- Each P0/P1 change has a regression test or explicit manual verification evidence.
- Database changes are migration-based and pass fresh-install plus upgrade checks.
- Cross-account tests prove no row, object, local cache, or queued write crosses owners.
- Release build/device smoke test passes; all deliberate deferrals are recorded.
- V1 can be tagged and rolled back; only then begin the V2 LLM prototype.
