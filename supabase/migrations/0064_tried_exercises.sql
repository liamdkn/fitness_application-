-- Which exercises the signed-in user has logged at least one set for - lets
-- the Exercise Library list exercises with history first. security invoker
-- (the default) so row level security on workout_sets still limits it to the
-- caller's own sets.
create or replace function tried_exercise_ids()
returns setof uuid
language sql
stable
as $$
  select distinct exercise_id from workout_sets;
$$;
