-- weekly_checkin_weekday uses Foundation's Calendar.weekday numbering:
-- 1=Sunday...7=Saturday, so Monday=2 (the default).
create table user_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id),
  weekly_checkin_weekday int not null default 2 check (weekly_checkin_weekday between 1 and 7),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger user_preferences_set_updated_at
  before update on user_preferences
  for each row execute function set_updated_at();

alter table user_preferences enable row level security;

create policy "user_preferences_owner_all"
  on user_preferences for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
