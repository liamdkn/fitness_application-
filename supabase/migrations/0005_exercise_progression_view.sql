-- Per-workout aggregates per exercise (est. 1RM via Epley formula, total
-- volume, max weight), used to drive progression charts. security_invoker
-- is required here so the view is subject to the querying user's RLS on
-- workout_sets/workouts, rather than running as the view owner and leaking
-- every user's data.
create view v_exercise_progression
with (security_invoker = true)
as
select
  ws.user_id,
  ws.exercise_id,
  w.id as workout_id,
  w.performed_at,
  max(ws.weight_kg * (1 + ws.reps / 30.0)) as best_est_1rm,
  max(ws.weight_kg) as max_weight_kg,
  sum(ws.reps * ws.weight_kg) as total_volume_kg,
  sum(ws.reps) as total_reps
from workout_sets ws
join workouts w on w.id = ws.workout_id
where ws.is_warmup = false
group by ws.user_id, ws.exercise_id, w.id, w.performed_at;
