# Real (non-spike) schema + landing volume. Defaults to a schema inside the
# `workspace` catalog -- the same proven pattern healthkit already uses
# (`healthkit`, `healthkit_silver`, `healthkit_gold`) -- rather than a
# dedicated catalog. Live check #3 (can this workspace CREATE CATALOG?)
# hasn't been run yet; this default carries zero collision risk either way,
# so it's not blocking real ingestion work.

resource "databricks_schema" "datajobs" {
  catalog_name = "workspace"
  name         = "datajobs"
  comment      = "DataJobs Bronze/Silver/Gold -- job-posting data pipeline."
}

resource "databricks_volume" "landing" {
  catalog_name = "workspace"
  schema_name  = databricks_schema.datajobs.name
  name         = "landing"
  volume_type  = "MANAGED"
  comment      = "Raw scraped JSON, landed by ingest/upload_to_volume.py, one subfolder per source_platform. See ingest/source_contract.md."
}

output "landing_volume_path" {
  value       = "/Volumes/workspace/${databricks_schema.datajobs.name}/${databricks_volume.landing.name}"
  description = "Root path ingest/upload_to_volume.py uploads into, per-source subfolders underneath."
}
