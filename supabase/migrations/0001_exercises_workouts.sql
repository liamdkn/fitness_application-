create extension if not exists pgcrypto;

create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- Exercise catalog: shared reference rows (is_custom = false) plus
-- per-user custom exercises (is_custom = true, created_by = owner).
create table exercises (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null check (category in ('compound', 'isolation', 'cardio', 'mobility')),
  primary_muscle_group text,
  equipment text,
  is_custom boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger exercises_set_updated_at
  before update on exercises
  for each row execute function set_updated_at();

alter table exercises enable row level security;

create policy "exercises_select_catalog_or_own"
  on exercises for select
  using (is_custom = false or created_by = auth.uid());

create policy "exercises_insert_own_custom"
  on exercises for insert
  with check (is_custom = true and created_by = auth.uid());

create policy "exercises_update_own_custom"
  on exercises for update
  using (is_custom = true and created_by = auth.uid());

create policy "exercises_delete_own_custom"
  on exercises for delete
  using (is_custom = true and created_by = auth.uid());

create table workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  performed_at timestamptz not null default now(),
  name text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index workouts_user_performed_at_idx on workouts (user_id, performed_at desc);

create trigger workouts_set_updated_at
  before update on workouts
  for each row execute function set_updated_at();

alter table workouts enable row level security;

create policy "workouts_owner_all"
  on workouts for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table workout_sets (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid not null references workouts(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  exercise_id uuid not null references exercises(id),
  set_index int not null,
  reps int not null check (reps >= 0),
  weight_kg numeric(6, 2) not null check (weight_kg >= 0),
  rpe numeric(3, 1) check (rpe between 0 and 10),
  is_warmup boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index workout_sets_workout_id_idx on workout_sets (workout_id);
create index workout_sets_user_exercise_idx on workout_sets (user_id, exercise_id, created_at);

create trigger workout_sets_set_updated_at
  before update on workout_sets
  for each row execute function set_updated_at();

alter table workout_sets enable row level security;

create policy "workout_sets_owner_all"
  on workout_sets for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
