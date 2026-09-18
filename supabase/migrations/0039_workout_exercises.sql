-- Persists which exercises belong to a specific workout instance and their
-- display order. Previously this was re-derived from the routine day
-- template every time the workout view (re)opened, which meant removing an
-- exercise mid-session (only its sets were deleted) silently reappeared the
-- next time the workout was resumed, since nothing recorded the removal -
-- this table is also the natural place to persist a mid-workout reorder.
create table workout_exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  workout_id uuid not null references workouts(id) on delete cascade,
  exercise_id uuid not null references exercises(id),
  position int not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workout_id, exercise_id)
);

create index workout_exercises_workout_id_idx on workout_exercises (workout_id, position);

create trigger workout_exercises_set_updated_at
  before update on workout_exercises
  for each row execute function set_updated_at();

alter table workout_exercises enable row level security;

create policy "workout_exercises_owner_all"
  on workout_exercises for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
