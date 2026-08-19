-- A same-day grouping tag: exercises sharing a superset_group_id are
-- performed back-to-back as a superset. Nullable, no FK - purely a grouping
-- tag scoped within the exercise's own routine_day_id.
alter table routine_day_exercises add column superset_group_id uuid;
