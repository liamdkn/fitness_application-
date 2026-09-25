-- Water intake logging. `water_containers` is a per-user list of the
-- vessels someone actually drinks from (a hydroflask, a pint glass, ...),
-- each with its own volume - not everyone's "pint" is a real 568ml pint,
-- hence this being user-editable rather than a fixed catalog. `water_logs`
-- is the individual entries: either "add 1x this container" (container_id
-- set, amount_ml copied from it at log time so a later edit to the
-- container's volume doesn't retroactively change historical totals) or a
-- one-off custom amount (container_id null).
create table water_containers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  volume_ml int not null check (volume_ml > 0),
  created_at timestamptz not null default now(),
  unique (user_id, name)
);

alter table water_containers enable row level security;

create policy "water_containers_owner_all"
  on water_containers for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table water_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  date date not null,
  amount_ml int not null check (amount_ml > 0),
  container_id uuid references water_containers(id) on delete set null,
  logged_at timestamptz not null default now()
);

create index water_logs_user_date_idx on water_logs (user_id, date);

alter table water_logs enable row level security;

create policy "water_logs_owner_all"
  on water_logs for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- A single current target, not phase-scoped like `user_goals` (hydration
-- isn't tied to a cut/bulk the way calorie/macro targets are) - same
-- treatment as the other plain settings already on this table.
alter table user_preferences
  add column daily_water_ml_target int not null default 2500 check (daily_water_ml_target > 0);
