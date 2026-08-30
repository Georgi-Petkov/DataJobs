# Databricks notebook source
# Scheduled dbt run: refreshes Silver + Gold from whatever Bronze currently
# has. Clones the public repo fresh each run (no persistent checkout to
# keep in sync) and runs against the same SQL Warehouse local dev uses, via
# dbt/datajobs/profiles.yml + a Databricks secret scope (datajobs-dbt)
# instead of a committed .env file. Directly modeled on healthkit's proven
# run_dbt_gold.py -- same shape, same reasoning.

REPO_URL = "https://github.com/Georgi-Petkov/DataJobs.git"
REPO_DIR = "/tmp/DataJobs"

# COMMAND ----------

# MAGIC %sh rm -rf /tmp/DataJobs && git clone --depth 1 https://github.com/Georgi-Petkov/DataJobs.git /tmp/DataJobs

# COMMAND ----------

# MAGIC %pip install dbt-databricks

# COMMAND ----------

dbutils.library.restartPython()

# COMMAND ----------

import os

os.environ["DATABRICKS_HOST"] = dbutils.secrets.get("datajobs-dbt", "databricks_host")
os.environ["DATABRICKS_HTTP_PATH"] = dbutils.secrets.get("datajobs-dbt", "databricks_http_path")
os.environ["DATABRICKS_TOKEN"] = dbutils.secrets.get("datajobs-dbt", "databricks_token")
os.environ["DBT_PROFILES_DIR"] = "/tmp/DataJobs/dbt/datajobs"

# COMMAND ----------

import subprocess

result = subprocess.run(
    ["dbt", "build"],
    cwd="/tmp/DataJobs/dbt/datajobs",
    capture_output=True,
    text=True,
)
print(result.stdout)
print(result.stderr)
if result.returncode != 0:
    raise RuntimeError(f"dbt build failed with exit code {result.returncode}")
