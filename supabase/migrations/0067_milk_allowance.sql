-- A daily milk allowance: an amount of one milk (default 100 ml) that's added
-- to the Drinks meal once each day, for the milk that goes in tea and coffee.
-- Today's entry is an ordinary meal entry, so changing the amount for one day
-- is just editing it; the default here is what each new day starts with.
alter table user_preferences
  add column milk_allowance_enabled boolean not null default false,
  add column milk_allowance_ml int not null default 100 check (milk_allowance_ml between 0 and 2000),
  add column milk_food_id uuid references foods(id) on delete set null,
  add column milk_applied_date date;
