-- Caffeine tracking and a starter set of drinks.
--
-- A drink is just a food measured in ml, so logging one is a normal meal
-- entry: its calories, sugar and sodium count once in the day's totals, and
-- caffeine/hydration are read from those same entries. caffeine_mg is per
-- serving like every other nutrient on `foods`; null = not recorded.
alter table foods
  add column caffeine_mg numeric(7, 2) check (caffeine_mg >= 0);

-- Per-user settings that drive the caffeine curve and the sodium bar.
-- Defaults: ~5 h caffeine half-life (the usual adult figure; it varies a lot
-- between people), a 400 mg/day ceiling (the widely used adult guideline),
-- and aiming to be under 50 mg by a 22:30 bedtime.
alter table user_preferences
  add column sodium_limit_mg int not null default 2300 check (sodium_limit_mg > 0),
  add column caffeine_limit_mg int not null default 400 check (caffeine_limit_mg > 0),
  add column bedtime_minutes int not null default 1350 check (bedtime_minutes between 0 and 1439),
  add column caffeine_half_life_hours numeric(3, 1) not null default 5.0 check (caffeine_half_life_hours between 2 and 12),
  add column caffeine_bedtime_target_mg int not null default 50 check (caffeine_bedtime_target_mg >= 0);

-- Starter drinks, per 100 ml (typical label values - verify against your own
-- can/bottle: brands and regions differ, and the app asks you to check any
-- food before you rely on it). Existing rows by name are left alone.
insert into foods (name, serving_size, serving_unit, calories, protein_g, carbs_g, fat_g, sodium_mg, caffeine_mg, source, is_custom)
select v.name, 100, 'ml', v.calories, 0, v.carbs, 0, v.sodium, v.caffeine, 'seed', false
from (values
  ('Pepsi',                   42, 10.9,  4, 10),
  ('Pepsi Max',                0.3, 0,  12, 20),
  ('Coca-Cola',               42, 10.6,  4, 10),
  ('Coca-Cola Zero',           0.2, 0,  12, 10),
  ('Diet Coke',                0.2, 0,  12, 13),
  ('Monster Energy',          46, 11,   40, 32),
  ('Monster Ultra (Zero Sugar)', 3, 0.5, 40, 30),
  ('Red Bull',                45, 11,   10, 32),
  ('Coffee (Brewed, Filter)',  1, 0,     2, 40),
  ('Espresso',                 2, 0,    14, 212),
  ('Instant Coffee (Made Up)', 1, 0,     2, 30),
  ('Black Tea',                1, 0.2,   3, 20),
  ('Green Tea',                1, 0,     2, 12),
  ('Sparkling Water',          0, 0,     1, 0)
) as v(name, calories, carbs, sodium, caffeine)
where not exists (select 1 from foods f where f.name = v.name and f.source = 'seed');

-- Coffee (Black) is stored per 240 ml cup, so its caffeine is per cup, not per 100 ml.
update foods set caffeine_mg = 95 where name = 'Coffee (Black)' and source = 'seed' and caffeine_mg is null;
update foods set caffeine_mg = 10 where name = 'Cola' and source = 'seed' and caffeine_mg is null;
