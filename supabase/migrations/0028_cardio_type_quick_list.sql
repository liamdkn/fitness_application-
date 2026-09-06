-- Which CardioType values show up by default in Start Cardio Session's
-- quick-pick list. The full catalog (CardioType.allCases in Swift) stays
-- available behind the "Add to List" checkbox sheet; this column is just
-- the user's personal subset. Defaults to incline_treadmill + stairmaster,
-- the two the user actually uses day to day.
alter table user_preferences
  add column enabled_cardio_types text[] not null default array['incline_treadmill', 'stairmaster'];
