-- Turn user_goals into a full phase (cut/maintain/bulk). effective_from is
-- already the phase start date - no separate start_date column needed.
alter table user_goals add column phase_type text;
update user_goals set phase_type = 'maintain' where phase_type is null;
alter table user_goals alter column phase_type set not null;
alter table user_goals add constraint user_goals_phase_type_check
  check (phase_type in ('cut', 'maintain', 'bulk'));

alter table user_goals add column starting_weight_kg numeric(6, 2);
alter table user_goals add column duration_weeks int not null default 12;

-- Enforce the weekly-change sign matches the phase type (cut <= 0,
-- maintain = 0, bulk >= 0), so a mismatched goal can't be saved silently.
alter table user_goals add constraint user_goals_weekly_change_sign_check
  check (
    weekly_weight_change_kg is null
    or (phase_type = 'cut' and weekly_weight_change_kg <= 0)
    or (phase_type = 'maintain' and weekly_weight_change_kg = 0)
    or (phase_type = 'bulk' and weekly_weight_change_kg >= 0)
  );
