-- Same atomic-multi-row-update pattern as reorder_routine_day_exercises -
-- a single statement is what makes this safe against meal_slots'
-- (user_id, sort_order) unique constraint, since Postgres only checks a
-- plain unique constraint against the final state of all rows touched by
-- one statement, not row-by-row as a naive sequence of single-row updates
-- would.
create or replace function reorder_meal_slots(p_ordered_ids uuid[])
returns void as $$
  update meal_slots ms
  set sort_order = v.new_order
  from unnest(p_ordered_ids) with ordinality as v(id, new_order)
  where ms.id = v.id
    and ms.user_id = auth.uid();
$$ language sql security invoker;
