"""Phase 0 live-check spike -- NOT part of the real pipeline.

Question this answers: does Auto Loader (`cloudFiles`) actually run --
not just validate -- inside a real Lakeflow Declarative Pipeline on this
Free Edition workspace's serverless compute? This was NOT true when
healthkit-medallion-pipeline was rebuilt in July 2026 (see that repo's
PIPELINE_ARCHITECTURE.md); current docs say it now is, but that's
unconfirmed on this specific account.

Delete this file, terraform/pipeline_spike.tf, and the spike schema/volume
it creates once the question is answered either way.
"""
from pyspark import pipelines as dp

# IDE-only: `spark` is injected as a global by the Databricks Lakeflow
# runtime at execution time -- this import is a no-op there, it just gives
# local editors/linters something to resolve `spark` against.
from databricks.sdk.runtime import spark

# Populated by terraform/pipeline_spike.tf's databricks_volume resource.
LANDING_PATH = "/Volumes/workspace/datajobs_spike/landing/"
SCHEMA_LOCATION = "/Volumes/workspace/datajobs_spike/landing/_autoloader_schema/"


@dp.table(
    name="spike_raw",
    comment="Phase 0 spike only: proves Auto Loader + cloudFiles works inside a Lakeflow pipeline on this workspace.",
)
def spike_raw():
    return (
        spark.readStream.format("cloudFiles")
        .option("cloudFiles.format", "json")
        .option("cloudFiles.schemaLocation", SCHEMA_LOCATION)
        .option("cloudFiles.inferColumnTypes", "true")
        .option("multiLine", "true")
        .load(LANDING_PATH)
    )
