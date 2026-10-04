-- A planned run can spell out its warm-up, its main part and its cool-down.
--
-- Paces are seconds per km. `main_pace_sec` is the target pace for a plain
-- run (without it the pace is worked out from distance and time, as before).
-- `blocks` is a list of repeated pieces for interval and tempo sessions, each
-- {reps, work: {distance_m | seconds, pace_sec}, recovery: {...}}; when
-- present it replaces the single main step. Warm-up and cool-down lengths of
-- null mean the old default of 10 minutes; 0 means none.

alter table planned_runs
  add column warmup_min int check (warmup_min is null or warmup_min between 0 and 60),
  add column warmup_pace_sec int check (warmup_pace_sec is null or warmup_pace_sec between 150 and 1200),
  add column cooldown_min int check (cooldown_min is null or cooldown_min between 0 and 60),
  add column cooldown_pace_sec int check (cooldown_pace_sec is null or cooldown_pace_sec between 150 and 1200),
  add column main_pace_sec int check (main_pace_sec is null or main_pace_sec between 150 and 1200),
  add column blocks jsonb check (blocks is null or (jsonb_typeof(blocks) = 'array' and jsonb_array_length(blocks) <= 20));
