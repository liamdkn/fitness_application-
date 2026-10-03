-- Optional grouping for saved meals: "Overnight oats" can hold several
-- variants (oats + berries, oats + peanut butter...), and the Saved Meals
-- picker lists them together. Free text rather than a table - categories
-- are just the distinct values in use, so there's nothing to manage.
alter table saved_meals add column category text;
