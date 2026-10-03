-- Let a user keep their own corrected copy of a scanned product.
--
-- A barcode scan inserts a shared Open Food Facts row that nobody can edit
-- (RLS only lets people update their own custom foods). When the scanned
-- numbers don't match the pack's label, the fix is a personal copy carrying
-- the same barcode - which the old table-wide UNIQUE (barcode) forbade.
-- Uniqueness now holds per scope instead: one shared row per barcode, and
-- one personal row per barcode per user. The scan lookup prefers the
-- personal copy (see FoodRepository.fetchByBarcode).
alter table foods drop constraint foods_barcode_key;

create unique index foods_barcode_shared_idx
  on foods (barcode)
  where is_custom = false and barcode is not null;

create unique index foods_barcode_custom_idx
  on foods (created_by, barcode)
  where is_custom = true and barcode is not null;
