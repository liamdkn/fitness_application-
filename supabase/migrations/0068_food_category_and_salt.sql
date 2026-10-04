-- Food categories: each food is mainly a protein, carb or fat source (or
-- something else - seasoning, mostly water). Lets a meal be read as its
-- protein / carb / fat parts, and later lets the app build meals by swapping
-- sources within a category.
alter table foods add column category text check (category in ('protein', 'carb', 'fat', 'other'));

-- Backfill from where a food's energy comes from (4/4/9 kcal per gram):
-- protein if at least 30% of it is protein (salmon, eggs, chicken, yoghurt -
-- protein sources even when fat supplies more), otherwise fat or carbs if one
-- supplies at least 45%. Mixed and near-zero-calorie foods stay unset for the
-- user to decide.
with shares as (
  select id,
         protein_g * 4 as p, carbs_g * 4 as c, fat_g * 9 as f,
         protein_g * 4 + carbs_g * 4 + fat_g * 9 as total
  from foods
)
update foods
set category = case
  when s.total <= 10 then null
  when s.p / s.total >= 0.30 then 'protein'
  when s.f / s.total >= 0.45 and s.f >= s.c then 'fat'
  when s.c / s.total >= 0.45 and s.c >= s.f then 'carb'
  else null
end
from shares s
where s.id = foods.id and foods.name <> 'Salt';

-- Table salt, so salt can be added to a meal in grams: it's about 39.3%
-- sodium by weight, i.e. 393 mg of sodium per gram.
insert into foods (name, serving_size, serving_unit, calories, protein_g, carbs_g, fat_g, sodium_mg,
                   source, is_custom, is_verified, is_drink, category)
select 'Salt', 100, 'g', 0, 0, 0, 0, 39300, 'seed', false, true, false, 'other'
where not exists (select 1 from foods where name = 'Salt' and source = 'seed');
