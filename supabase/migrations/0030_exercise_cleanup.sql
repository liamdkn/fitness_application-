-- Merges near-duplicate exercises. In each pair below, the row with logged
-- history is the one with malformed data (trailing-space name and/or a
-- malformed equipment string) - not the cleaner-looking duplicate, which
-- turned out to be unused. So history moves onto the clean id, then the
-- malformed row is deleted, rather than the other way around.
update workout_sets set exercise_id = 'c15f23b5-7b46-4a5c-abf7-7864b702c688' -- Lateral Raise
  where exercise_id = 'fac2caff-426d-4e08-a389-fea71793d4d3'; -- "Dumbbell Side Lateral Raise "
update routine_day_exercises set exercise_id = 'c15f23b5-7b46-4a5c-abf7-7864b702c688'
  where exercise_id = 'fac2caff-426d-4e08-a389-fea71793d4d3';

update workout_sets set exercise_id = '08378e43-4afc-41c5-9943-d22744fb7f2d' -- Machine Shoulder Press
  where exercise_id = 'cdd8e345-7f0f-482f-a7e8-161ec299851a'; -- "Shoulder Press Machine "
update routine_day_exercises set exercise_id = '08378e43-4afc-41c5-9943-d22744fb7f2d'
  where exercise_id = 'cdd8e345-7f0f-482f-a7e8-161ec299851a';

update workout_sets set exercise_id = '8cae52a1-f928-4e09-81d1-d5e42b8d7a39' -- Pec Deck Fly
  where exercise_id = 'fb62a17d-6f41-4504-8958-d386220752e1'; -- "Pec Deck Machine "
update routine_day_exercises set exercise_id = '8cae52a1-f928-4e09-81d1-d5e42b8d7a39'
  where exercise_id = 'fb62a17d-6f41-4504-8958-d386220752e1';

update workout_sets set exercise_id = 'e6f2eaff-39c6-4513-969f-4551540d3478' -- Bulgarian Split Squat
  where exercise_id = 'd40dea4b-c834-4546-9cca-e56681a52bf9'; -- "Dumbbell Rear Leg Elevated Split "
update routine_day_exercises set exercise_id = 'e6f2eaff-39c6-4513-969f-4551540d3478'
  where exercise_id = 'd40dea4b-c834-4546-9cca-e56681a52bf9';

delete from exercises where id in (
  'fac2caff-426d-4e08-a389-fea71793d4d3',
  'cdd8e345-7f0f-482f-a7e8-161ec299851a',
  'fb62a17d-6f41-4504-8958-d386220752e1',
  'd40dea4b-c834-4546-9cca-e56681a52bf9'
);

-- Malformed equipment text on other exercises (trailing spaces, blanks,
-- inconsistent capitalization) - found alongside the duplicates above.
update exercises set equipment = 'decline bench' where trim(name) = 'Decline Ab Crunch';
update exercises set equipment = 'smith machine' where trim(name) = 'Incline Smith Press';
update exercises set equipment = 'cable' where trim(name) = 'Dual Rope Pushdown';
update exercises set equipment = 'dumbbell' where trim(name) = 'Lateral Raise';
update exercises set equipment = 'machine' where trim(name) = 'Machine Shoulder Press';
update exercises set equipment = 'machine' where trim(name) = 'Pec Deck Fly';
update exercises set name = trim(name) where trim(name) in ('Dual Rope Pushdown', 'Decline Ab Crunch') and name != trim(name);
