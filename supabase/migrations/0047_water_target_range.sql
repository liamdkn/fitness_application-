-- Water target as a range (e.g. 3-4L) rather than one exact number - a day
-- landing anywhere in the range counts as "on target", matching how this
-- gets thought about day to day rather than one precise figure.
alter table user_preferences
  add column daily_water_ml_target_min int not null default 2500 check (daily_water_ml_target_min > 0),
  add column daily_water_ml_target_max int not null default 3000 check (daily_water_ml_target_max > 0);

update user_preferences
  set daily_water_ml_target_min = daily_water_ml_target,
      daily_water_ml_target_max = daily_water_ml_target;

alter table user_preferences
  add constraint daily_water_ml_target_range_check check (daily_water_ml_target_max >= daily_water_ml_target_min);

alter table user_preferences
  drop column daily_water_ml_target;
