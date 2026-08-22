-- Strength-training targets as part of a phase, mirroring the existing
-- cardio sessions/week target - lets the (upcoming) weekly adherence score
-- judge training against a real weekly cadence instead of a hardcoded
-- number. strength_optional_sessions is how many of those weekly sessions
-- are "bonus": missing one doesn't count against adherence.
alter table user_goals add column strength_sessions_per_week int;
alter table user_goals add column strength_optional_sessions int;

-- A split day that's a bonus/optional session (e.g. an optional "Day 5")
-- rather than a required one - missing it isn't scored as a miss either.
alter table routine_days add column is_optional boolean not null default false;
