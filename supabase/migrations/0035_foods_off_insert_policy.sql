-- A barcode lookup that misses the local catalog but hits Open Food Facts
-- inserts a new SHARED row (is_custom = false, source = 'off', no owner) -
-- unlike a user's own custom food, this isn't owned by whoever scanned it,
-- so the existing "insert your own custom food" policy (is_custom = true
-- and created_by = auth.uid()) doesn't cover it. Any authenticated user can
-- add one of these; that's the intended crowd-sourced-growth behavior,
-- mirroring how MFP's own food database grows.
create policy "foods_insert_off_lookup"
  on foods for insert
  with check (is_custom = false and source = 'off');
