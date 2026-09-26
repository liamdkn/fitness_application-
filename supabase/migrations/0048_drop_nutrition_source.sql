-- The in-house meal log is now the only Nutrition screen - there's no
-- second screen left for this to switch between, and Health's dietary
-- sync now always runs (see HealthSyncService) to fill gaps during the
-- cutover rather than being gated on this flag.
alter table user_preferences
  drop column nutrition_source;
