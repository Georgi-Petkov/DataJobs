# Bronze source contract

What every source must satisfy before it can land in the Bronze landing
Volume. Adding a new source later means satisfying this once — nothing else
about Bronze ingestion should need to change.

## Landing path

`/Volumes/workspace/datajobs/landing/<source_platform>/<original_filename>.json`

One subfolder per source, named by `source_platform` (`as3`, `linkedin`, ...
future sources). Files keep their original dated filename — never renamed,
never overwritten (matches both existing scrape processes' own convention).

## Sources: AS3 only, for now

`as3` is the only ingested source. Its own `source` field already
aggregates postings crawled from LinkedIn (`www.linkedin.dk (Crawler)`),
jobbank.dk, Jobindex.dk, Indeed, jobnet.dk, and others — a separate
`linkedin_jobs_scan` ingestion path would be largely redundant, so it's
left out rather than run in parallel.

**Known trade-off, not a blocker**: AS3's LinkedIn-origin postings are
*crawled* copies of public listings, not the same thing as a direct,
personalized LinkedIn search (`linkedin_jobs_scan`'s own `category`-scoped
results). If AS3's LinkedIn coverage ever looks thin against what a direct
search would surface, revisit — the `linkedin` shape below is kept
documented for exactly that reason, not because it's actively used.

## Raw shape

Each file is a flat JSON array of postings, exactly as the source scrape
already produces it — no reshaping before upload.

- **`as3`** (ingested): `id, title, company, description, url, source, date, location, level, as3_job_id`
  (`source` here is AS3's *own* origin-site field — not to be confused with
  `source_platform`, which is always literally `"as3"`)
- **`linkedin`** (documented, not currently ingested — see above): `category, cardText, jobId, description`

Bronze does not validate or reconcile these — it lands them as-is, one row
per file, with two Autoloader-provided columns (`source_file`,
`file_modification_time`) and one literal (`source_platform`). Schema
reconciliation into one canonical shape happens in dbt (`stg_job_postings.sql`,
Phase 4), not here.

## Natural key (for later reference, not enforced in Bronze)

- `as3`: `as3_job_id`
- `linkedin`: `jobId` (if ever revisited)

Confirmed stable and recapture-safe against real data (see the plan doc) —
`(source_platform, external_job_id)` is what Silver dedups on.

## Adding a source later

1. Land its raw JSON under a new `<source_platform>/` subfolder here, same
   flat-array-of-postings shape.
2. Add one more `@dp.table` to `bronze_ingest_pipeline.py`, copy-pasted from
   an existing one, path changed.
3. Note its natural-key field in this doc.
4. Add one more `UNION ALL` branch to `stg_job_postings.sql` (Phase 4).

Nothing else changes.
