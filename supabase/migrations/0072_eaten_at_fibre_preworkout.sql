-- Nutrition additions.
--
-- 1. meal_entries.eaten_at: when the food was actually eaten, as opposed to
--    logged_at (when it was typed in). Null means unknown. It is what lines
--    meals up against blood-glucose readings later, so it's a real timestamp.
-- 2. user_preferences.fibre_goal_g: daily fibre target (default 30 g).
-- 3. user_preferences.preworkout_carbs_g_per_kg: carbs to aim for before a
--    workout, per kg of bodyweight (default 1 g/kg). 0 turns the goal off.

alter table meal_entries
  add column if not exists eaten_at timestamptz;

alter table user_preferences
  add column if not exists fibre_goal_g integer not null default 30,
  add column if not exists preworkout_carbs_g_per_kg numeric(3,1) not null default 1.0;

alter table user_preferences
  add constraint user_preferences_fibre_goal_range check (fibre_goal_g between 0 and 200),
  add constraint user_preferences_preworkout_carbs_range check (preworkout_carbs_g_per_kg between 0 and 5);
