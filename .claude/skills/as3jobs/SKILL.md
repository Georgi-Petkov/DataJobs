---
name: as3jobs
description: "Samples all currently-matching postings from the user's AS3 Job Match portal (title, company, full description, source board, date, location) via a real, interactively-logged-in Playwright browser session, and saves them to a timestamped, never-overwritten snapshot file. Trigger: /as3jobs [radius_km: N] [date_window: Last24Hours|PastWeek|Past2Weeks|PastMonth]"
---

# AS3 Jobs — Job Match postings sampler

Reproduces, as a reusable procedure, the manual scrape explored in the
2026-08-27 session against `https://portal.as3companies.com/job-match`
(originally built in PKH, moved into this repo since AS3 scraping is
DataJobs' concern end-to-end). It drives a real browser logged in as the
user, on the user's own real AS3 outplacement account. It is
**interactive by design, not a background/unattended job** — run it
yourself by typing `/as3jobs` when you want a fresh sample; there is no
scheduler here on purpose, since an unattended job can't handle a login
wall or 2FA if the session ever expires.

Unlike LinkedIn, AS3's Job Match feed is not driven by free-text search
params in a URL — the occupations it matches against (currently: business
analyst, business intelligence manager, data analyst, data quality
specialist) are a persistent setting on the user's account, configured via
AS3's own "Customise my job preferences" flow. This skill does **not**
change those occupations. It only optionally overrides radius/date-window
for a single run (see Parameters), and always leaves the account exactly as
it found it.

## Why this is safe to run unattended once invoked

- Read path (the actual scrape) is pure `GET`/`POST` calls to AS3's own
  `JobMatchApi`, paginated with a deliberate delay between pages — this
  matters because it's a real vendor's API being hit under the user's own
  authenticated session, not a public endpoint; never fire pagination
  requests back-to-back with zero delay.
- No robots.txt exists at `portal.as3companies.com` or the API host
  `portal-v1.as3companies.com` (confirmed live 2026-08-27); the only
  robots.txt on the domain is the marketing site's generic Umbraco
  boilerplate, unrelated to the portal. Moot either way since this is
  authenticated personal-account access, not anonymous crawling.
- The only mutating call (`PUT UpdateJobMatchProfile`) is used solely for
  the optional radius/date override, and is always paired with an explicit
  revert plus a verification diff before the run is reported done — see
  step 3.

## Parameters

Both optional, both override-for-this-run-only (nothing is written to a
config file — there is no meaningful "default" here beyond "whatever the
account is already configured with"):

- `radius_km` — one of `10, 25, 50, 75, 100, 150, 200, 300` (these are the
  only presets the site offers; there is no arbitrary-value radius). If the
  user asks for a value not in this list, tell them the nearest available
  options and ask which to use rather than silently rounding.
- `date_window` — one of `Last24Hours, PastWeek, Past2Weeks, PastMonth`.

If neither is given, skip step 3 entirely and just read whatever the
account's Job Match profile is currently configured with (zero mutation,
pure read — the default and preferred mode).

## Procedure

1. **Confirm the browser session is really logged in as the user.** Using
   the Playwright MCP tools, navigate to
   `https://portal.as3companies.com/job-match` and take a snapshot. Confirm
   it shows the real Job Match page (a "GP" avatar top-right, an "X
   positions found" line) rather than a login wall. If not authenticated,
   **stop and ask the user to log in manually in the browser window** —
   never attempt to enter credentials, solve a CAPTCHA, or bypass 2FA
   yourself.

2. **If no overrides were requested, skip to step 4.**

3. **Apply overrides, scrape, then revert — all in one run, no mid-way
   approval needed:**
   a. Fetch the current profile via
      `GET https://portal-v1.as3companies.com/umbraco/api/JobMatchApi/GetJobMatchProfile?language=en`
      (via `browser_evaluate`, `credentials: 'include'`) and save the
      current `GeoSettings.RadiusKm` and `ProfileFilters.DateFilter` values
      in memory — this is what gets restored at the end.
   b. For a radius override: click the radius dropdown button on the
      Job Match page, select the requested km option.
   c. For a date_window override: open the "Filters" panel, click the
      matching "Posted date" button (`Last 24 hours` / `Past week` /
      `Past 2 weeks` / `Past month`), then click "Search" to apply.
   d. Run the full scrape (step 4).
   e. Revert: repeat (b)/(c) with the original values captured in (a), and
      click Search again.
   f. Verify: fetch `GetJobMatchProfile` once more and diff it against the
      snapshot from (a), ignoring only `JobMatchPageLastVisited` (which
      always changes). If anything else differs, **stop and tell the user
      explicitly** rather than reporting success — do not assume the revert
      worked without checking.

4. **Paginated scrape**, via `browser_evaluate` calling AS3's own API
   directly (`credentials: 'include'`, no extra auth needed — same session
   cookie the logged-in page already has):
   ```js
   POST https://portal-v1.as3companies.com/umbraco/api/JobMatchApi/GetMatchesForProfile
   body: {"Limit": 50, "Offset": <N>, "Order": "DateDescending"}
   ```
   Start at `Offset: 0`, read `TotalResults` from the first response, then
   keep incrementing `Offset` by 50 until all results are collected.
   **Wait at least `page_delay_seconds` (from `config.json`, default 1.5s)
   between each page request** — do this as separate sequential
   `browser_evaluate` calls (or an explicit `await new
   Promise(r=>setTimeout(r, delay))` between fetches inside one script), not
   a tight zero-delay loop.

5. **For each result, capture:**
   - `id` — AS3's own `Id`
   - `title` — `Jobtitle`
   - `company` — `Company.Name`
   - `description` — `Text` (the full job description, several KB per
     posting — this is why the API is used directly instead of clicking
     through 200+ individual cards)
   - `url` — `Url`
   - `source` — `Source` (e.g. `"www.linkedin.dk (Crawler)"`,
     `"www.jobbank.dk (Crawler)"`, `"www.Jobindex.dk"` — useful downstream
     for a LinkedIn-vs-other-boards split, as done manually 2026-08-27)
   - `date` — `FormattedDate`
   - `location` — `Location`
   - `level` — `Level`
   - `as3_job_id` — `JobId` (AS3's pointer to the original board's own
     posting id, distinct from AS3's internal `Id`)

   Do **not** filter, dedupe, or drop anything here — including postings
   that look like duplicates of each other (the same role legitimately
   appears under multiple `source` values when more than one job board
   crawled the same original listing; a real example from 2026-08-27:
   DSV's "Business Integration Manager" showed up via both jobbank.dk and
   Jobindex.dk). Note the apparent-duplicate count in the final report, but
   leave deduplication to a downstream step — never invent a dedup
   heuristic here. (The real downstream dedup lives in
   `dbt/datajobs/models/staging/stg_job_postings.sql`, keyed on
   `as3_job_id`, once a snapshot has been uploaded and ingested.)

6. **Save, never overwriting:**
   - Target path: `data/as3_jobs_scan/<YYYY-MM-DD>.json` (today's date).
   - If a file for today already exists, do **not** touch it — write to
     `data/as3_jobs_scan/<YYYY-MM-DD>_<HHMM>.json` instead.
   - Write the JSON array (flat list of postings, indent=2) via the Write
     tool. This directory is gitignored — never remove it from
     `.gitignore`, this repo is public.

7. **Stop there.** Report to the user: total postings collected, the
   LinkedIn-vs-other-sources split, the apparent-duplicate count (by
   title+company across different sources), whether an override was
   applied and successfully reverted (if step 3 ran), and the file path
   written. Do not analyze, score, or summarize the postings themselves —
   uploading (`ingest/upload_to_volume.py`) and analysis (the
   Bronze→Silver→Gold pipeline, or ad hoc queries against
   `workspace.datajobs_gold.*`) are separate, later steps.
