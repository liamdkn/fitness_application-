-- Adds Stairmaster as a cardio type. Same drop/re-add pattern as
-- 0015_fix_routine_day_delete.sql for changing an existing constraint.
alter table cardio_tracking_sessions
  drop constraint cardio_tracking_sessions_cardio_type_check;
alter table cardio_tracking_sessions
  add constraint cardio_tracking_sessions_cardio_type_check
  check (cardio_type in (
    'treadmill', 'outdoor_run', 'outdoor_walk', 'stairmaster', 'bike',
    'elliptical', 'rowing', 'swimming', 'other'
  ));
