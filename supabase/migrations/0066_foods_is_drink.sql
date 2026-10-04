-- Being measured in ml doesn't make a food a drink (olive oil, hot sauce), so
-- "is a drink" is now its own flag instead of being inferred from the unit.
-- It's what puts a food in the Liquids screen and counts it toward hydration
-- and caffeine.
alter table foods add column is_drink boolean not null default false;

-- Existing foods: anything measured in ml, except obvious non-drinks by name.
update foods
set is_drink = true
where lower(serving_unit) like 'ml%'
  and lower(name) !~ '(oil|sauce|syrup|vinegar|dressing|honey|ketchup|mayonnaise|marinade)';
