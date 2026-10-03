-- Meal prep: cook one batch (overnight oats, a curry, protein balls...),
-- split it into portions, eat those portions over the following days.
--
-- A prep is deliberately a one-off *snapshot*, not a reusable template: the
-- next batch of protein balls may use a different brand of chocolate or
-- peanut butter, so each prep owns its own `recipes` row (and therefore its
-- own ingredient list and cached per-portion macros). "Prep again" in the
-- app just pre-fills a new prep from an old one's ingredients; it never
-- links the two or edits the old batch.
--
-- Eating a portion is an ordinary meal_entries row pointing at the prep's
-- recipe (quantity = portions eaten), so daily totals, TDEE, the offline
-- queue etc. need no changes. Portions remaining is derived (portions minus
-- the sum of that recipe's meal_entries) rather than stored, so deleting or
-- editing a logged entry can never leave a counter out of sync.

-- Prep recipes are internal to their prep - hidden from the "My Recipes"
-- picker so every batch doesn't clutter it.
alter table recipes add column is_meal_prep boolean not null default false;

-- Ingredient weights are entered in grams then stored as a servings
-- multiplier (grams / serving size); two decimals rounds a 37g-of-a-100g
-- food badly enough to matter in a batch, so widen it.
alter table recipe_ingredients alter column quantity type numeric(12, 4);

create table meal_preps (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  -- One portion's worth: recipes.calories/macros are already per portion
  -- (batch total / portions) and recipes.serving_size is one portion's
  -- weight in grams when total_weight_g is known, else 1 'portion'.
  recipe_id uuid not null unique references recipes(id) on delete cascade,
  prepped_on date not null default current_date,
  portions numeric(6, 2) not null check (portions > 0),
  eat_within_days int not null check (eat_within_days > 0),
  -- Final (cooked) weight of the whole batch, if weighed - lets a portion
  -- be logged by the grams actually served.
  total_weight_g numeric(8, 2) check (total_weight_g > 0),
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index meal_preps_user_prepped_idx on meal_preps (user_id, prepped_on desc);

create trigger meal_preps_set_updated_at
  before update on meal_preps
  for each row execute function set_updated_at();

alter table meal_preps enable row level security;

create policy "meal_preps_owner_all"
  on meal_preps for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Remaining-portions lookups filter meal_entries by recipe.
create index meal_entries_recipe_id_idx on meal_entries (recipe_id) where recipe_id is not null;
