-- Running plans: a set of planned runs per day, compared against what the
-- Apple Watch actually recorded. Runs themselves still arrive through the
-- Watch import (cardio_tracking_sessions, cardio_type = 'outdoor_run') - the
-- only addition on that side is the distance, which nothing stored before.
alter table cardio_tracking_sessions add column distance_meters numeric(9, 1);

create table running_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  start_date date not null,
  -- Plans that begin partway through a longer programme (joined at week 4)
  -- still show the programme's own week numbers.
  first_week_number int not null default 1,
  target_race_date date,
  target_distance_km numeric(5, 1),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger running_plans_set_updated_at
  before update on running_plans
  for each row execute function set_updated_at();

create table planned_runs (
  id uuid primary key default gen_random_uuid(),
  running_plan_id uuid not null references running_plans(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  date date not null,
  run_type text not null check (run_type in ('easy', 'long', 'tempo', 'interval', 'race_pace', 'rest')),
  -- Either, both or neither: an easy midweek run is usually "35 minutes",
  -- a long run "9 km", an interval session a note ("6 x 1 km").
  target_distance_km numeric(5, 1),
  target_duration_min int,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index planned_runs_plan_date_idx on planned_runs (running_plan_id, date);

create trigger planned_runs_set_updated_at
  before update on planned_runs
  for each row execute function set_updated_at();

alter table running_plans enable row level security;
alter table planned_runs enable row level security;

create policy "running_plans_owner_all"
  on running_plans for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "planned_runs_owner_all"
  on planned_runs for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
