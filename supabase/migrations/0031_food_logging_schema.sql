-- Foundation for in-house per-meal food logging (replacing the
-- MyFitnessPal-daily-total placeholder in nutrition_logs). See the
-- "Nutrition Rebuild + Apple Health/Watch Integration" audit for the full
-- design; this migration is step 1 of that punch list: schema + the
-- nutrition_source switch, no new UI yet. nutrition_logs is NOT touched or
-- removed - it stays the source of truth for the healthkit_manual path and
-- for historical trend data from before any user's cutover date.
create extension if not exists pg_trgm;

-- Food catalog: shared reference rows (is_custom = false, source 'seed' or
-- 'off') plus per-user custom foods (is_custom = true, source 'user',
-- created_by = owner) - exactly the exercises/is_custom pattern already
-- used for the exercise catalog.
create table foods (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  brand text,
  serving_size numeric(8, 2) not null check (serving_size > 0),
  serving_unit text not null,
  calories numeric(7, 2) not null check (calories >= 0),
  protein_g numeric(6, 2) not null default 0 check (protein_g >= 0),
  carbs_g numeric(6, 2) not null default 0 check (carbs_g >= 0),
  fat_g numeric(6, 2) not null default 0 check (fat_g >= 0),
  fiber_g numeric(6, 2) check (fiber_g >= 0),
  barcode text unique,
  source text not null default 'user' check (source in ('seed', 'off', 'user')),
  is_custom boolean not null default false,
  created_by uuid references auth.users(id),
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index foods_name_trgm_idx on foods using gin (name gin_trgm_ops);

create trigger foods_set_updated_at
  before update on foods
  for each row execute function set_updated_at();

alter table foods enable row level security;

create policy "foods_select_catalog_or_own"
  on foods for select
  using (is_custom = false or created_by = auth.uid());

create policy "foods_insert_own_custom"
  on foods for insert
  with check (is_custom = true and created_by = auth.uid());

create policy "foods_update_own_custom"
  on foods for update
  using (is_custom = true and created_by = auth.uid());

create policy "foods_delete_own_custom"
  on foods for delete
  using (is_custom = true and created_by = auth.uid());

-- Recipes are a named, saveable food composed of other foods - logged into
-- a meal slot like a single food (see meal_entries below). Macro totals are
-- computed client-side from recipe_ingredients and cached here rather than
-- computed live on every read, matching the cached-aggregate pattern
-- muscle_group_weekly_volume already uses elsewhere in this schema.
create table recipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  serving_size numeric(8, 2) not null default 1 check (serving_size > 0),
  serving_unit text not null default 'serving',
  calories numeric(7, 2) not null default 0,
  protein_g numeric(6, 2) not null default 0,
  carbs_g numeric(6, 2) not null default 0,
  fat_g numeric(6, 2) not null default 0,
  fiber_g numeric(6, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger recipes_set_updated_at
  before update on recipes
  for each row execute function set_updated_at();

alter table recipes enable row level security;

create policy "recipes_owner_all"
  on recipes for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipes(id) on delete cascade,
  food_id uuid not null references foods(id),
  quantity numeric(6, 2) not null check (quantity > 0),
  created_at timestamptz not null default now()
);

create index recipe_ingredients_recipe_id_idx on recipe_ingredients (recipe_id);

alter table recipe_ingredients enable row level security;

create policy "recipe_ingredients_owner_all"
  on recipe_ingredients for all
  using (exists (
    select 1 from recipes r where r.id = recipe_ingredients.recipe_id and r.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from recipes r where r.id = recipe_ingredients.recipe_id and r.user_id = auth.uid()
  ));

-- A user's configured meals-per-day (e.g. Preworkout/Breakfast/Lunch/
-- Dinner/Snacks) - a real per-user table, not a hardcoded enum, so the
-- count and names are actually editable. sort_order controls display
-- order and doubles as the per-user uniqueness key so reordering is a
-- simple renumbering rather than a separate position table.
create table meal_slots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  sort_order int not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, sort_order)
);

create trigger meal_slots_set_updated_at
  before update on meal_slots
  for each row execute function set_updated_at();

alter table meal_slots enable row level security;

create policy "meal_slots_owner_all"
  on meal_slots for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- The real per-meal log: one row per food (or recipe) logged into a meal
-- slot on a day. Daily nutrition totals become a live sum over this table
-- rather than a separately-maintained aggregate row, unlike the legacy
-- nutrition_logs table this sits alongside.
create table meal_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  date date not null,
  meal_slot_id uuid not null references meal_slots(id) on delete cascade,
  food_id uuid references foods(id),
  recipe_id uuid references recipes(id),
  quantity numeric(6, 2) not null default 1 check (quantity > 0),
  logged_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((food_id is null) <> (recipe_id is null))
);

create index meal_entries_user_date_idx on meal_entries (user_id, date);

create trigger meal_entries_set_updated_at
  before update on meal_entries
  for each row execute function set_updated_at();

alter table meal_entries enable row level security;

create policy "meal_entries_owner_all"
  on meal_entries for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- A saved snapshot of a meal's contents (e.g. "my usual breakfast") that
-- can be re-applied to any day/slot in one action - "repeat day" itself
-- doesn't need its own table, it's just a bulk-copy of meal_entries rows
-- from one date to another, or from a saved_meal's items onto a date.
create table saved_meals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger saved_meals_set_updated_at
  before update on saved_meals
  for each row execute function set_updated_at();

alter table saved_meals enable row level security;

create policy "saved_meals_owner_all"
  on saved_meals for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table saved_meal_items (
  id uuid primary key default gen_random_uuid(),
  saved_meal_id uuid not null references saved_meals(id) on delete cascade,
  food_id uuid references foods(id),
  recipe_id uuid references recipes(id),
  quantity numeric(6, 2) not null default 1 check (quantity > 0),
  created_at timestamptz not null default now(),
  check ((food_id is null) <> (recipe_id is null))
);

create index saved_meal_items_saved_meal_id_idx on saved_meal_items (saved_meal_id);

alter table saved_meal_items enable row level security;

create policy "saved_meal_items_owner_all"
  on saved_meal_items for all
  using (exists (
    select 1 from saved_meals sm where sm.id = saved_meal_items.saved_meal_id and sm.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from saved_meals sm where sm.id = saved_meal_items.saved_meal_id and sm.user_id = auth.uid()
  ));

-- Fiber target, same treatment as the existing protein/carbs/fat targets.
alter table user_goals add column fiber_g_target numeric(6, 2);

-- The in_house/healthkit_manual switch (see HealthSyncService gating).
-- Defaults to healthkit_manual - today's behavior - so this migration
-- alone doesn't cut off anyone's existing HealthKit nutrition sync before
-- the in-house meal-logging UI actually exists to replace it. The cutover
-- to 'in_house' is a deliberate later action once that UI ships.
alter table user_preferences
  add column nutrition_source text not null default 'healthkit_manual'
  check (nutrition_source in ('in_house', 'healthkit_manual'));
