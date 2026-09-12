-- Named, deliberately-curated day snapshots ("Perfect Cut Day", "Leg Day
-- Fuel") - a saved day is a full copy of every meal slot's items at save
-- time, not a live reference to saved_meals or meal_entries, so editing a
-- saved meal later never retroactively changes a saved day that happened
-- to reuse the same food, and a saved day doesn't require every meal in it
-- to also exist as its own independently-saved meal.
create table saved_days (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger saved_days_set_updated_at
  before update on saved_days
  for each row execute function set_updated_at();

alter table saved_days enable row level security;

create policy "saved_days_owner_all"
  on saved_days for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table saved_day_items (
  id uuid primary key default gen_random_uuid(),
  saved_day_id uuid not null references saved_days(id) on delete cascade,
  meal_slot_id uuid not null references meal_slots(id) on delete cascade,
  food_id uuid references foods(id),
  recipe_id uuid references recipes(id),
  quantity numeric(6, 2) not null default 1 check (quantity > 0),
  created_at timestamptz not null default now(),
  check ((food_id is null) <> (recipe_id is null))
);

create index saved_day_items_saved_day_id_idx on saved_day_items (saved_day_id);

alter table saved_day_items enable row level security;

create policy "saved_day_items_owner_all"
  on saved_day_items for all
  using (exists (
    select 1 from saved_days sd where sd.id = saved_day_items.saved_day_id and sd.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from saved_days sd where sd.id = saved_day_items.saved_day_id and sd.user_id = auth.uid()
  ));
