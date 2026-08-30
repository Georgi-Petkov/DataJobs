# Real Bronze ingestion pipeline. Structurally identical to the Phase 0
# spike (terraform/pipeline_spike.tf) -- same databricks_workspace_file +
# databricks_pipeline shape, proven to work -- pointed at the real source
# file and the real (non-spike) schema/volume from schema.tf.

resource "databricks_workspace_file" "bronze_pipeline_src" {
  source = "${path.module}/../databricks/datajobs_pipeline/src/bronze_ingest_pipeline.py"
  path   = "${data.databricks_current_user.me.home}/datajobs/bronze_ingest_pipeline.py"
}

resource "databricks_pipeline" "bronze_ingest" {
  name = "datajobs-bronze-ingest"

  catalog = "workspace"
  schema  = databricks_schema.datajobs.name

  serverless = true
  photon     = true
  continuous = false

  library {
    file {
      path = databricks_workspace_file.bronze_pipeline_src.path
    }
  }

  notification {
    email_recipients = ["2georgipetkov@gmail.com"]
    alerts            = ["on-update-failure"]
  }
}

output "bronze_pipeline_id" {
  value       = databricks_pipeline.bronze_ingest.id
  description = "Run `databricks pipelines start-update <id> --profile datajobs` to trigger an update."
}

output "bronze_pipeline_url" {
  value = databricks_pipeline.bronze_ingest.url
}
