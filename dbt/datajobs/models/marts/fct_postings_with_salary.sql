-- Postings with a disclosed salary RANGE (not a single figure) in the
-- description. Deliberately simplified vs. PKH/ingest/salary_parser.py --
-- that script has K-suffix expansion + FX-to-DKK conversion, ground-truth-
-- tested against 7 real examples. Porting that faithfully to SQL risked
-- exactly the kind of subtle bug this project has caught before, so this
-- mart only does presence detection + the raw matched snippet, not
-- normalized salary_min/salary_max/currency fields.
--
-- Three currency-position patterns, tried in order (first match wins),
-- mirroring the real shapes actually found in this data on 2026-08-30 --
-- NOT guessed, verified against the 14 currency-mentioning postings in
-- stg_job_postings before this was written:
--   1. leading currency:   "DKK 800,000 - DKK 1,100,000" / "DKK584.000,00---876.000,00"
--   2. trailing currency:  "651,000 to 956,900 DKK"
--   3. per-number currency: "3520 EUR to 5280 EUR"
-- Separator allows 1-3 hyphens (real example: "---") or an en/em-dash or "to".
-- A first pass covering only pattern 1 caught just 1 of 14 real
-- currency-mentioning postings; this version catches all 6 that are
-- genuinely salary ranges (the other 8 are company revenue/turnover
-- figures or a single per-game payment, correctly not ranges at all).
--
-- Known gap, not silently glossed over: salary_range_raw is the matched
-- text, not a parsed number -- if full numeric fidelity is ever needed,
-- redo this as a dbt Python model calling salary_parser.py directly
-- rather than re-deriving its regex cascade in SQL (contingent on
-- confirming dbt Python models work on this Free Edition serverless
-- workspace -- not yet checked).

with postings as (

    select *
    from {{ ref('stg_job_postings') }}

),

with_salary_detection as (

    select
        *,
        coalesce(
            nullif(regexp_extract(description, '(DKK|USD|EUR|NOK|SEK|GBP|\\$|€|£)\\s?[\\d][\\d.,]*\\s?[Kk]?\\s*(-{1,3}|–|—|to)\\s*(DKK|USD|EUR|NOK|SEK|GBP|\\$|€|£)?\\s?[\\d][\\d.,]*\\s?[Kk]?', 0), ''),
            nullif(regexp_extract(description, '[\\d][\\d.,]*\\s?[Kk]?\\s*(-{1,3}|–|—|to)\\s*[\\d][\\d.,]*\\s?[Kk]?\\s?(DKK|USD|EUR|NOK|SEK|GBP|\\$|€|£)', 0), ''),
            nullif(regexp_extract(description, '[\\d][\\d.,]*\\s?[Kk]?\\s?(DKK|USD|EUR|NOK|SEK|GBP|\\$|€|£)\\s*(-{1,3}|–|—|to)\\s*[\\d][\\d.,]*\\s?[Kk]?\\s?(DKK|USD|EUR|NOK|SEK|GBP|\\$|€|£)', 0), '')
        ) as salary_range_raw
    from postings

)

select *
from with_salary_detection
where salary_range_raw is not null
