-- Tracks injuries by muscle group, using the same taxonomy as
-- exercises.primary_muscle_group so the app can warn when logging a set for
-- an exercise that targets an unresolved injury's area. resolved_at is null
-- while an injury is still active; setting it marks it as healed rather than
-- deleting the row, so past injuries stay visible in history.
create table injuries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  muscle_group text not null check (muscle_group in (
    'chest', 'back', 'shoulders', 'biceps', 'triceps', 'quads', 'hamstrings',
    'glutes', 'calves', 'abs', 'forearms', 'full_body', 'cardio', 'mobility'
  )),
  notes text,
  started_at date not null default current_date,
  resolved_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger injuries_set_updated_at
  before update on injuries
  for each row execute function set_updated_at();

alter table injuries enable row level security;

create policy "injuries_owner_all"
  on injuries for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
