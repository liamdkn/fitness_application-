create table progress_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  taken_at date not null,
  storage_path text not null,
  goal_id uuid references user_goals(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index progress_photos_user_taken_at_idx on progress_photos (user_id, taken_at desc);

create trigger progress_photos_set_updated_at
  before update on progress_photos
  for each row execute function set_updated_at();

alter table progress_photos enable row level security;

create policy "progress_photos_owner_all"
  on progress_photos for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Private bucket; every object path is "{user_id}/{uuid}.jpg", enforced by
-- the policies below (never trust a client-supplied path prefix).
insert into storage.buckets (id, name, public)
values ('progress-photos', 'progress-photos', false)
on conflict (id) do nothing;

create policy "progress_photos_storage_owner_select"
  on storage.objects for select
  using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "progress_photos_storage_owner_insert"
  on storage.objects for insert
  with check (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "progress_photos_storage_owner_delete"
  on storage.objects for delete
  using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);
