-- Tags a logged set as part of a drop-set chain. Drops are still ordinary
-- rows in set_index order (they contribute to volume/progression like any
-- other set) - this column only drives display grouping ("Drop 1", "Drop 2"
-- following the set they chained off) and tells the app to skip starting a
-- rest timer between them.
alter table workout_sets add column is_drop_set boolean not null default false;
