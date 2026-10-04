-- 'quick_add': a one-off "just add these calories and macros" entry. It is
-- stored as a food row so a meal entry can point at it (every total in the
-- app reads food rows), but the app never lists it in search, recents or the
-- food database.
alter table foods drop constraint foods_source_check;
alter table foods add constraint foods_source_check
  check (source in ('seed', 'off', 'nutritionix', 'user', 'ocr', 'quick_add'));
