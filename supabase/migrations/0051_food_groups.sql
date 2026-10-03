-- Product groups: "these foods are the same thing, different brand" -
-- Fage 0% and Tesco Greek yoghurt, two peanut butters, two dark chocolates.
-- It's what lets a meal prep say "same overnight oats, new yoghurt" and
-- lets the app rank brands of one product against each other by macros.
--
-- Per-user on purpose: `foods` is a shared catalog (seed + Open Food Facts
-- rows nobody but the system can edit), so a group id on the food itself
-- would let one user's "these are equivalent" bleed into everyone's
-- catalog. A membership table keeps the correlation private to whoever
-- made it. A food sits in at most one of a user's groups.

create table food_groups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index food_groups_user_idx on food_groups (user_id);

create trigger food_groups_set_updated_at
  before update on food_groups
  for each row execute function set_updated_at();

create table food_group_members (
  group_id uuid not null references food_groups(id) on delete cascade,
  food_id uuid not null references foods(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (group_id, food_id),
  unique (user_id, food_id)
);

alter table food_groups enable row level security;
alter table food_group_members enable row level security;

create policy "food_groups_owner_all"
  on food_groups for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "food_group_members_owner_all"
  on food_group_members for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
