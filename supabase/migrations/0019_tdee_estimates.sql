-- Weekly-computed adaptive TDEE estimate + calorie recommendation, derived
-- from the trend body-weight change vs logged nutrition intake over a
-- trailing window (see AdaptiveTDEEEngine). One row per estimate (not per
-- day), so the history itself is the TDEE trend line - no separate
-- aggregation table needed later for a TDEE-over-time chart.
create table tdee_estimates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  estimated_at date not null default current_date,
  window_days int not null,
  logged_days_in_window int not null,
  avg_daily_calories numeric(7, 1) not null,
  trend_weight_change_kg_per_week numeric(5, 3) not null,
  estimated_tdee numeric(7, 1) not null,
  current_calorie_target numeric(7, 1) not null,
  recommended_calorie_target numeric(7, 1) not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'dismissed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, estimated_at)
);

create index tdee_estimates_user_estimated_at_idx on tdee_estimates (user_id, estimated_at desc);

create trigger tdee_estimates_set_updated_at
  before update on tdee_estimates
  for each row execute function set_updated_at();

alter table tdee_estimates enable row level security;

create policy "tdee_estimates_owner_all"
  on tdee_estimates for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
