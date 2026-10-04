-- Exercises can work more than one muscle group. `primary_muscle_group` stays
-- the main one (used for grouping in the library); `secondary_muscle_groups`
-- lists the others so injury warnings fire for any muscle an exercise loads,
-- e.g. a bench press warns for a triceps or shoulder injury, not just chest.

alter table exercises
  add column if not exists secondary_muscle_groups text[] not null default '{}';

alter table exercises
  add constraint exercises_secondary_muscle_groups_check
  check (secondary_muscle_groups <@ array[
    'chest', 'back', 'shoulders', 'biceps', 'triceps', 'quads', 'hamstrings',
    'glutes', 'calves', 'abs', 'forearms', 'full_body', 'cardio', 'mobility'
  ]::text[]);

-- Seed secondaries for the catalogue by name pattern. Patterns are listed
-- most specific first and each exercise takes the first one it matches.
-- Only catalogue rows (is_custom = false) that don't have any set yet.
with patterns(rank, pattern, groups) as (
  select row_number() over (), pattern, groups from (values
  -- Specific names first, so a broader pattern below can't win.
  ('close-grip bench press', array['chest', 'shoulders']),
  ('upright row', array['biceps', 'back']),
  ('%leg curl%', array[]::text[]),
  ('%row', array['biceps', 'shoulders', 'forearms']),
  -- Chest presses and dips load triceps and front delts.
  ('%bench press%', array['triceps', 'shoulders']),
  ('%chest press%', array['triceps', 'shoulders']),
  ('%incline%press%', array['triceps', 'shoulders']),
  ('%decline%press%', array['triceps', 'shoulders']),
  ('%push-up%', array['triceps', 'shoulders', 'abs']),
  ('%chest dip%', array['triceps', 'shoulders']),
  ('%svend%', array['shoulders']),
  -- Back: pulls load biceps and rear delts; hinges load glutes/hamstrings.
  ('deadlift', array['hamstrings', 'glutes', 'forearms', 'quads']),
  ('rack pull', array['hamstrings', 'glutes', 'forearms']),
  ('%pull-up%', array['biceps', 'forearms', 'shoulders']),
  ('%chin-up%', array['biceps', 'forearms']),
  ('%pulldown%', array['biceps', 'forearms']),
  -- Shoulders.
  ('%shoulder press%', array['triceps']),
  ('overhead press', array['triceps', 'abs']),
  ('arnold press', array['triceps']),
  ('landmine press', array['triceps', 'chest']),
  ('%shrug%', array['back', 'forearms']),
  ('face pull', array['back', 'biceps']),
  ('%rear delt%', array['back']),
  ('reverse pec deck', array['back']),
  -- Arms.
  ('%curl%', array['forearms']),
  ('%dip%', array['chest', 'shoulders']),
  ('diamond push-up', array['chest', 'shoulders']),
  ('jm press', array['chest', 'shoulders']),
  -- Legs.
  ('%squat%', array['glutes', 'hamstrings', 'abs']),
  ('leg press', array['glutes', 'hamstrings']),
  ('%lunge%', array['glutes', 'hamstrings', 'calves']),
  ('step-up', array['glutes', 'hamstrings']),
  ('romanian deadlift', array['glutes', 'back', 'forearms']),
  ('good morning', array['glutes', 'back']),
  ('hip thrust', array['hamstrings', 'quads']),
  ('glute bridge', array['hamstrings']),
  -- Core and carries.
  ('plank', array['shoulders', 'glutes']),
  ('ab wheel rollout', array['shoulders', 'back']),
  ('hanging leg raise', array['forearms']),
  ('farmer''s carry', array['back', 'shoulders', 'abs']),
  ('kettlebell swing', array['glutes', 'hamstrings', 'back', 'shoulders']),
  ('clean and jerk', array['quads', 'glutes', 'back', 'shoulders', 'triceps']),
  ('burpee', array['chest', 'quads', 'shoulders', 'triceps'])
) as v(pattern, groups)
),
best as (
  select distinct on (e.id) e.id, array(
      select g from unnest(p.groups) g where g is distinct from e.primary_muscle_group
    ) as groups
  from exercises e
  join patterns p on lower(e.name) like p.pattern
  where e.is_custom = false and e.secondary_muscle_groups = '{}'
  order by e.id, p.rank
)
update exercises e
set secondary_muscle_groups = best.groups
from best
where e.id = best.id;

-- Corrections for names the patterns above handle badly or miss.
update exercises set secondary_muscle_groups = '{}' where is_custom = false and name = 'Nordic Curl';
update exercises set secondary_muscle_groups = array['chest', 'shoulders'] where is_custom = false and name = 'Diamond Push-Up';
update exercises set secondary_muscle_groups = array['quads', 'hamstrings', 'back'] where is_custom = false and name = 'Sumo Deadlift';
update exercises set secondary_muscle_groups = array['glutes', 'back'] where is_custom = false and name = 'Single-Leg Romanian Deadlift';
update exercises set secondary_muscle_groups = array['glutes', 'hamstrings'] where is_custom = false and name = 'Single-Leg Leg Press';
update exercises set secondary_muscle_groups = array['biceps'] where is_custom = false and name = 'Reverse Curl';
update exercises set secondary_muscle_groups = array['quads', 'shoulders', 'abs'] where is_custom = false and name = 'Thruster';
update exercises set secondary_muscle_groups = array['back', 'shoulders', 'abs'] where is_custom = false and name = 'Turkish Get-Up';
update exercises set secondary_muscle_groups = array['hamstrings', 'glutes'] where is_custom = false and name = 'Treadmill Running';
update exercises set secondary_muscle_groups = array['back', 'biceps', 'hamstrings'] where is_custom = false and name = 'Rowing Machine';
update exercises set secondary_muscle_groups = array['glutes', 'hamstrings', 'calves'] where is_custom = false and name in ('Mountain Climber', 'StairMaster', 'Sled Push');
update exercises set secondary_muscle_groups = array['shoulders', 'abs'] where is_custom = false and name = 'Cable Woodchopper';
