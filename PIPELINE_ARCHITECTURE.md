# DataJobs — Architecture & Build Log

**This is a skeleton, not a finished narrative.** Unlike `healthkit-medallion-pipeline`'s
architecture doc (written after the fact, describing a system that already
ran against real data), this one is meant to be filled in *as the build
happens* — real trade-offs, real bugs, real dead ends — the same honesty
discipline, just written concurrently instead of retrospectively. Don't
pre-fill sections with how things are supposed to work; wait until they do.

## Sections to fill in, in build order

### Live-check results (Phase 0)
- [x] **Does Auto Loader work inside a real Lakeflow Declarative Pipeline on
      this Free Edition workspace's serverless compute? YES, confirmed 2026-08-30.**
      Deployed via a Terraform-managed `databricks_pipeline` (`terraform/pipeline_spike.tf`,
      `databricks/datajobs_pipeline/src/spike_pipeline.py`) with one
      `@dp.table` reading `cloudFiles` from a Unity Catalog Volume. First
      attempt failed on a real bug, not a platform limitation:
      `cloudFiles.schemaLocation` pointed at a volume that was never created
      (`_autoloader_schema` as a sibling volume instead of a subpath inside
      the one real volume) — `UC_VOLUME_NOT_FOUND`. Fixed by nesting the
      schema location inside the existing `landing` volume; second update
      completed cleanly (`WAITING_FOR_RESOURCES` → `SETTING_UP_TABLES` →
      `RUNNING` → `COMPLETED`), and `SELECT count(*) FROM
      workspace.datajobs_spike.spike_raw` returned exactly 1 row, matching
      the one synthetic file uploaded — real data, not an empty no-op
      stream. De-risks the core architecture: Bronze ingestion can be a real
      Lakeflow pipeline, not a fallback to dbt+VARIANT-explode.
      Spike resources (`workspace.datajobs_spike` schema/volume/pipeline)
      still live — tear down once Phase 0's other checks are done.
- [~] **Downgraded, no longer blocking (2026-08-30).** Is Databricks
      managed MCP (Genie/UC Functions) entitled on this account? Moot for
      now — Phase 6 (PKH integration) was redesigned as a decoupled,
      poll-based flow (PKH queries Gold on its own schedule via a direct
      SQL connector) rather than an MCP call. Only worth checking later if
      that changes.
- [ ] Can this workspace `CREATE CATALOG`, or is it schema-in-`workspace`
      only (as in the healthkit workspace)? Currently defaulted to
      schema-in-`workspace` (`terraform/schema.tf`, schema `datajobs`)
      without testing `CREATE CATALOG` — works either way, untested.
- [ ] Is `databricks_quality_monitor` (Lakehouse Monitoring) available here?

### Layer 1: Bronze (Lakeflow + Auto Loader)
**Real, deployed, ingesting real data as of 2026-08-30.** One `@dp.table`
(`bronze_as3_raw`), Autoloader (`cloudFiles`) reading a Unity Catalog Volume
landing path (`terraform/schema.tf` + `terraform/pipeline.tf`,
`databricks/datajobs_pipeline/src/bronze_ingest_pipeline.py`). AS3 only —
LinkedIn dropped from scope, since AS3's own `source` field already
aggregates postings crawled from LinkedIn plus jobbank.dk, Jobindex.dk,
Indeed, jobnet.dk, etc.; running a separate LinkedIn ingestion path in
parallel would be redundant (see `ingest/source_contract.md` for the
known trade-off this carries: AS3's LinkedIn coverage is crawled, not the
same as a direct personalized LinkedIn search).

Real run against the 3 existing AS3 snapshots landed **265 rows** in
`bronze_as3_raw`. Notable, confirmed rather than assumed: `cloudFiles`'
JSON reader parses a top-level JSON array into one row per array element
automatically (not one row per file, the way healthkit's single-JSON-object
Bronze files worked) — so Bronze here is already one row per posting, no
explicit `explode()` needed at this layer. Two real bugs hit and fixed
along the way:
1. `cloudFiles.schemaLocation` pointed at a sibling volume that didn't
   exist rather than a subpath inside the real one — `UC_VOLUME_NOT_FOUND`
   (same class of mistake as the Phase 0 spike, made twice).
2. `databricks fs cp` doesn't auto-create the destination subdirectory
   inside a Volume the way local `cp` implicitly would — `ingest/upload_to_volume.py`
   needed an explicit `databricks fs mkdir` per source before the first
   copy.

