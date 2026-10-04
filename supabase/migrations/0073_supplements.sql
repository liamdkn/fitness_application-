-- Supplements: what you take, how much, and a log of each time you took it.
--
-- A supplement is taken `servings_per_day` times a day; each serving is
-- `amount_per_serving` of its unit (1 scoop, 2 capsules). A scoop can carry a
-- weight (`scoop_size_g`) so a goal reads in grams too (creatine: 1 scoop of
-- 5 g). `supplement_overrides` changes the servings or amount for one date,
-- e.g. a loading day. `reminder_times` are minutes after midnight; empty
-- means no reminder.

create table supplements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  unit text not null default 'serving'
    check (unit in ('serving', 'scoop', 'capsule', 'tablet', 'softgel', 'drop', 'g', 'mg', 'ml')),
  amount_per_serving numeric(8, 2) not null default 1 check (amount_per_serving > 0 and amount_per_serving <= 1000),
  scoop_size_g numeric(6, 2) check (scoop_size_g is null or (scoop_size_g > 0 and scoop_size_g <= 500)),
  servings_per_day int not null default 1 check (servings_per_day between 1 and 12),
  reminder_times int[] not null default '{}'
    check (coalesce(array_length(reminder_times, 1), 0) <= 8),
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create index supplements_user_idx on supplements (user_id, sort_order);

alter table supplements enable row level security;
create policy "supplements_owner_all" on supplements for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create table supplement_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  supplement_id uuid not null references supplements(id) on delete cascade,
  date date not null,
  servings_per_day int check (servings_per_day is null or servings_per_day between 0 and 12),
  amount_per_serving numeric(8, 2) check (amount_per_serving is null or (amount_per_serving > 0 and amount_per_serving <= 1000)),
  unique (supplement_id, date)
);

alter table supplement_overrides enable row level security;
create policy "supplement_overrides_owner_all" on supplement_overrides for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create table supplement_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  supplement_id uuid not null references supplements(id) on delete cascade,
  date date not null,
  amount numeric(8, 2) not null check (amount > 0 and amount <= 1000),
  taken_at timestamptz not null default now()
);

create index supplement_logs_user_date_idx on supplement_logs (user_id, date);

alter table supplement_logs enable row level security;
create policy "supplement_logs_owner_all" on supplement_logs for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
