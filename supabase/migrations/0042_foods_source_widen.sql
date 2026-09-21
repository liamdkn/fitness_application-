-- Widens foods.source for two upcoming sources: 'ocr' (this migration's
-- companion, docs/nutrition-label-scan-brief.md) and 'nutritionix'
-- (docs/food-search-verified-sources-brief.md, not built yet but added
-- now rather than a second migration later).
alter table foods drop constraint foods_source_check;
alter table foods add constraint foods_source_check
  check (source in ('seed', 'off', 'nutritionix', 'user', 'ocr'));
