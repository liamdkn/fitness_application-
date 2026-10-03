-- Two caffeine settings:
--   bedtime_from_health: work out bedtime from when you actually fall asleep
--     (Apple Health sleep data) instead of the fixed bedtime_minutes. The
--     fixed time stays as the fallback when there isn't enough sleep data.
--   caffeine_reminders_enabled: the "last call for caffeine" and "wind down"
--     notifications.
alter table user_preferences
  add column bedtime_from_health boolean not null default true,
  add column caffeine_reminders_enabled boolean not null default true;
