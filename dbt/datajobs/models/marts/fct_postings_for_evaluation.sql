-- The PKH integration surface (see PKH_INTEGRATION.md and
-- PIPELINE_ARCHITECTURE.md's "PKH integration" section): PKH polls this
-- table on its own schedule, using scraped_date as its watermark ("new
-- since I last checked"), and runs job_fit_agent.py against whatever's
-- new. DataJobs' responsibility ends here -- it doesn't track which rows
-- PKH has already evaluated, doesn't call PKH, doesn't know PKH exists.
--
-- Deliberately NOT restricted to the 5 named categories -- stg_job_postings
-- already dropped everything irrelevant (see its own keep/drop rule);
-- postings still in `other` here were kept specifically because they
-- mention "data" and might be a genuine fit job_fit_agent.py's actual
-- judgment is better positioned to make than another SQL filter.

select
    external_job_id,
    source_platform,
    title,
    employer,
    description,
    url,
    location,
    origin_site,
    capture_method,
    seniority_raw,
    job_category,
    language_guess,
    posted_date,
    scraped_date
from {{ ref('stg_job_postings') }}
