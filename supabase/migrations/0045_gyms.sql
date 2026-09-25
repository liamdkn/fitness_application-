-- Tracking which gym a workout happened at - equipment (dumbbell jumps,
-- machine brands) varies enough between gyms that a weight suggestion
-- based on a different gym's last session can be actively wrong. `gyms` is
-- just a per-user named list (e.g. "Navan Gym"); `workouts.gym_id` records
-- which one a session was at, and `user_preferences.preferred_gym_id` is
-- the default a new workout starts with.
create table gyms (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);

alter table gyms enable row level security;

create policy "gyms_owner_all"
  on gyms for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table workouts add column gym_id uuid references gyms(id) on delete set null;
alter table user_preferences add column preferred_gym_id uuid references gyms(id) on delete set null;

-- Same as before when for_gym_id is omitted (existing callers keep working
-- unchanged). When given, prefers the most recent workout at that same gym;
-- if this exercise has never been logged there before, falls back to the
-- most recent workout anywhere, so a first visit to a new gym still shows
-- real history instead of looking like day one on the exercise.
create or replace function previous_exercise_sets(for_exercise_id uuid, for_gym_id uuid default null)
returns setof workout_sets as $$
  select ws.*
  from workout_sets ws
  where ws.exercise_id = for_exercise_id
    and ws.user_id = auth.uid()
    and ws.is_warmup = false
    and ws.workout_id = coalesce(
      (
        select w.id
        from workouts w
        join workout_sets ws2 on ws2.workout_id = w.id
        where w.user_id = auth.uid()
          and ws2.exercise_id = for_exercise_id
          and for_gym_id is not null
          and w.gym_id = for_gym_id
        order by w.performed_at desc
        limit 1
      ),
      (
        select w.id
        from workouts w
        join workout_sets ws2 on ws2.workout_id = w.id
        where w.user_id = auth.uid()
          and ws2.exercise_id = for_exercise_id
        order by w.performed_at desc
        limit 1
      )
    )
  order by ws.set_index;
$$ language sql stable security invoker;
