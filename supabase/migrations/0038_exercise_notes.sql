-- Per-exercise notes, tied to a specific workout instance (e.g. "shoulder
-- very sore on this one") - distinct from `workouts.notes` (whole-workout).
-- One note per (workout, exercise), reachable from the exercise's "..."
-- menu during an active workout and shown alongside that exercise's set
-- history afterward.
create table exercise_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  workout_id uuid not null references workouts(id) on delete cascade,
  exercise_id uuid not null references exercises(id),
  note text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workout_id, exercise_id)
);

create index exercise_notes_user_exercise_idx on exercise_notes (user_id, exercise_id, created_at desc);

create trigger exercise_notes_set_updated_at
  before update on exercise_notes
  for each row execute function set_updated_at();

alter table exercise_notes enable row level security;

create policy "exercise_notes_owner_all"
  on exercise_notes for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
