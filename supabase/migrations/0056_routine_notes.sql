-- Durable "read this before training" text on a routine - injury
-- constraints, pain rules, stop rules, retest reminders. Mirrors
-- workouts.notes (per logged session) but lives on the routine, so it's
-- there every time the split is opened rather than per workout. Plain
-- text the user reads; nothing in the app evaluates or acts on it.
alter table routines add column notes text;
