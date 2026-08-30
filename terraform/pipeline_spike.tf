# ============================================================================
# PHASE 0 LIVE-CHECK SPIKE -- delete this whole file once answered.
#
# Question: does a real Lakeflow Declarative Pipeline (Auto Loader inside a
# @dp.table) actually RUN -- not just validate -- on this Free Edition
# workspace's serverless compute? See ../databricks/datajobs_pipeline/src/
# spike_pipeline.py for the pipeline code itself and the full context.
#
# Everything in this file is throwaway: a dedicated schema + volume so
# nothing here can collide with real Bronze/Silver/Gold schemas decided
# later, and a pipeline pointed at it. Safe to `terraform destroy` this
# file's resources (or delete the file and re-apply) once we have an answer.
# ============================================================================

data "databricks_current_user" "me" {}

resource "databricks_schema" "spike" {
  catalog_name = "workspace"
  name         = "datajobs_spike"
  comment      = "Throwaway schema for the Phase 0 Lakeflow-on-serverless live check. Safe to drop once answered."
}

resource "databricks_volume" "spike_landing" {
  catalog_name = "workspace"
  schema_name  = databricks_schema.spike.name
  name         = "landing"
  volume_type  = "MANAGED"
  comment      = "Throwaway landing volume for the Phase 0 spike -- not the real DataJobs landing zone."
}

resource "databricks_workspace_file" "spike_pipeline_src" {
  source = "${path.module}/../databricks/datajobs_pipeline/src/spike_pipeline.py"
  path   = "${data.databricks_current_user.me.home}/datajobs_spike/spike_pipeline.py"
}

resource "databricks_pipeline" "spike" {
  name = "datajobs-spike-lakeflow-check"

  catalog = "workspace"
  schema  = databricks_schema.spike.name

  serverless = true
  photon     = true
  continuous = false

  library {
    file {
      path = databricks_workspace_file.spike_pipeline_src.path
    }
  }

  notification {
    email_recipients = ["2georgipetkov@gmail.com"]
    alerts            = ["on-update-failure"]
  }
}

output "spike_pipeline_id" {
  value       = databricks_pipeline.spike.id
  description = "Run `databricks pipelines start-update <id> --profile healthkit` then check the event log."
}

output "spike_landing_volume_path" {
  value       = "/Volumes/workspace/${databricks_schema.spike.name}/${databricks_volume.spike_landing.name}"
  description = "Upload a tiny synthetic JSON file here before starting an update -- Terraform manages the volume, not what's inside it."
}

output "spike_pipeline_url" {
  value       = databricks_pipeline.spike.url
  description = "Open this in a browser to watch the update run and read the event log directly."
}