No data-quality gates (`@dp.expect_or_drop`) here yet — deliberately, since
adding one on a guessed row shape almost produced a wrong check (see the
git history for this file if curious). Worth adding once Silver's real
requirements are known, not before.

### Layer 2: Silver (dbt — clean, dedup, augment)
**Real, built, tested as of 2026-08-30.** `dbt/datajobs/models/staging/stg_job_postings.sql`
dedups on `(source_platform, external_job_id)` via `qualify row_number()`
(same pattern as `base_healthkit_metrics.sql`), classifies each posting
into `data_analyst` / `data_engineer` / `data_scientist` /
`business_intelligence` / `ai_engineer` / `other`, and applies a keep/drop
filter tuned interactively against real title data:

- Classification and the keep/drop rule were negotiated against the real
  183 distinct titles in Bronze, not designed abstractly — see the
  conversation history for the exact back-and-forth, but the settled rule:
  keep every category match; for `other`, keep only if the title mentions
  "data" AND the core role isn't a generic Product/Project/Program Manager
  function (e.g. "Technical Product Manager, Data Platform" drops — the
  function is Product Manager, "Data Platform" is just the object managed
  — but "Business Analyst / Agile Coach, Digital, Data & IT" and "Pricing
  Specialist that turns click data into the next price" both stay, for
  consistency with the simpler rule once tested against real examples).
  Plain "Business Analyst" (no data mention) drops.
- `origin_site` normalizes AS3's own `source` field (strips `www.`, the
  `(Crawler)`/`(Direct)`/`(Websites)` suffix, and case variants —
  `www.LinkedIn.dk` and `www.linkedin.dk (Crawler)` both become
  `linkedin.dk`) into `capture_method` + `origin_site` as separate columns.
- `posted_date` parses AS3's `"27 August 2026"` string format
  (`to_date(date, 'd MMMM yyyy')`). `scraped_date` comes from the landed
  filename via `source_file`, deliberately NOT `file_modification_time` —
  confirmed empirically that `file_modification_time` reflects upload
  time (today), not the actual AS3 capture date encoded in the filename.
