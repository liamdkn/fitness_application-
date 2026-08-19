-- Cardio target as part of a phase (sessions/week, minutes/session).
alter table user_goals add column cardio_sessions_per_week int;
alter table user_goals add column cardio_minutes_per_session int;

-- Live-tracked cardio sessions: start (type + steps), running (pause/
-- resume), end (steps + avg HR). Pause state is modeled as nullable
-- timestamps + one accumulator, mirroring workouts.ended_at's existing
-- "null = still running" convention.
create table cardio_tracking_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  cardio_type text not null check (cardio_type in (
    'treadmill', 'outdoor_run', 'outdoor_walk', 'bike', 'elliptical',
    'rowing', 'swimming', 'other'
  )),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  paused_at timestamptz,
  paused_seconds int not null default 0 check (paused_seconds >= 0),
  steps_before int,
  steps_after int,
  avg_heart_rate int check (avg_heart_rate is null or avg_heart_rate > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ended_at is null or paused_at is null),
  check (steps_after is null or steps_before is null or steps_after >= steps_before)
);

create index cardio_tracking_sessions_user_started_idx
  on cardio_tracking_sessions (user_id, started_at desc);

-- At most one in-progress session per user, mirroring the exact existing
-- pattern for "one active routine per user" (0004_routines_and_progression.sql).
create unique index cardio_tracking_sessions_one_active_per_user
  on cardio_tracking_sessions (user_id) where ended_at is null;

create trigger cardio_tracking_sessions_set_updated_at
  before update on cardio_tracking_sessions
  for each row execute function set_updated_at();

alter table cardio_tracking_sessions enable row level security;

create policy "cardio_tracking_sessions_owner_all"
  on cardio_tracking_sessions for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
