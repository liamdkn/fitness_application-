-- Weekly training volume per muscle group, used to flag muscle groups
-- trending below their own recent average (a lightweight stand-in for
-- hand-configured MEV/MAV/MRV landmarks). Mirrors v_exercise_progression's
-- shape and security_invoker usage (0005_exercise_progression_view.sql).
create view v_muscle_group_weekly_volume
with (security_invoker = true)
as
select
  ws.user_id,
  date_trunc('week', w.performed_at)::date as week_start,
  coalesce(e.primary_muscle_group, 'unknown') as muscle_group,
  sum(ws.reps * ws.weight_kg) as total_volume_kg,
  sum(ws.reps) as total_reps,
  count(distinct ws.id) as set_count
from workout_sets ws
join workouts w on w.id = ws.workout_id
join exercises e on e.id = ws.exercise_id
where ws.is_warmup = false
group by ws.user_id, date_trunc('week', w.performed_at), coalesce(e.primary_muscle_group, 'unknown');
