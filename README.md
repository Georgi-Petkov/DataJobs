# DataJobs

Bronze/Silver/Gold data pipeline over your own job-search data (AS3 outplacement
portal + LinkedIn), built to practice Databricks Lakeflow + dbt + Terraform,
and to actually drive real job-search decisions by feeding a Gold layer back
into [PKH](../PKH) (your personal knowledge graph / job-fit agent).

**Status: scaffolding only — Phase 0 live-checks not yet run.** Nothing here
is deployed. See [`../.claude/plans/i-want-to-plan-silly-wand.md`](/Users/g/.claude/plans/i-want-to-plan-silly-wand.md)
for the full phased plan this repo is being built from.

```
AS3 outplacement portal          LinkedIn
        │  /as3jobs skill (PKH,          │  manual scrape,
        │  interactive, manual)          │  interactive, manual
        ▼                                ▼
   PKH/data/as3_jobs_scan/*.json    PKH/data/linkedin_jobs_scan/*.json
        │
        │  ingest/upload_to_volume.py (manual/light-scheduled)
        ▼
   Unity Catalog Volume (landing)
        │  Auto Loader (cloudFiles), inside a Lakeflow Declarative Pipeline
        ▼
BRONZE   bronze_as3_raw / bronze_linkedin_raw   (Delta, Unity Catalog)
        │  dbt — schema reconciliation + dedup + augment
        ▼
SILVER   stg_job_postings  (+ job_postings_snapshot for change history)
        │  dbt (gold marts)
        ▼
GOLD     fct_skill_demand_trend / fct_salary_by_skill /
         fct_source_category_trends / fct_language_requirement_gaps /
         fct_posting_freshness
        │  Databricks managed MCP (or a direct SQL fallback)
        ▼
   PKH/agent/job_fit_agent.py — live market context per job-fit assessment
```

## Layout

- `databricks/datajobs_pipeline/` — the Lakeflow Declarative Pipeline: Auto
  Loader ingestion from the landing Volume into raw Bronze tables. Deliberately
  minimal — no flatten, no dedup here; that's dbt's job.
- `ingest/` — the source contract raw JSON must follow, notes on the two
  existing manual scraping processes (AS3, LinkedIn — both stay manual by
  design), and the script that lands already-scraped local JSON into the
  Unity Catalog Volume.
- `dbt/datajobs/` — Silver (clean/dedup/augment) and Gold marts.
- `terraform/` — manages the Lakeflow pipeline, the Silver→Gold job, a
  freshness alert, and a Lakehouse Monitoring quality monitor, as code.
- `PKH_INTEGRATION.md` — how Gold gets exposed to PKH, and why.

## Why this exists

Two things drove this project — see the plan doc for the full reasoning:

1. **Cert-prep hands-on reps** on Databricks Lakeflow + Terraform, building
   on a pattern already designed once (for [`healthkit-medallion-pipeline`](../healthkit-medallion-pipeline))
   but never actually deployed.
2. **Real job-search value** — turning ad hoc, print-to-stdout job-market
   analysis already living in `PKH/ingest/analyze_job_postings.py` into
   persisted, queryable Gold tables that can actually inform decisions.
