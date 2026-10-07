-- A warm-up or cool-down can be set by distance instead of time. When
-- warmup_km / cooldown_km is set it is used and the minutes are ignored;
-- 0 means none, like the minutes columns.
alter table planned_runs
  add column if not exists warmup_km numeric(4, 1) check (warmup_km is null or warmup_km between 0 and 20),
  add column if not exists cooldown_km numeric(4, 1) check (cooldown_km is null or cooldown_km between 0 and 20);
