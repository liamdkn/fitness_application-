-- "Calorie banking" - planning a treat ahead of time by borrowing its
-- extra calories/macros from the other days in the same week. This table
-- only stores the plan itself (a date, which meal it's allocated to, and
-- how much *extra* - over a normal day's share - that meal will need);
-- the actual redistribution across the week's daily targets is computed
-- client-side (`CalorieBankCalculator`), not stored, so it always reflects
-- the current goal's targets rather than a stale snapshot.
create table planned_treats (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  date date not null,
  meal_slot_id uuid references meal_slots(id) on delete set null,
  label text not null,
  extra_calories numeric not null check (extra_calories > 0),
  extra_protein_g numeric not null default 0,
  extra_carbs_g numeric not null default 0,
  extra_fat_g numeric not null default 0,
  created_at timestamptz not null default now()
);

create index planned_treats_user_date_idx on planned_treats (user_id, date);

alter table planned_treats enable row level security;

create policy "planned_treats_owner_all"
  on planned_treats for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
