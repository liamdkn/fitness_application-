-- A prepped batch can be moved to the freezer: it stops counting down to an
-- eat-by date while frozen, and thawing it restarts that clock from the day
-- it came out (thawed food has a short life again, however long it sat in
-- the freezer). `prepped_on` stays the day it was cooked - the dates here
-- only record the moves.
alter table meal_preps
  add column location text not null default 'fridge' check (location in ('fridge', 'freezer')),
  add column frozen_on date,
  add column thawed_on date;
