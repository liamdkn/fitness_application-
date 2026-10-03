-- Two staples that searches missed: ground cinnamon (Open Food Facts has
-- almost no usable calorie data for plain spices) and Pink Lady apples (the
-- generic "Apple" row didn't match a "pink lady apple" search). Same
-- per-100g reference convention as the rest of the seed catalog; the apple
-- uses typical UK pack-label values.
insert into foods (name, serving_size, serving_unit, calories, protein_g, carbs_g, fat_g, fiber_g, source, is_custom)
select v.name, v.serving_size, v.serving_unit, v.calories, v.protein_g, v.carbs_g, v.fat_g, v.fiber_g, 'seed', false
from (values
  ('Cinnamon (Ground)', 100, 'g', 247, 4, 80.6, 1.2, 53.1),
  ('Pink Lady Apple', 100, 'g', 56, 0.6, 11.6, 0.5, 1.2)
) as v(name, serving_size, serving_unit, calories, protein_g, carbs_g, fat_g, fiber_g)
where not exists (select 1 from foods f where f.name = v.name and f.source = 'seed');
