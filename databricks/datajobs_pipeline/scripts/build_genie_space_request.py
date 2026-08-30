#!/usr/bin/env python3
"""Builds the request body for creating the DataJobs Genie space.

Writes JSON to stdout -- pipe into a file, then POST it:
    python3 build_genie_space_request.py > /tmp/genie_space_request.json
    databricks api post /api/2.0/genie/spaces --profile datajobs --json @/tmp/genie_space_request.json

Structure confirmed against the real, live healthkit Genie space
(workspace.healthkit's serialized_space, fetched via GET
/api/2.0/genie/spaces/<id>?include_serialized_space=true) rather than
guessed from docs alone -- serialized_space is a JSON *string* nested
inside the outer request body, not a nested object.
"""
import json
import uuid


def new_id() -> str:
    """Lowercase 32-hex UUID without hyphens -- the exact format the Genie
    API requires for every instruction/benchmark_question id, confirmed by
    a real "id must be provided and non-empty" error on the first attempt.
    """
    return uuid.uuid4().hex

TABLES = sorted([
    "workspace.datajobs.bronze_as3_raw",
    "workspace.datajobs_silver.stg_job_postings",
    "workspace.datajobs_gold.fct_postings_for_evaluation",
    "workspace.datajobs_gold.fct_postings_with_salary",
    "workspace.datajobs_gold.fct_posting_technologies",
    "workspace.datajobs_gold.fct_company_posting_trends",
])
# The Genie API requires data_sources.tables sorted by identifier --
# genie_freshness_gate.sh does the same (jq 'sort_by(.identifier)') before
# every write, which is this exact requirement, not just its own
# comparison convenience.

INSTRUCTIONS = [
    "* This data covers AS3 Job Match postings only (source_platform is always"
    " 'as3'). origin_site distinguishes the underlying board AS3 crawled the"
    " posting from (e.g. linkedin.dk, jobbank.dk, Jobindex.dk, indeed.com) --"
    " that is a different concept from source_platform.\n",

    "* job_category has exactly 6 values: data_analyst, data_engineer,"
    " data_scientist, business_intelligence, ai_engineer, or other. 'other'"
    " does NOT mean irrelevant -- it means the posting mentions 'data' and"
    " passed relevance filtering but didn't match one of the 5 named"
    " categories. Never treat 'other' as noise to exclude by default.\n",

    "* fct_postings_with_salary is NOT an exhaustive salary dataset -- most"
    " postings simply don't disclose a salary at all (a known, confirmed"
    " market pattern for this region), and salary_range_raw is the matched"
    " TEXT SNIPPET, not a parsed number -- never cast it or do arithmetic on"
    " it directly. If asked for salary statistics (average, min, max), say"
    " this table only supports listing which postings disclosed a range, not"
    " numeric aggregation, rather than attempting to parse salary_range_raw.\n",

    "* fct_posting_technologies.mentioned_technologies is an array of"
    " canonical terms from a curated, growing seed list -- a technology"
    " being absent from a posting's array means it wasn't in the seed list"
    " OR wasn't mentioned, not necessarily the latter. Don't claim a posting"
    " 'doesn't require Python' just because 'python' is missing from its"
    " array without noting that caveat.\n",

    "* For any 'when was X posted' or trend/time-series question, use"
    " posted_date (what AS3 reports as the posting's publish date), not"
    " scraped_date (when this pipeline happened to capture it) -- those"
    " answer different questions and are easy to conflate.\n",

    "* The company name column is called 'employer' in every table here, not"
    " 'company'.\n",
]

BENCHMARK_QUESTIONS = [
    {
        "question": ["Which employer posted the most data jobs last month?"],
        "sql": [
            "SELECT employer, SUM(posting_count) AS n FROM "
            "workspace.datajobs_gold.fct_company_posting_trends "
            "WHERE posted_month = date_trunc('month', add_months(current_date(), -1)) "
            "GROUP BY employer ORDER BY n DESC LIMIT 10"
        ],
    },
    {
        "question": ["Which postings mention both Databricks and Python?"],
        "sql": [
            "SELECT external_job_id, title, employer, mentioned_technologies FROM "
            "workspace.datajobs_gold.fct_posting_technologies "
            "WHERE array_contains(mentioned_technologies, 'databricks') "
            "AND array_contains(mentioned_technologies, 'python')"
        ],
    },
]

serialized_space = {
    "version": 2,
    "data_sources": {"tables": [{"identifier": t} for t in TABLES]},
    "instructions": {
        "text_instructions": [
            {"id": new_id(), "content": INSTRUCTIONS}
        ]
    },
    "benchmarks": {
        "questions": [
            {
                "id": new_id(),
                "question": q["question"],
                "answer": [{"format": "SQL", "content": q["sql"]}],
            }
            for q in BENCHMARK_QUESTIONS
        ]
    },
}

request_body = {
    "warehouse_id": "9331fd1235b63aa4",
    "title": "DataJobs Pipeline",
    "description": "Genie space for the DataJobs job-market data pipeline (AS3 postings, Bronze/Silver/Gold).",
    "serialized_space": json.dumps(serialized_space),
}

print(json.dumps(request_body, indent=2))
