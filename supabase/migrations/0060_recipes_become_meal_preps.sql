-- Meal Prep replaces Recipes as the one way to make a dish: it does
-- everything a recipe did (ingredients, per-portion macros, logging a
-- portion) plus tracking what's left, eat-by dates and the freezer.
--
-- Every existing standalone recipe becomes a meal prep batch backed by the
-- same recipes row, so its ingredients, id and anything referencing it
-- (logged entries, saved meals/days) carry over untouched. Portions can't
-- be known for an old recipe - it was stored as one serving holding the
-- whole batch - so it's set to 1 and the user edits it in the app.
insert into meal_preps (user_id, name, recipe_id, prepped_on, portions, eat_within_days)
select r.user_id, r.name, r.id, r.created_at::date, 1, 3
from recipes r
where not r.is_meal_prep
  and not exists (select 1 from meal_preps p where p.recipe_id = r.id);

update recipes
set is_meal_prep = true,
    serving_unit = case when serving_unit = 'serving' then 'portion' else serving_unit end
where not is_meal_prep;
