-- Adds Incline Treadmill (displayed as "Incline Walk") as a cardio type.
-- Same drop/re-add pattern as 0023_add_stairmaster.sql.
alter table cardio_tracking_sessions
  drop constraint cardio_tracking_sessions_cardio_type_check;
alter table cardio_tracking_sessions
  add constraint cardio_tracking_sessions_cardio_type_check
  check (cardio_type in (
    'treadmill', 'incline_treadmill', 'outdoor_run', 'outdoor_walk',
    'stairmaster', 'bike', 'elliptical', 'rowing', 'swimming', 'other'
  ));
