# Spike findings: key-locked diary access

**Outcome: abandoned.** Even a real, headed Playwright-controlled Chromium
got stuck on Cloudflare's "Just a moment..." challenge indefinitely (never
resolved, unlike a genuine unautomated browser which clears it in ~5s) —
Cloudflare appears to detect the CDP automation connection itself, not just
headless mode. A stealth-patched fork (`patchright`) was a possible next
step but wasn't pursued; the MVP logs nutrition manually in the app instead.
Keeping these notes in case automated import is worth revisiting later.

Confirmed by driving a real browser against the live diary:

## Mechanism

1. `GET https://www.myfitnesspal.com/food/diary/{username}` — no login required
   at all. If the diary is locked, the page renders a "Password Required"
   form inline (a single text input + submit button) instead of redirecting
   anywhere.
2. Submitting that form (`GET /food/authenticate_diary_password?username={username}`
   with the key) unlocks the diary for the session (cookie-based) — after
   that, `GET /food/diary/{username}?date=YYYY-MM-DD` returns the full diary
   for any date without re-submitting the key.
3. **Cloudflare protects the whole site.** The first visit hits a "Just a
   moment..." JS challenge that a real browser clears in ~5s automatically,
   but a plain HTTP client (Python `requests`) won't execute that JS and will
   get stuck on the challenge page or a 403 — confirmed by testing a raw
   `fetch()` from the page itself, which was also blocked. This rules out
   the originally-planned `requests` + BeautifulSoup approach.

## Decision: use Playwright instead of `requests`

`mfp-sync` drives a real (headless) Chromium via Playwright: navigate to the
diary, fill and submit the key form if prompted, then navigate per-date and
extract the totals row. This reliably clears the Cloudflare challenge the
same way a real browser does, at the cost of a heavier dependency (~150MB+
browser binary via `playwright install chromium`) and a few extra seconds
per run — acceptable for a once-nightly job.

## Diary HTML structure (for parsing)

The daily totals live in `table#diary-table tr.total`:

```html
<tr class="total">
  <td class="first">Totals</td>
  <td>3,015</td>                                    <!-- calories -->
  <td><span class="macro-value">410</span>...</td>  <!-- carbs (g) -->
  <td><span class="macro-value">58</span>...</td>   <!-- fat (g) -->
  <td><span class="macro-value">191</span>...</td>  <!-- protein (g) -->
  <td>7,147</td>                                    <!-- sodium (mg), unused -->
  <td>92</td>                                       <!-- sugar (g), unused -->
</tr>
```

Numbers use comma thousands separators and need stripping before parsing.
