-- Export everything an account holds, and delete the account for good.
--
-- Both read the table list from the catalogue (every public table with a
-- `user_id` column) instead of naming tables, so tables added later are
-- covered without anyone remembering to update these.

-- export_my_data(): one JSON object, a key per table holding that table's
-- rows for the signed-in user. Runs as the caller, so row-level security
-- applies - it can only return the caller's own rows.
create or replace function export_my_data()
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  result jsonb := '{}'::jsonb;
  t record;
  rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  for t in
    select c.table_name
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
    where c.table_schema = 'public' and c.column_name = 'user_id'
    order by c.table_name
  loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.%I x where x.user_id = $1', t.table_name)
      into rows using auth.uid();
    result := result || jsonb_build_object(t.table_name, rows);
  end loop;
  -- Foods the user created themselves.
  select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) into rows
    from public.foods f where f.is_custom = true and f.created_by = auth.uid();
  result := result || jsonb_build_object('custom_foods', rows);
  return jsonb_build_object('exported_at', now(), 'user_id', auth.uid(), 'data', result);
end;
$$;

-- delete_my_account(): removes every row the signed-in user owns and finally
-- the login itself. Cannot be undone. Uploaded files can't be deleted from SQL
-- (the Storage API owns them), so the app removes those first.
-- Tables reference each other, so rows are deleted in passes: a table that
-- still has children waiting is skipped and retried on the next pass.
create or replace function delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
  t record;
  remaining text[];
  progressed boolean;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;

  select array_agg(c.table_name order by c.table_name) into remaining
  from information_schema.columns c
  join information_schema.tables tb
    on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
  where c.table_schema = 'public' and c.column_name = 'user_id';

  for pass in 1..10 loop
    exit when remaining is null or cardinality(remaining) = 0;
    progressed := false;
    for t in select unnest(remaining) as name loop
      begin
        execute format('delete from public.%I where user_id = $1', t.name) using uid;
        remaining := array_remove(remaining, t.name);
        progressed := true;
      exception when foreign_key_violation then
        null; -- something still points at these rows; try again next pass
      end;
    end loop;
    exit when not progressed;
  end loop;
  if remaining is not null and cardinality(remaining) > 0 then
    raise exception 'could not remove rows from: %', remaining;
  end if;

  delete from public.foods where created_by = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function export_my_data() from public, anon;
revoke all on function delete_my_account() from public, anon;
grant execute on function export_my_data() to authenticated;
grant execute on function delete_my_account() to authenticated;
