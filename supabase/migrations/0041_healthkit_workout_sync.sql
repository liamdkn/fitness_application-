-- Supports importing/enriching workouts detected from Apple Watch (an
-- Indoor Walk or Stairmaster session recorded via the Watch's own Workout
-- app, or a Functional Strength Training session that overlaps a workout
-- already logged in-app). Every write here is user-confirmed - the app
-- surfaces detected Watch workouts and only imports/enriches on an
-- explicit tap, never silently in the background sync - so this is purely
-- storage for that confirmed result, not sync-state machinery.

alter table cardio_tracking_sessions
  add column active_calories numeric(7, 1),
  add column source text not null default 'app' check (source in ('app', 'healthkit')),
  add column healthkit_uuid text;

-- One Watch workout should only ever become one cardio session, even if
-- sync logic runs twice.
create unique index cardio_tracking_sessions_healthkit_uuid_idx
  on cardio_tracking_sessions (user_id, healthkit_uuid)
  where healthkit_uuid is not null;

alter table workouts
  add column avg_heart_rate int check (avg_heart_rate is null or avg_heart_rate > 0),
  add column active_calories numeric(7, 1),
  add column healthkit_workout_uuid text;

create unique index workouts_healthkit_uuid_idx
  on workouts (user_id, healthkit_workout_uuid)
  where healthkit_workout_uuid is not null;

-- A Watch workout the user explicitly declined to import/enrich - without
-- this, the same candidate would keep reappearing on every future review
-- since nothing else marks it as "seen."
create table dismissed_healthkit_workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  healthkit_uuid text not null,
  created_at timestamptz not null default now(),
  unique (user_id, healthkit_uuid)
);

alter table dismissed_healthkit_workouts enable row level security;

create policy "dismissed_healthkit_workouts_owner_all"
  on dismissed_healthkit_workouts for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
