-- Weekly Log: a server-side aggregate returning one row per week (avg
-- weight/calories/macros/steps), so the client can render the whole
-- scannable history table in one round-trip instead of calling something
-- like WeeklyInsightsViewModel's per-week computation once per row.
--
-- Weeks are bucketed with date_trunc('week', ...), which is Monday-anchored
-- - the same boundary WeeklyInsightsViewModel's `mondayOfWeek` uses - not
-- the user's separately-configurable `weekly_checkin_weekday` (a different
-- concept: when a check-in is *due*, not where a week starts).
create or replace function weekly_log_summary(p_limit int default 12, p_before date default null)
returns table (
  week_start date,
  avg_weight_kg numeric,
  avg_calories numeric,
  avg_protein_g numeric,
  avg_carbs_g numeric,
  avg_fat_g numeric,
  avg_steps numeric
) as $$
  with nutrition_daily as (
    -- Per-day totals derived from meal_entries - quantity is already a
    -- plain multiplier of a food/recipe's cached per-serving macros (see
    -- Food.calories(at:)/Recipe.calories(at:) client-side), so no serving-
    -- size conversion is needed here beyond the multiply.
    select
      me.date,
      sum(me.quantity * coalesce(f.calories, r.calories)) as calories,
      sum(me.quantity * coalesce(f.protein_g, r.protein_g)) as protein_g,
      sum(me.quantity * coalesce(f.carbs_g, r.carbs_g)) as carbs_g,
      sum(me.quantity * coalesce(f.fat_g, r.fat_g)) as fat_g
    from meal_entries me
    left join foods f on f.id = me.food_id
    left join recipes r on r.id = me.recipe_id
    where me.user_id = auth.uid()
    group by me.date
  ),
  -- Cutover-aware, per NutritionRepository's documented migration path:
  -- meal_entries-derived totals win for any date that has them, falling
  -- back to the legacy nutrition_logs row for dates before a user's
  -- cutover to in-house logging.
  nutrition_combined as (
    select date, calories, protein_g, carbs_g, fat_g from nutrition_daily
    union all
    select nl.date, nl.calories, nl.protein_g, nl.carbs_g, nl.fat_g
    from nutrition_logs nl
    where nl.user_id = auth.uid()
      and nl.date not in (select date from nutrition_daily)
  ),
  weight_weekly as (
    select date_trunc('week', logged_at)::date as week_start, avg(weight_kg) as avg_weight_kg
    from body_weight_logs
    where user_id = auth.uid()
    group by 1
  ),
  -- Only fully-elapsed days count, matching avgStepsPerDay's existing
  -- semantics (a still-accumulating today shouldn't drag the average
  -- down) - true for every day of any past week already, so this one
  -- filter covers both the current week and history without a special case.
  -- Also mirrors avgStepsPerDay's cardio-step exclusion: if the user has
  -- that preference on, a day's machine-counted cardio steps (steps_after
  -- - steps_before, per cardio_step_sessions) are subtracted before
  -- averaging - without this, Weekly Log and Weekly Insights would show
  -- two different numbers for the exact same week.
  steps_weekly as (
    select
      date_trunc('week', sl.date)::date as week_start,
      avg(greatest(sl.step_count - case
        when (select cardio_step_exclusion_enabled from user_preferences up where up.user_id = auth.uid())
        then coalesce((
          select sum(css.steps_after - css.steps_before)
          from cardio_step_sessions css
          where css.user_id = auth.uid() and css.date = sl.date
        ), 0)
        else 0
      end, 0)) as avg_steps
    from step_logs sl
    where sl.user_id = auth.uid() and sl.date < current_date
    group by 1
  ),
  nutrition_weekly as (
    select
      date_trunc('week', date)::date as week_start,
      avg(calories) as avg_calories,
      avg(protein_g) as avg_protein_g,
      avg(carbs_g) as avg_carbs_g,
      avg(fat_g) as avg_fat_g
    from nutrition_combined
    group by 1
  ),
  -- Only weeks with at least one logged data point show up as a row -
  -- weeks before someone started tracking anything would just be noise.
  weeks as (
    select week_start from weight_weekly
    union
    select week_start from steps_weekly
    union
    select week_start from nutrition_weekly
  )
  select
    w.week_start,
    ww.avg_weight_kg,
    nw.avg_calories,
    nw.avg_protein_g,
    nw.avg_carbs_g,
    nw.avg_fat_g,
    sw.avg_steps
  from weeks w
  left join weight_weekly ww using (week_start)
  left join nutrition_weekly nw using (week_start)
  left join steps_weekly sw using (week_start)
  where p_before is null or w.week_start < p_before
  order by w.week_start desc
  limit p_limit;
$$ language sql security invoker stable;
