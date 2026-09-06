-- Tracks when a "logical phase" actually began, independent of
-- effective_from. A mid-phase target adjustment (GoalsRepository.saveGoal,
-- used by the new "adjust nutrition targets from a date" flow and by
-- applyCalorieAdjustment) inserts a new row with a later effective_from
-- but the SAME phase_started_at as the phase it's adjusting, so
-- week-number/duration tracking survives the adjustment instead of
-- looking like the phase restarted. Starting a genuinely new phase
-- (StartNewPhaseView) sets both to the same date.
alter table user_goals add column phase_started_at date;
update user_goals set phase_started_at = effective_from where phase_started_at is null;
alter table user_goals alter column phase_started_at set not null;
alter table user_goals alter column phase_started_at set default current_date;
