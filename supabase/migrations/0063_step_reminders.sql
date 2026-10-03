-- Step-goal notifications: a nudge when today's steps are short of the
-- target. step_reminder_minutes is the evening "last push" time, minutes
-- after midnight (1110 = 18:30); an earlier afternoon check at 14:00 only
-- fires when the day is running behind pace.
alter table user_preferences
  add column step_reminders_enabled boolean not null default true,
  add column step_reminder_minutes int not null default 1110
    check (step_reminder_minutes between 0 and 1439);
