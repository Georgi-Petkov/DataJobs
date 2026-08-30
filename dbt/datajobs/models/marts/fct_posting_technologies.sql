-- Technology/tool mentions per posting, as an ARRAY<STRING> column rather
-- than one column per term -- a fixed wide table doesn't fit "each posting
-- mentions a lot of terms, and the term list itself keeps growing." This
-- stays a real Delta table (queryable, versioned, joinable) while keeping
-- the variable-length-list shape the data actually has; explode() turns it
-- into a frequency table on demand (see the interview-question-style
-- example in PIPELINE_ARCHITECTURE.md once written).
--
-- seeds/technology_terms.csv is a starting list, not a closed one --
-- "emerging technology" tracking means this needs ongoing curation, not a
-- one-time fixed pattern set. Postings matching zero terms don't appear
-- here at all (inner join + group by) -- that's deliberate, this mart is
-- specifically about technology mentions.

with postings as (

    select
        external_job_id,
        source_platform,
        title,
        description,
        scraped_date
    from {{ ref('stg_job_postings') }}

),

terms as (

    select canonical_term, match_pattern
    from {{ ref('technology_terms') }}

),

matches as (

    select distinct
        p.external_job_id,
        p.source_platform,
        p.scraped_date,
        t.canonical_term
    from postings p
    inner join terms t
        on lower(p.title || ' ' || p.description) rlike t.match_pattern

)

select
    external_job_id,
    source_platform,
    scraped_date,
    collect_list(canonical_term) as mentioned_technologies,
    size(collect_list(canonical_term)) as technology_mention_count
from matches
group by external_job_id, source_platform, scraped_date
