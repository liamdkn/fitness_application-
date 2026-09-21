# Food search: fallback chain + Nutritionix as the verified source

## Context (Sep 19)

Liam noticed common foods (e.g. his Ghost protein powder) don't show
up when searching in-house food logging. Root cause, confirmed in
code: `FoodPickerView`'s search only queries the local `foods` table
(`FoodRepository.search`) - there's no live external lookup on text
search today, only on barcode scan (`OpenFoodFactsService.lookup`,
barcode-only, no text search). The catalog only grows from barcode
scans and manual "New Food"/"Quick Add" entries, so anything never
scanned or typed in by hand just isn't there.

Liam confirmed: use Nutritionix as the verified-product source
(dietitian-verified data, strong on US/branded/supplement items like
Ghost - see prior message thread for the MFP-does-the-same-thing
background). Open Food Facts stays in the chain too - it's free,
no API key, and strong on UK/Irish grocery own-brand products
specifically, which is most of his day-to-day Tesco/Aldi shop.

## 1. Schema change

`foods.source` has a check constraint limited to `('seed', 'off',
'user')` (migration `0031_food_logging_schema.sql`). New migration
needed to widen it:

```sql
alter table foods drop constraint foods_source_check;
alter table foods add constraint foods_source_check
  check (source in ('seed', 'off', 'nutritionix', 'user', 'ocr'));
```

(`'ocr'` included here for `docs/nutrition-label-scan-brief.md`, the
companion feature - add both now rather than two migrations.)

## 2. Nutritionix integration

New `NutritionixService.swift`, same shape as the existing
`OpenFoodFactsService.swift`:
- Nutritionix's Natural Language / Instant Search endpoint for text
  search (`/v2/search/instant` - branded results specifically, which
  is what's needed here), and their `/v2/natural/nutrients` or item
  endpoint for full macro detail on a selected result.
- Needs an API key (App ID + App Key, free tier: 200 calls/day) -
  store in whatever config/secrets pattern the app already uses for
  other keys (check if one exists; if not, this is the first one -
  flag that as its own small setup step).
- Free-tier cap (200 calls/day) is a single-user non-issue for daily
  logging, but the API requires attribution per their free-tier
  terms - a small "Nutrition data from Nutritionix" credit somewhere
  reasonable (e.g. Settings or the food detail view) covers that.
- On a picked Nutritionix result: insert into `foods` with
  `source: "nutritionix"`, `is_verified: true` (this is the one
  source where auto-setting `is_verified = true` is justified -
  Nutritionix's own dietitian-review process backs it, unlike OFF's
  crowdsourced entries or a user's own manual add). `is_verified` is
  already a column on `Food`/already modeled in Swift - currently
  set nowhere in the app, this is its first real use.

## 3. Search fallback chain

`FoodRepository.search` currently only hits the local table. New
order when local search comes back empty (or, arguably, always run
in parallel and merge - simpler to ship local-first, external-if-
empty, and revisit merging if local search alone still misses things
often once Nutritionix results start getting cached locally):

1. Local `foods` table (existing, unchanged, always instant).
2. If empty: Nutritionix instant search (branded/supplement-strong).
3. If still empty: Open Food Facts text search (OFF has a real
   search API too, not just barcode lookup today's code only uses -
   `world.openfoodfacts.org` `/cgi/search.pl` or the v2 search
   endpoint with `search_terms`) - strong on UK/IE grocery own-brand.
4. Still nothing: existing "No matches - try a different search, or
   add a new food" fallback to manual/Quick Add, unchanged.

Any result picked from 2 or 3 gets inserted into `foods` on first use
(same cache-on-first-pick pattern `insertFromOpenFoodFacts` already
does for barcode hits) so the second time anyone searches that item
it's a fast local hit with no repeat API call.

## 4. Not in this pass

- Merging/ranking results across all three sources in one list -
  starting with try-in-order (cheaper, simpler, and local-first
  already covers anything used before) rather than parallel-fetch-
  and-merge. Revisit if local-first ordering feels wrong in practice.
- Tesco/Aldi scraping - parked per the earlier discussion; ship this
  fallback chain first and see how much of a gap remains before
  taking on that scope/ToS risk.
