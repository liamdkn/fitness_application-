-- A user's split (e.g. "Push/Pull/Legs"). Only one active routine at a time;
-- "active" is what drives the rotating "what's my next workout" logic.
create table routines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index routines_one_active_per_user
  on routines (user_id)
  where is_active;

create trigger routines_set_updated_at
  before update on routines
  for each row execute function set_updated_at();

alter table routines enable row level security;

create policy "routines_owner_all"
  on routines for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- One slot in the rotation (e.g. position 1 = "Push"). Rotation wraps by
-- count(*) of days in the routine, independent of calendar day.
create table routine_days (
  id uuid primary key default gen_random_uuid(),
  routine_id uuid not null references routines(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  position int not null,
  label text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (routine_id, position)
);

create trigger routine_days_set_updated_at
  before update on routine_days
  for each row execute function set_updated_at();

alter table routine_days enable row level security;

create policy "routine_days_owner_all"
  on routine_days for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- The exercise template for a routine day, plus the double-progression
-- target used to suggest the next weight/reps (top of rep range for all
-- sets -> suggest weight_increment more next time; otherwise same weight,
-- aim for more reps).
create table routine_day_exercises (
  id uuid primary key default gen_random_uuid(),
  routine_day_id uuid not null references routine_days(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  exercise_id uuid not null references exercises(id),
  position int not null,
  target_sets int not null check (target_sets > 0),
  rep_range_low int not null check (rep_range_low > 0),
  rep_range_high int not null check (rep_range_high >= rep_range_low),
  weight_increment_kg numeric(5, 2) not null default 2.5,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (routine_day_id, position)
);

create trigger routine_day_exercises_set_updated_at
  before update on routine_day_exercises
  for each row execute function set_updated_at();

alter table routine_day_exercises enable row level security;

create policy "routine_day_exercises_owner_all"
  on routine_day_exercises for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- A workout instance is optionally tied to the routine day it was following,
-- plus duration tracking (started_at is set when the workout begins,
-- ended_at when it's finished).
alter table workouts
  add column routine_day_id uuid references routine_days(id),
  add column started_at timestamptz not null default now(),
  add column ended_at timestamptz;

-- Which routine day comes next in the rotation for a given routine, based on
-- the most recent finished workout that followed this routine (wraps around
-- the day count, independent of calendar day). Defaults to position 1 when
-- there's no workout history yet for this routine.
create or replace function next_routine_day(for_routine_id uuid)
returns routine_days as $$
  select rd.*
  from routine_days rd
  where rd.routine_id = for_routine_id
    and rd.position = coalesce(
      (
        select (last_day.position % (select count(*) from routine_days where routine_id = for_routine_id)) + 1
        from workouts w
        join routine_days last_day on last_day.id = w.routine_day_id
        where last_day.routine_id = for_routine_id
          and w.user_id = auth.uid()
          and w.ended_at is not null
        order by w.performed_at desc
        limit 1
      ),
      1
    );
$$ language sql stable security invoker;

-- The working sets (excludes warmups) from the most recent workout that
-- included this exercise, used both to display "last time" and to compute
-- the double-progression suggestion for next time.
create or replace function previous_exercise_sets(for_exercise_id uuid)
returns setof workout_sets as $$
  select ws.*
  from workout_sets ws
  where ws.exercise_id = for_exercise_id
    and ws.user_id = auth.uid()
    and ws.is_warmup = false
    and ws.workout_id = (
      select w.id
      from workouts w
      join workout_sets ws2 on ws2.workout_id = w.id
      where w.user_id = auth.uid()
        and ws2.exercise_id = for_exercise_id
      order by w.performed_at desc
      limit 1
    )
  order by ws.set_index;
$$ language sql stable security invoker;
