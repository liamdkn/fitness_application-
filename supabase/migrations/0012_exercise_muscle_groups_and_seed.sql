-- Constrain primary_muscle_group to a fixed set of categories (was free
-- text), and seed a real exercise library. Previously the catalog held
-- only whatever a user manually inserted during testing.

-- Normalize any stray existing values first so the new check can never
-- fail against unknown legacy data.
update exercises
set primary_muscle_group = null
where primary_muscle_group is not null
  and primary_muscle_group not in (
    'chest', 'back', 'shoulders', 'biceps', 'triceps', 'quads', 'hamstrings',
    'glutes', 'calves', 'abs', 'forearms', 'full_body', 'cardio', 'mobility'
  );

alter table exercises
  add constraint exercises_primary_muscle_group_check
  check (primary_muscle_group is null or primary_muscle_group in (
    'chest', 'back', 'shoulders', 'biceps', 'triceps', 'quads', 'hamstrings',
    'glutes', 'calves', 'abs', 'forearms', 'full_body', 'cardio', 'mobility'
  ));

-- Seed the catalog, skipping any name that already exists as a catalog
-- entry (e.g. "Barbell Back Squat" was inserted manually during testing).
insert into exercises (name, category, primary_muscle_group, equipment, is_custom)
select v.name, v.category, v.primary_muscle_group, v.equipment, v.is_custom
from (values
  -- Chest
  ('Barbell Bench Press', 'compound', 'chest', 'barbell', false),
  ('Incline Barbell Bench Press', 'compound', 'chest', 'barbell', false),
  ('Incline Dumbbell Press', 'compound', 'chest', 'dumbbell', false),
  ('Dumbbell Bench Press', 'compound', 'chest', 'dumbbell', false),
  ('Dumbbell Flyes', 'isolation', 'chest', 'dumbbell', false),
  ('Cable Chest Fly', 'isolation', 'chest', 'cable', false),
  ('Push-Up', 'compound', 'chest', 'bodyweight', false),
  ('Chest Dip', 'compound', 'chest', 'bodyweight', false),

  -- Back
  ('Deadlift', 'compound', 'back', 'barbell', false),
  ('Pull-Up', 'compound', 'back', 'bodyweight', false),
  ('Chin-Up', 'compound', 'back', 'bodyweight', false),
  ('Lat Pulldown', 'compound', 'back', 'cable', false),
  ('Barbell Row', 'compound', 'back', 'barbell', false),
  ('Pendlay Row', 'compound', 'back', 'barbell', false),
  ('Seated Cable Row', 'compound', 'back', 'cable', false),
  ('One-Arm Dumbbell Row', 'compound', 'back', 'dumbbell', false),
  ('T-Bar Row', 'compound', 'back', 'barbell', false),

  -- Shoulders
  ('Overhead Press', 'compound', 'shoulders', 'barbell', false),
  ('Dumbbell Shoulder Press', 'compound', 'shoulders', 'dumbbell', false),
  ('Arnold Press', 'compound', 'shoulders', 'dumbbell', false),
  ('Lateral Raise', 'isolation', 'shoulders', 'dumbbell', false),
  ('Front Raise', 'isolation', 'shoulders', 'dumbbell', false),
  ('Face Pull', 'isolation', 'shoulders', 'cable', false),
  ('Rear Delt Fly', 'isolation', 'shoulders', 'dumbbell', false),

  -- Biceps
  ('Barbell Curl', 'isolation', 'biceps', 'barbell', false),
  ('Dumbbell Curl', 'isolation', 'biceps', 'dumbbell', false),
  ('Hammer Curl', 'isolation', 'biceps', 'dumbbell', false),
  ('Preacher Curl', 'isolation', 'biceps', 'barbell', false),
  ('Cable Curl', 'isolation', 'biceps', 'cable', false),

  -- Triceps
  ('Tricep Pushdown', 'isolation', 'triceps', 'cable', false),
  ('Skull Crusher', 'isolation', 'triceps', 'barbell', false),
  ('Overhead Tricep Extension', 'isolation', 'triceps', 'dumbbell', false),
  ('Close-Grip Bench Press', 'compound', 'triceps', 'barbell', false),
  ('Tricep Dip', 'compound', 'triceps', 'bodyweight', false),

  -- Quads
  ('Barbell Back Squat', 'compound', 'quads', 'barbell', false),
  ('Front Squat', 'compound', 'quads', 'barbell', false),
  ('Leg Press', 'compound', 'quads', 'machine', false),
  ('Leg Extension', 'isolation', 'quads', 'machine', false),
  ('Walking Lunge', 'compound', 'quads', 'dumbbell', false),
  ('Bulgarian Split Squat', 'compound', 'quads', 'dumbbell', false),

  -- Hamstrings
  ('Romanian Deadlift', 'compound', 'hamstrings', 'barbell', false),
  ('Leg Curl', 'isolation', 'hamstrings', 'machine', false),
  ('Good Morning', 'compound', 'hamstrings', 'barbell', false),

  -- Glutes
  ('Hip Thrust', 'compound', 'glutes', 'barbell', false),
  ('Glute Bridge', 'compound', 'glutes', 'bodyweight', false),
  ('Cable Kickback', 'isolation', 'glutes', 'cable', false),

  -- Calves
  ('Standing Calf Raise', 'isolation', 'calves', 'machine', false),
  ('Seated Calf Raise', 'isolation', 'calves', 'machine', false),

  -- Abs
  ('Plank', 'isolation', 'abs', 'bodyweight', false),
  ('Hanging Leg Raise', 'isolation', 'abs', 'bodyweight', false),
  ('Ab Wheel Rollout', 'isolation', 'abs', 'bodyweight', false),
  ('Cable Crunch', 'isolation', 'abs', 'cable', false),

  -- Forearms
  ('Wrist Curl', 'isolation', 'forearms', 'barbell', false),
  ('Farmer''s Carry', 'compound', 'forearms', 'dumbbell', false),

  -- Full body
  ('Kettlebell Swing', 'compound', 'full_body', 'kettlebell', false),
  ('Clean and Jerk', 'compound', 'full_body', 'barbell', false),
  ('Burpee', 'compound', 'full_body', 'bodyweight', false),

  -- Cardio
  ('Treadmill Running', 'cardio', 'cardio', 'machine', false),
  ('Rowing Machine', 'cardio', 'cardio', 'machine', false),
  ('Stationary Bike', 'cardio', 'cardio', 'machine', false),
  ('Jump Rope', 'cardio', 'cardio', 'bodyweight', false),

  -- Mobility
  ('Foam Rolling', 'mobility', 'mobility', 'bodyweight', false),
  ('Cat-Cow Stretch', 'mobility', 'mobility', 'bodyweight', false),
  ('World''s Greatest Stretch', 'mobility', 'mobility', 'bodyweight', false)
) as v(name, category, primary_muscle_group, equipment, is_custom)
where not exists (
  select 1 from exercises e where e.name = v.name and e.is_custom = false
);
