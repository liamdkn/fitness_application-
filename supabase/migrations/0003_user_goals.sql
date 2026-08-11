create table user_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  effective_from date not null default current_date,
  daily_calorie_target numeric(7, 1) not null,
  protein_g_target numeric(6, 1) not null,
  carbs_g_target numeric(6, 1),
  fat_g_target numeric(6, 1),
  target_weight_kg numeric(6, 2),
  weekly_weight_change_kg numeric(4, 2),
  step_target int,
  sleep_target_minutes int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, effective_from)
);

create index user_goals_user_effective_from_idx on user_goals (user_id, effective_from desc);

create trigger user_goals_set_updated_at
  before update on user_goals
  for each row execute function set_updated_at();

alter table user_goals enable row level security;

create policy "user_goals_owner_all"
  on user_goals for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Current goal in effect as of a given date (defaults to today).
create or replace function current_user_goal(as_of date default current_date)
returns user_goals as $$
  select *
  from user_goals
  where user_id = auth.uid()
    and effective_from <= as_of
  order by effective_from desc
  limit 1;
$$ language sql stable security invoker;
