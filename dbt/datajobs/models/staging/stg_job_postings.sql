-- Bronze -> Silver. AS3 only for now (see ingest/source_contract.md).
--
-- Classification rule and keep/drop filter below were tuned interactively
-- against the real 265-row Bronze table on 2026-08-30 -- see
-- PIPELINE_ARCHITECTURE.md for the reasoning behind each judgment call
-- (why plain "Business Analyst" drops, why Product/Project/Program Manager
-- titles drop even when they mention "data", why everything else that
-- mentions "data" is kept as `other` rather than dropped).

with source as (

    select
        as3_job_id as external_job_id,
        'as3' as source_platform,
        title,
        company as employer,
        description,
        url,
        location,
        level as seniority_raw,
        source as origin_site_raw,
        to_date(date, 'd MMMM yyyy') as posted_date,
        -- scraped_date comes from the landed filename, not
        -- file_modification_time -- confirmed empirically that
        -- file_modification_time reflects when we uploaded the file
        -- (today), not when AS3 actually captured the snapshot.
        to_date(regexp_extract(source_file, '(\\d{4}-\\d{2}-\\d{2})', 1)) as scraped_date,
        source_file,
        file_modification_time as _ingested_at

    from {{ source('datajobs_bronze', 'bronze_as3_raw') }}
    where as3_job_id is not null

),

deduped as (

    select *
    from source
    qualify row_number() over (
        partition by source_platform, external_job_id
        order by _ingested_at desc, length(description) desc
    ) = 1

),

classified as (

    select
        *,
        case
            when lower(title) rlike '\\bdata\\s*(&|and)?\\s*analytics engineer\\b' then 'data_engineer'
            when lower(title) rlike '\\bdata engineer\\b' then 'data_engineer'
            when lower(title) rlike '\\banalytics engineer\\b' then 'data_engineer'
            when lower(title) rlike '\\b(ai|ml|machine learning)\\s*engineer\\b' then 'ai_engineer'
            when lower(title) rlike '\\bdata scientist\\b' then 'data_scientist'
            when lower(title) rlike 'data science' then 'data_scientist'
            when lower(title) rlike 'business intelligence' then 'business_intelligence'
            when lower(title) rlike '\\bbi\\b' then 'business_intelligence'
            when lower(title) rlike '\\bdata analyst\\b' then 'data_analyst'
            else 'other'
        end as job_category,
        -- "www.LinkedIn.dk" and "www.linkedin.dk (Crawler)" both normalize
        -- to "linkedin.dk" -- capture_method (Crawler/Direct/Websites) kept
        -- as a separate column rather than folded into origin_site.
        lower(regexp_replace(regexp_replace(origin_site_raw, '\\s*\\([^)]*\\)', ''), '^www\\.', '')) as origin_site,
        nullif(regexp_extract(origin_site_raw, '\\(([^)]+)\\)', 1), '') as capture_method

    from deduped

)

select *
from classified
where
    -- Keep every category match. For everything else ("other"), keep only
    -- if the title mentions "data" at all -- UNLESS the core role is a
    -- generic Product/Project/Program Manager function, which drops even
    -- when it mentions data (e.g. "Technical Product Manager, Data
    -- Platform" -- the function is Product Manager, "Data Platform" is
    -- just the object being managed, not a data-discipline role).
    job_category != 'other'
    or (
        lower(title) rlike '\\bdata\\b'
        and not lower(title) rlike '\\b(product|project|program)\\s+manager\\b'
    )
