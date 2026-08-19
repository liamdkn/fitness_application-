-- week_number is computed in Swift and stored at submit time (not derived
-- on read), since goal_id is on delete set null and could later be
-- orphaned, which would corrupt a purely-derived value.
create table weekly_checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  goal_id uuid references user_goals(id) on delete set null,
  checkin_date date not null,
  week_number int,
  overall_rating_7d int check (overall_rating_7d between 1 and 5),
  weight_kg numeric(6, 2) check (weight_kg > 0),
  energy_level int check (energy_level between 1 and 5),
  soreness_level int check (soreness_level between 1 and 5),
  stress_level int check (stress_level between 1 and 5),
  stress_reason text,
  biggest_win text,
  mood_notes text,
  overall_adherence int check (overall_adherence between 1 and 5),
  training_adherence int check (training_adherence between 1 and 5),
  nutrition_adherence int check (nutrition_adherence between 1 and 5),
  discipline_level int check (discipline_level between 1 and 5),
  upcoming_distractions text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, checkin_date)
);

create trigger weekly_checkins_set_updated_at
  before update on weekly_checkins
  for each row execute function set_updated_at();

alter table weekly_checkins enable row level security;

create policy "weekly_checkins_owner_all"
  on weekly_checkins for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Retrofit now that weekly_checkins exists (kept out of 0007/0008 so those
-- migrations were self-contained at the time).
alter table body_measurements add column weekly_checkin_id uuid references weekly_checkins(id) on delete set null;
alter table progress_photos add column weekly_checkin_id uuid references weekly_checkins(id) on delete set null;
