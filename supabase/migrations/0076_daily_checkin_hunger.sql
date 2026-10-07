-- How hungry the previous day was, 1 (not at all) to 5 (starving). Like the
-- other yesterday_* fields it lives on today's check-in row.
alter table daily_checkins
  add column if not exists yesterday_hunger_level int
  check (yesterday_hunger_level between 1 and 5);