- `employer` (renamed from Bronze's `company`) is the column name used
  everywhere downstream.

Real result: 265 raw Bronze rows → 225 distinct postings after dedup → 51
kept after the classification/relevance filter (as of the 3-snapshot
baseline; 52 after a 4th snapshot added one new relevant posting).

### Layer 3: Gold (dbt marts)
**Real, built, tested as of 2026-08-30.** Four marts, not the original
plan's five — scope changed to match actual stated needs partway through
Phase 4:

- **`fct_postings_for_evaluation`** — thin pass-through of `stg_job_postings`,
  the PKH integration surface (see below).
- **`fct_postings_with_salary`** — postings with a disclosed salary
  *range* (not single figure). Deliberately simplified vs.
  `PKH/ingest/salary_parser.py` (presence + raw snippet only, no parsed
  min/max/currency) to avoid re-deriving its ground-truth-tested regex
  cascade in SQL. First version (leading-currency-only pattern) caught
  just 1 of 14 real currency-mentioning postings; verified against real
  text and rebuilt as 3 patterns (leading/trailing/per-number currency),
  which correctly catches all 6 genuine salary ranges in the current data
  (the other 8 currency mentions are company revenue/turnover figures or
  a single per-game payment, correctly excluded).
- **`fct_posting_technologies`** — `mentioned_technologies` as an
  `ARRAY<STRING>`, not a wide one-hot table, matched against
  `seeds/technology_terms.csv` (54 terms, a starting list meant to grow).
  Postings matching zero terms don't appear at all.
- **`fct_company_posting_trends`** — employer × posted-month ×
  job_category, answers "which employer posted the most data jobs in a
  given month" directly (based on `posted_date`, not `scraped_date`).

All four validated against real data before being trusted — see the
conversation history for the specific SQL checks run (row counts, real
title/text spot-checks) before each was considered correct, not just
"ran without error."

### Terraform + job orchestration
**Real, deployed, tested end-to-end as of 2026-08-30.** `terraform/jobs.tf`
adds a `databricks_notebook` (managed via Terraform, unlike healthkit's
equivalent notebook which was uploaded manually outside IaC) and a
`databricks_job` (`datajobs-daily-refresh`) chaining `refresh_bronze`
(`pipeline_task`) → `run_dbt_silver_gold` (`notebook_task`, `depends_on`
the first). The notebook clones the now-public
`github.com/Georgi-Petkov/DataJobs` repo fresh each run and runs
`dbt build`, using a `datajobs-dbt` Databricks secret scope (created via
CLI, not Terraform — no `databricks_secret_scope` resource used here,
matching the fact this is genuinely new ground vs. healthkit's Terraform).

First real trigger failed: `run_dbt_silver_gold` hit
`Secret does not exist with scope: datajobs-dbt and key: databricks_host`
— the secret-scope creation step had been skipped before `terraform apply`
and the first job trigger. Not a code bug; created the scope, retriggered,
both tasks succeeded. Confirmed the run was a genuine incremental test, not
a no-op: uploaded one new AS3 snapshot first, Bronze went 265→299 rows
(4 distinct files), `fct_postings_for_evaluation` went 51→52.

### Genie space
**Real, live as of 2026-08-30.** `space_id: 01f1a4863d4c1d88982f6819eb80c370`,
created via direct API call (`POST /api/2.0/genie/spaces`) since no
`databricks_genie_space` Terraform resource exists yet (confirmed via
search — this is a known gap in the provider, not something skipped).
Built by `databricks/datajobs_pipeline/scripts/build_genie_space_request.py`,
which constructs the request body in Python rather than hand-written JSON
to avoid escaping bugs in the doubly-nested `serialized_space` string.
Points at Bronze + Silver + all 4 Gold marts, with instructions grounded
in real gotchas found this session (the `other` category isn't noise;
`fct_postings_with_salary` isn't exhaustive and `salary_range_raw` is
unparsed text; `mentioned_technologies` only covers the curated seed list;
`posted_date` vs `scraped_date` mean different things; the company column
is `employer` not `company`) and two benchmark questions.

Two real API errors hit while building the request, both fixed and worth
knowing for next time:
1. `data_sources.tables must be sorted by identifier` — confirms
   `genie_freshness_gate.sh`'s `jq 'sort_by(.identifier)'` before every
   write is a real API requirement, not just that script's own comparison
   convenience (a detail that wasn't obvious just from reading it).
2. `benchmark_question.id must be provided and non-empty. Expected
   lowercase 32-hex UUID without hyphens` — every instruction block and
   benchmark question needs a client-generated ID (`uuid.uuid4().hex`);
   they are not server-assigned on creation despite existing IDs being
   visible when reading back an already-created space.

### Monitoring & alerting
Partial. One of the three planned layers is live incidentally, not by
deliberate design yet: `terraform/jobs.tf`'s `email_notifications.on_failure`
on `datajobs_daily_refresh` covers the loud-error case (a task actually
erroring — this is what caught the missing-secret-scope failure above, in
principle, though this session diagnosed it manually rather than waiting
for the email). Not yet built: the staleness alert (`databricks_alert_v2`
on a freshness signal — no `fct_posting_freshness`-equivalent mart exists,
since Phase 4's mart set changed to the 4 actually-requested marts) and the
quality-drift monitor (`databricks_quality_monitor`, live-check #4 above,
still unconfirmed on this workspace).

No `databricks_quality_monitor`/alerting layer built yet beyond the above
— see the Live-check results section for what's still open.

### PKH integration
**Design decided 2026-08-30, real as of the same day.** Deliberately
decoupled, poll-based, not MCP: DataJobs' responsibility ends at Gold
landing cleanly — it doesn't know PKH exists.

`/as3jobs` originally lived in PKH; moved into this repo (`.claude/skills/as3jobs/`)
for full separation — DataJobs now owns AS3 scraping start to finish, PKH
holds no raw job data or scraping logic at all.

Full flow: `/as3jobs` (interactive, manual) → `ingest/upload_to_volume.py`
→ Bronze → dbt Silver/Gold (all real, this layer) → **PKH polls Gold on its
own schedule** via a direct SQL connector (`PKH/ingest/query_job_market_gold.py`,
same connection pattern as healthkit's `check_dropped_rows.py`, token auth
instead of that script's `azure-cli`) → analysis / job-fit evaluation
happens on PKH's side, out of scope for this repo.

Chosen over Databricks managed MCP specifically to avoid gating this on an
unconfirmed entitlement check, and because polling is the simpler
mechanism for "react to new rows on a schedule" — MCP's advantage (letting
an agent *choose* which rows to pull mid-conversation) isn't needed here.

### What's not automated
*Write this honestly once real gaps are known — likely candidates already
flagged in the plan: cross-source dedup (same job via LinkedIn directly vs.
via an AS3 crawl of LinkedIn, under different IDs), and anything Phase 0's
live checks ruled out.*
