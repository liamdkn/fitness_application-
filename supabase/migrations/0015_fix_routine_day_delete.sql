-- workouts.routine_day_id had no ON DELETE clause, defaulting to RESTRICT.
-- Deleting a routine day that had ever been logged against silently failed
-- the delete (swallowed client-side by try?), making the day reappear on
-- next reload. Fix to ON DELETE SET NULL, matching daily_checkins'
-- routine_day_id precedent (0010_daily_checkins.sql) - the workout history
-- itself is preserved, only its link to the now-deleted day is cleared.
-- WorkoutHistoryView already handles a nil routineDayId by falling back to
-- workout.name ?? "Workout".
alter table workouts drop constraint workouts_routine_day_id_fkey;
alter table workouts add constraint workouts_routine_day_id_fkey
  foreign key (routine_day_id) references routine_days(id) on delete set null;
