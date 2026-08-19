-- Append-only measurement timeseries, same shape as body_weight_logs.
-- weekly_checkin_id is added later (0011) once that table exists, to keep
-- this migration self-contained.
create table body_measurements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  measured_at date not null,
  waist_cm numeric(5, 1) check (waist_cm > 0),
  left_bicep_cm numeric(4, 1) check (left_bicep_cm > 0),
  right_bicep_cm numeric(4, 1) check (right_bicep_cm > 0),
  goal_id uuid references user_goals(id) on delete set null,
  source text not null default 'manual' check (source in ('phase_start', 'weekly_checkin', 'manual')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index body_measurements_user_measured_at_idx on body_measurements (user_id, measured_at desc);

create trigger body_measurements_set_updated_at
  before update on body_measurements
  for each row execute function set_updated_at();

alter table body_measurements enable row level security;

create policy "body_measurements_owner_all"
  on body_measurements for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
