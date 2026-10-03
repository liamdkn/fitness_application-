-- Richer data for Watch-imported runs: the extra numbers Apple records
-- (elevation gain, running power, cadence, total calories) as plain columns,
-- and the GPS route in its own table. The route is ~hundreds of points, so
-- it stays out of cardio_tracking_sessions - history lists select * from
-- that table and shouldn't haul a route per row; `has_route` lets a list
-- show a map affordance without fetching one.
alter table cardio_tracking_sessions
  add column elevation_gain_m numeric(7, 1),
  add column avg_power_w int,
  add column avg_cadence_spm int,
  add column total_calories numeric(7, 1),
  add column has_route boolean not null default false;

-- points: [[lat, lon, seconds_from_start], ...], already thinned to a few
-- hundred - enough to draw the route and work out km splits, not a raw GPS dump.
create table run_routes (
  session_id uuid primary key references cardio_tracking_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  points jsonb not null,
  created_at timestamptz not null default now()
);

alter table run_routes enable row level security;

create policy "run_routes_owner_all"
  on run_routes for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
