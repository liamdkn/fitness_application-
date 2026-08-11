create table body_weight_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  logged_at timestamptz not null default now(),
  weight_kg numeric(6, 2) not null check (weight_kg > 0),
  source text not null default 'manual' check (source in ('manual', 'healthkit')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index body_weight_logs_user_logged_at_idx on body_weight_logs (user_id, logged_at desc);

create trigger body_weight_logs_set_updated_at
  before update on body_weight_logs
  for each row execute function set_updated_at();

alter table body_weight_logs enable row level security;

create policy "body_weight_logs_owner_all"
  on body_weight_logs for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table nutrition_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  date date not null,
  calories numeric(7, 1) not null check (calories >= 0),
  protein_g numeric(6, 1) not null check (protein_g >= 0),
  carbs_g numeric(6, 1) not null check (carbs_g >= 0),
  fat_g numeric(6, 1) not null check (fat_g >= 0),
  source text not null default 'myfitnesspal',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, date)
);

create trigger nutrition_logs_set_updated_at
  before update on nutrition_logs
  for each row execute function set_updated_at();

alter table nutrition_logs enable row level security;

create policy "nutrition_logs_owner_all"
  on nutrition_logs for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table sleep_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  date date not null,
  total_sleep_minutes int not null check (total_sleep_minutes >= 0),
  in_bed_minutes int check (in_bed_minutes >= 0),
  source text not null default 'healthkit',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, date)
);

create trigger sleep_logs_set_updated_at
  before update on sleep_logs
  for each row execute function set_updated_at();

alter table sleep_logs enable row level security;

create policy "sleep_logs_owner_all"
  on sleep_logs for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table step_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  date date not null,
  step_count int not null check (step_count >= 0),
  source text not null default 'healthkit',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, date)
);

create trigger step_logs_set_updated_at
  before update on step_logs
  for each row execute function set_updated_at();

alter table step_logs enable row level security;

create policy "step_logs_owner_all"
  on step_logs for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
