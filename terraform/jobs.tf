# Managed via Terraform end-to-end -- unlike healthkit, where the
# equivalent notebook was manually uploaded and the job resource just
# references a pre-existing workspace path. databricks_notebook here
# actually owns the notebook's content, not just the job pointing at it.

resource "databricks_notebook" "run_dbt_datajobs" {
  source = "${path.module}/../databricks/datajobs_pipeline/notebooks/run_dbt_datajobs.py"
  path   = "${data.databricks_current_user.me.home}/datajobs/run_dbt_datajobs"
}

resource "databricks_job" "datajobs_daily_refresh" {
  name = "datajobs-daily-refresh"

  max_concurrent_runs = 1

  queue {
    enabled = true
  }

  email_notifications {
    on_failure = ["2georgipetkov@gmail.com"]
  }

  schedule {
    quartz_cron_expression = "0 0 5 * * ?"
    timezone_id            = "Europe/Copenhagen"
    pause_status           = "UNPAUSED"
  }

  task {
    task_key = "refresh_bronze"

    pipeline_task {
      pipeline_id = databricks_pipeline.bronze_ingest.id
    }
  }

  task {
    task_key = "run_dbt_silver_gold"

    depends_on {
      task_key = "refresh_bronze"
    }

    notebook_task {
      notebook_path = databricks_notebook.run_dbt_datajobs.path
      source        = "WORKSPACE"
    }
  }
}
