-- Time intelligence: which employer posted the most (data-adjacent) jobs
-- in a given month, sliceable by job_category. Grain is
-- (employer, posted_month, job_category) -- roll up further with SUM() in
-- a query, e.g.:
--   select employer, sum(posting_count)
--   from fct_company_posting_trends
--   where posted_month = '2026-08-01'
--   group by employer order by 2 desc
--
-- Based on posted_date (when AS3 says the job went live), not
-- scraped_date (when we captured it) -- "posted the most jobs in August"
-- is a posted_date question. Rows with a null posted_date (unparseable
-- date string) are excluded rather than silently bucketed into some
-- default month.

select
    employer,
    date_trunc('month', posted_date) as posted_month,
    job_category,
    count(*) as posting_count
from {{ ref('stg_job_postings') }}
where posted_date is not null
group by employer, date_trunc('month', posted_date), job_category
