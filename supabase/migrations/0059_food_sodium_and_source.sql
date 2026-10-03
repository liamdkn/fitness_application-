-- Sodium on foods, and a link from a user's corrected/verified copy back to
-- the shared row it was made from.
--
-- sodium_mg: nullable on purpose - existing foods (seed, Open Food Facts)
-- don't have it, and "not known yet" is different from 0. The food editor
-- asks for it, and won't let a food be marked verified without one.
--
-- source_food_id: a shared catalog row (seed / Open Food Facts) isn't
-- anyone's to edit, so a correction or a "verified" tick is saved as the
-- user's own copy. Pointing the copy at its original lets search hide the
-- original once a copy exists, instead of listing the same food twice.
alter table foods
  add column sodium_mg numeric(8, 2) check (sodium_mg >= 0),
  add column source_food_id uuid references foods(id) on delete set null;

create index foods_source_food_id_idx on foods (source_food_id) where source_food_id is not null;
