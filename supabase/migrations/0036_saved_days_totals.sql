-- Cached macro totals on saved_days, same pattern as recipes: computed
-- client-side at save time from every item's underlying food/recipe times
-- its quantity, rather than derived live on every read - the whole point
-- of a saved-days picker is comparing options at a glance ("which of these
-- fits today"), so it needs to be cheap to list many of them.
alter table saved_days
  add column calories numeric(7, 2) not null default 0,
  add column protein_g numeric(6, 2) not null default 0,
  add column carbs_g numeric(6, 2) not null default 0,
  add column fat_g numeric(6, 2) not null default 0,
  add column fiber_g numeric(6, 2) not null default 0;
