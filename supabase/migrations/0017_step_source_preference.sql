-- Which HealthKit source to use for daily step totals. 'merged' matches the
-- Health app's own cross-source deduplicated total; 'apple_watch' counts
-- only Watch-recorded steps (undercounts on days the Watch isn't worn, but
-- some users prefer the single-source consistency).
alter table user_preferences
  add column step_source text not null default 'merged'
  check (step_source in ('merged', 'apple_watch'));
