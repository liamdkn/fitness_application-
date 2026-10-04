-- A food can fill more than one role in a meal - salmon and eggs are a
-- protein source and a healthy-fat source - so a food has a list of
-- categories rather than one. The first (protein, then carb, then fat) is its
-- "main" one, used when a meal lists its foods by part.
-- Supersedes the single `category` column added in 0068.
alter table foods add column categories text[] not null default '{}'
  check (categories <@ array['protein', 'carb', 'fat', 'other']);

-- Every macro that supplies at least 30% of a food's energy (4/4/9 kcal per
-- gram) is one of its categories. Near-zero-calorie foods stay empty.
with shares as (
  select id,
         protein_g * 4 as p, carbs_g * 4 as c, fat_g * 9 as f,
         protein_g * 4 + carbs_g * 4 + fat_g * 9 as total
  from foods
)
update foods
set categories = case
  when foods.name = 'Salt' and foods.source = 'seed' then array['other']
  when s.total <= 10 then '{}'
  else array_remove(array[
         case when s.p / s.total >= 0.30 then 'protein' end,
         case when s.c / s.total >= 0.30 then 'carb' end,
         case when s.f / s.total >= 0.30 then 'fat' end
       ], null)
end
from shares s
where s.id = foods.id;

alter table foods drop column category;
