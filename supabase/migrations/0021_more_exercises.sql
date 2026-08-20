-- Expands the exercise library (0012 seeded ~64 exercises; this roughly
-- doubles coverage per muscle group with common machine/bodyweight/isolation
-- variants that weren't yet included). Same idempotent insert-if-missing
-- pattern as 0012.
insert into exercises (name, category, primary_muscle_group, equipment, is_custom)
select v.name, v.category, v.primary_muscle_group, v.equipment, v.is_custom
from (values
  -- Chest
  ('Decline Barbell Bench Press', 'compound', 'chest', 'barbell', false),
  ('Decline Dumbbell Press', 'compound', 'chest', 'dumbbell', false),
  ('Machine Chest Press', 'compound', 'chest', 'machine', false),
  ('Pec Deck Fly', 'isolation', 'chest', 'machine', false),
  ('Cable Crossover', 'isolation', 'chest', 'cable', false),
  ('Svend Press', 'isolation', 'chest', 'dumbbell', false),
  ('Incline Push-Up', 'compound', 'chest', 'bodyweight', false),

  -- Back
  ('Weighted Pull-Up', 'compound', 'back', 'bodyweight', false),
  ('Close-Grip Lat Pulldown', 'compound', 'back', 'cable', false),
  ('Straight-Arm Pulldown', 'isolation', 'back', 'cable', false),
  ('Chest-Supported Row', 'compound', 'back', 'machine', false),
  ('Machine Row', 'compound', 'back', 'machine', false),
  ('Inverted Row', 'compound', 'back', 'bodyweight', false),
  ('Rack Pull', 'compound', 'back', 'barbell', false),
  ('Meadows Row', 'compound', 'back', 'barbell', false),

  -- Shoulders
  ('Machine Shoulder Press', 'compound', 'shoulders', 'machine', false),
  ('Cable Lateral Raise', 'isolation', 'shoulders', 'cable', false),
  ('Upright Row', 'compound', 'shoulders', 'barbell', false),
  ('Barbell Shrug', 'isolation', 'shoulders', 'barbell', false),
  ('Landmine Press', 'compound', 'shoulders', 'barbell', false),
  ('Reverse Pec Deck', 'isolation', 'shoulders', 'machine', false),

  -- Biceps
  ('Concentration Curl', 'isolation', 'biceps', 'dumbbell', false),
  ('Incline Dumbbell Curl', 'isolation', 'biceps', 'dumbbell', false),
  ('EZ-Bar Curl', 'isolation', 'biceps', 'barbell', false),
  ('Cable Rope Hammer Curl', 'isolation', 'biceps', 'cable', false),
  ('Spider Curl', 'isolation', 'biceps', 'barbell', false),
  ('21s Bicep Curl', 'isolation', 'biceps', 'barbell', false),

  -- Triceps
  ('Cable Overhead Tricep Extension', 'isolation', 'triceps', 'cable', false),
  ('Diamond Push-Up', 'compound', 'triceps', 'bodyweight', false),
  ('JM Press', 'compound', 'triceps', 'barbell', false),
  ('Dumbbell Kickback', 'isolation', 'triceps', 'dumbbell', false),
  ('Bench Dip', 'compound', 'triceps', 'bodyweight', false),

  -- Quads
  ('Hack Squat', 'compound', 'quads', 'machine', false),
  ('Goblet Squat', 'compound', 'quads', 'dumbbell', false),
  ('Step-Up', 'compound', 'quads', 'dumbbell', false),
  ('Sissy Squat', 'isolation', 'quads', 'bodyweight', false),
  ('Smith Machine Squat', 'compound', 'quads', 'machine', false),
  ('Single-Leg Leg Press', 'compound', 'quads', 'machine', false),

  -- Hamstrings
  ('Seated Leg Curl', 'isolation', 'hamstrings', 'machine', false),
  ('Lying Leg Curl', 'isolation', 'hamstrings', 'machine', false),
  ('Single-Leg Romanian Deadlift', 'compound', 'hamstrings', 'dumbbell', false),
  ('Nordic Curl', 'isolation', 'hamstrings', 'bodyweight', false),
  ('Glute-Ham Raise', 'compound', 'hamstrings', 'machine', false),

  -- Glutes
  ('Cable Pull-Through', 'compound', 'glutes', 'cable', false),
  ('Donkey Kick', 'isolation', 'glutes', 'bodyweight', false),
  ('Frog Pump', 'isolation', 'glutes', 'bodyweight', false),
  ('Sumo Deadlift', 'compound', 'glutes', 'barbell', false),

  -- Calves
  ('Donkey Calf Raise', 'isolation', 'calves', 'machine', false),
  ('Single-Leg Calf Raise', 'isolation', 'calves', 'bodyweight', false),

  -- Abs
  ('Russian Twist', 'isolation', 'abs', 'bodyweight', false),
  ('Sit-Up', 'isolation', 'abs', 'bodyweight', false),
  ('Bicycle Crunch', 'isolation', 'abs', 'bodyweight', false),
  ('Mountain Climber', 'compound', 'abs', 'bodyweight', false),
  ('Dead Bug', 'isolation', 'abs', 'bodyweight', false),
  ('Cable Woodchopper', 'isolation', 'abs', 'cable', false),
  ('V-Up', 'isolation', 'abs', 'bodyweight', false),

  -- Forearms
  ('Reverse Curl', 'isolation', 'forearms', 'barbell', false),
  ('Plate Pinch Hold', 'isolation', 'forearms', 'bodyweight', false),
  ('Behind-the-Back Wrist Curl', 'isolation', 'forearms', 'barbell', false),

  -- Full body
  ('Thruster', 'compound', 'full_body', 'barbell', false),
  ('Man Maker', 'compound', 'full_body', 'dumbbell', false),
  ('Turkish Get-Up', 'compound', 'full_body', 'kettlebell', false),
  ('Sled Push', 'compound', 'full_body', 'machine', false),
  ('Battle Ropes', 'compound', 'full_body', 'bodyweight', false),

  -- Cardio
  ('Elliptical', 'cardio', 'cardio', 'machine', false),
  ('StairMaster', 'cardio', 'cardio', 'machine', false),
  ('Assault Bike', 'cardio', 'cardio', 'machine', false),
  ('Swimming', 'cardio', 'cardio', 'bodyweight', false),
  ('Outdoor Cycling', 'cardio', 'cardio', 'bodyweight', false),

  -- Mobility
  ('Hip Flexor Stretch', 'mobility', 'mobility', 'bodyweight', false),
  ('Thoracic Spine Rotation', 'mobility', 'mobility', 'bodyweight', false),
  ('Shoulder Dislocates', 'mobility', 'mobility', 'bodyweight', false),
  ('90/90 Hip Stretch', 'mobility', 'mobility', 'bodyweight', false),
  ('Ankle Mobility Drill', 'mobility', 'mobility', 'bodyweight', false)
) as v(name, category, primary_muscle_group, equipment, is_custom)
where not exists (
  select 1 from exercises e where e.name = v.name and e.is_custom = false
);
