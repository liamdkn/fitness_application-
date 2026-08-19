-- Manual before/after watch step counts around a cardio session (e.g.
-- treadmill), so machine-counted steps can be excluded from the day's real
-- walking step total. Multiple sessions per day are allowed and summed.
create table cardio_step_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  date date not null,
  steps_before int not null check (steps_before >= 0),
  steps_after int not null check (steps_after >= steps_before),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index cardio_step_sessions_user_date_idx on cardio_step_sessions (user_id, date);

create trigger cardio_step_sessions_set_updated_at
  before update on cardio_step_sessions
  for each row execute function set_updated_at();

alter table cardio_step_sessions enable row level security;

create policy "cardio_step_sessions_owner_all"
  on cardio_step_sessions for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table user_preferences
  add column cardio_step_exclusion_enabled boolean not null default false;
