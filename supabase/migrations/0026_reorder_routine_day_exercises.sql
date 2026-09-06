-- Persists a drag-to-reorder of a routine day's exercises in one atomic
-- statement. A single multi-row UPDATE is what makes this safe against the
-- routine_day_exercises_routine_day_id_position_key unique constraint -
-- Postgres checks a plain (non-deferrable) unique constraint against the
-- final state of all rows touched by one statement, not row-by-row as the
-- update proceeds, so a full reshuffle of positions (including swaps) can't
-- collide with itself mid-statement the way a sequence of separate
-- single-row updates could.
create or replace function reorder_routine_day_exercises(p_routine_day_id uuid, p_ordered_ids uuid[])
returns void as $$
  update routine_day_exercises rde
  set position = v.new_position
  from unnest(p_ordered_ids) with ordinality as v(id, new_position)
  where rde.id = v.id
    and rde.routine_day_id = p_routine_day_id
    and rde.user_id = auth.uid();
$$ language sql security invoker;
