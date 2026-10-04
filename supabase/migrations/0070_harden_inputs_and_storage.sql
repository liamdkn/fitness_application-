-- Hardening from the security review (docs/SECURITY_AND_RELEASE_READINESS.md).
--
-- 1. Shared catalogue inserts were open to the `public` role, i.e. anyone
--    holding the app's public anon key could add shared foods without signing
--    in. They now need a signed-in user.
-- 2. Numeric inputs had no upper bounds, so a client (or a typo) could store
--    absurd values. Bounds are added as NOT VALID: they apply to every new
--    insert and update but don't re-check, or block, rows that already exist.
-- 3. The progress-photos bucket had no size limit and accepted any file type.

-- 1 ---------------------------------------------------------------------
drop policy if exists foods_insert_off_lookup on foods;
create policy foods_insert_off_lookup on foods
  for insert to authenticated
  with check (is_custom = false and source = 'off');

drop policy if exists foods_insert_own_custom on foods;
create policy foods_insert_own_custom on foods
  for insert to authenticated
  with check (is_custom = true and created_by = auth.uid());

-- 2 ---------------------------------------------------------------------
alter table foods
  add constraint foods_calories_max check (calories <= 5000) not valid,
  add constraint foods_protein_max check (protein_g <= 1000) not valid,
  add constraint foods_carbs_max check (carbs_g <= 1000) not valid,
  add constraint foods_fat_max check (fat_g <= 1000) not valid,
  add constraint foods_fiber_max check (fiber_g <= 1000) not valid,
  add constraint foods_sodium_max check (sodium_mg <= 100000) not valid,
  add constraint foods_caffeine_max check (caffeine_mg <= 5000) not valid,
  add constraint foods_serving_size_max check (serving_size <= 10000) not valid,
  add constraint foods_name_length check (char_length(name) between 1 and 200) not valid,
  add constraint foods_brand_length check (char_length(brand) <= 100) not valid,
  add constraint foods_barcode_length check (char_length(barcode) <= 32) not valid;

alter table recipes
  add constraint recipes_calories_range check (calories between 0 and 10000) not valid,
  add constraint recipes_macros_range check (
    protein_g between 0 and 2000 and carbs_g between 0 and 2000
    and fat_g between 0 and 2000 and fiber_g between 0 and 2000) not valid;

alter table saved_days
  add constraint saved_days_calories_range check (calories between 0 and 20000) not valid,
  add constraint saved_days_macros_range check (
    protein_g between 0 and 4000 and carbs_g between 0 and 4000
    and fat_g between 0 and 4000 and fiber_g between 0 and 4000) not valid;

alter table planned_treats
  add constraint planned_treats_extras_range check (
    extra_protein_g between 0 and 1000 and extra_carbs_g between 0 and 2000
    and extra_fat_g between 0 and 1000) not valid;

alter table user_goals
  add constraint user_goals_calories_range check (daily_calorie_target between 500 and 10000) not valid,
  add constraint user_goals_macros_range check (
    protein_g_target between 0 and 1000 and carbs_g_target between 0 and 2000
    and fat_g_target between 0 and 1000 and fiber_g_target between 0 and 300) not valid,
  add constraint user_goals_steps_range check (step_target between 0 and 100000) not valid,
  add constraint user_goals_sleep_range check (sleep_target_minutes between 0 and 1440) not valid,
  add constraint user_goals_weight_range check (
    starting_weight_kg between 20 and 400 and target_weight_kg between 20 and 400) not valid,
  add constraint user_goals_sessions_range check (
    cardio_sessions_per_week between 0 and 21 and strength_sessions_per_week between 0 and 21
    and cardio_minutes_per_session between 0 and 600) not valid,
  add constraint user_goals_duration_range check (duration_weeks between 1 and 156) not valid;

alter table planned_runs
  add constraint planned_runs_targets_range check (
    target_distance_km between 0 and 500 and target_duration_min between 0 and 2000) not valid;

alter table workouts
  add constraint workouts_active_calories_range check (active_calories between 0 and 20000) not valid;

alter table cardio_tracking_sessions
  add constraint cardio_distance_range check (distance_meters between 0 and 500000) not valid,
  add constraint cardio_calories_range check (
    active_calories between 0 and 20000 and total_calories between 0 and 30000) not valid,
  add constraint cardio_elevation_range check (elevation_gain_m between 0 and 20000) not valid;

-- 3 ---------------------------------------------------------------------
update storage.buckets
set file_size_limit = 10485760,                      -- 10 MB
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
where id = 'progress-photos';
