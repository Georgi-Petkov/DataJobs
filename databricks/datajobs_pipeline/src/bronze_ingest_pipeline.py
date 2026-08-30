"""Bronze ingestion: lands raw scraped job-posting JSON via Auto Loader.
Deliberately minimal -- no flatten, no dedup, no schema reconciliation
here; that's dbt's job (Silver, Phase 4).

AS3 only for now -- its own `source` field already aggregates LinkedIn,
jobbank.dk, Jobindex.dk, Indeed, jobnet.dk, etc., so a separate LinkedIn
ingestion path would be redundant. `_bronze_source_table` stays
parameterized by source_platform anyway: adding a genuinely distinct
future source (one AS3 doesn't cover) is one more @dp.table call, copy-
pasted, nothing else changes. See ingest/source_contract.md.

Modeled on healthkit-medallion-pipeline's healthkit_silver_pipeline.py
stage 1 (bronze_healthkit_raw) -- same Autoloader/cloudFiles shape, proven
to work on this workspace's serverless compute by the Phase 0 spike.
"""
from pyspark import pipelines as dp
from pyspark.sql import functions as F

# IDE-only: `spark` is already injected as a global by the Databricks
# Lakeflow runtime at execution time -- this import does nothing there,
# it just gives local editors/linters something to resolve `spark` against.
from databricks.sdk.runtime import spark

LANDING_ROOT = "/Volumes/workspace/datajobs/landing"
SCHEMA_LOCATION_ROOT = f"{LANDING_ROOT}/_autoloader_schema"


def _bronze_source_table(source_platform: str):
    """Autoloader read for one source's raw JSON, tagged with source_platform.

    Confirmed empirically (2026-08-30, real AS3 data): cloudFiles' JSON
    reader parses a top-level JSON array into one row per array element,
    not one row per file -- 3 uploaded files (25 + 212 + 28 records) landed
    as 265 Bronze rows. Bronze is already one row per posting.
    """
    return (
        spark.readStream.format("cloudFiles")
        .option("cloudFiles.format", "json")
        .option("cloudFiles.schemaLocation", f"{SCHEMA_LOCATION_ROOT}/{source_platform}/")
        .option("cloudFiles.inferColumnTypes", "true")
        .option("multiLine", "true")
        .load(f"{LANDING_ROOT}/{source_platform}/")
        .withColumn("source_platform", F.lit(source_platform))
        .withColumn("source_file", F.col("_metadata.file_path"))
        .withColumn("file_modification_time", F.col("_metadata.file_modification_time"))
    )


@dp.table(
    name="bronze_as3_raw",
    comment="Raw AS3 Job Match postings via Autoloader, one row per posting. See ingest/source_contract.md for the shape.",
)
def bronze_as3_raw():
    return _bronze_source_table("as3")
