-- One row per calendar day. checkin_date is always sent explicitly from
-- Swift (never relies on a DB-side default) since the database's timezone
-- isn't the device's. The yesterday_* fields are about the PREVIOUS day but
-- live on today's row - the column names carry that meaning, not the date
-- bucket, keeping one row per day like every other date-keyed table here.
create table daily_checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  checkin_date date not null,
  weight_kg numeric(6, 2) check (weight_kg > 0),
  routine_day_id uuid references routine_days(id) on delete set null,
  workout_choice_label text,
  is_rest_day boolean not null default false,
  energy_level int check (energy_level between 1 and 5),
  soreness_level int check (soreness_level between 1 and 5),
  yesterday_water_ml int check (yesterday_water_ml >= 0),
  yesterday_off_plan boolean,
  yesterday_off_plan_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, checkin_date)
);

create trigger daily_checkins_set_updated_at
  before update on daily_checkins
  for each row execute function set_updated_at();

alter table daily_checkins enable row level security;

create policy "daily_checkins_owner_all"
  on daily_checkins for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
