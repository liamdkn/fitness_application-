-- Replaces the old "cycle through routine_days by completing a workout"
-- model with a fixed weekly calendar: each of the 7 weekdays is either a
-- specific workout day, an active-rest day (e.g. a run), or a full rest
-- day, editable from the split editor. Train's top-of-screen carousel
-- reads this directly instead of `next_routine_day` (see
-- StartWorkoutView.swift). weekday follows Swift's own
-- `Calendar.Component.weekday` convention (1 = Sunday ... 7 = Saturday) so
-- the client never needs to translate between two different numbering
-- schemes.
create table weekly_schedule (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  routine_id uuid not null references routines(id) on delete cascade,
  weekday int not null check (weekday between 1 and 7),
  day_type text not null default 'rest' check (day_type in ('workout', 'active_rest', 'rest')),
  routine_day_id uuid references routine_days(id) on delete set null,
  cardio_type text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (routine_id, weekday)
);

create trigger weekly_schedule_set_updated_at
  before update on weekly_schedule
  for each row execute function set_updated_at();

alter table weekly_schedule enable row level security;

create policy "weekly_schedule_owner_all"
  on weekly_schedule for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
