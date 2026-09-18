alter table tdee_estimates
  add column excluded_bump_days integer not null default 0;
