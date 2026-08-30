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
*To be written once `stg_job_postings.sql` is built and tested against real
Bronze data — including the actual natural-key/dedup behavior observed, not
just the intended design.*

### Layer 3: Gold (dbt marts)
*To be written once the five marts exist and have been spot-checked against
`PKH/ingest/analyze_job_postings.py`'s current output.*

### Monitoring & alerting
*Three layers once built: job failure, staleness, quality drift — see the
plan doc for what each catches. Document what actually triggered, if
anything, the way healthkit's doc documents the real credential-staleness
incident that prompted its own alerting.*

### PKH integration
**Design decided 2026-08-30, not yet built.** Deliberately decoupled,
poll-based, not MCP: DataJobs' responsibility ends at Gold landing cleanly
— it doesn't know PKH exists. Full intended flow (evolves the existing
`/as3jobs` PKH skill into more of an agent):

`/as3jobs`-derived agent checks AS3 for new postings against the account's
already-configured occupations (lightweight check first, full scrape only
if something's new) → `ingest/upload_to_volume.py` → Bronze (this layer) →
dbt Silver/Gold (not built yet) → **PKH polls Gold on its own schedule**
via a direct SQL connector (`PKH/ingest/query_job_market_gold.py`, not yet
written, same pattern as healthkit's `check_dropped_rows.py`) → new rows
since the last poll get evaluated by `PKH/agent/job_fit_agent.py` → a
good-fit result sends an email.

Chosen over Databricks managed MCP specifically to avoid gating this on an
unconfirmed entitlement check, and because polling is the simpler
mechanism for "react to new rows on a schedule" — MCP's advantage (letting
an agent *choose* which rows to pull mid-conversation) isn't needed here.

### What's not automated
*Write this honestly once real gaps are known — likely candidates already
flagged in the plan: cross-source dedup (same job via LinkedIn directly vs.
via an AS3 crawl of LinkedIn, under different IDs), and anything Phase 0's
live checks ruled out.*
