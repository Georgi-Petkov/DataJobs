#!/usr/bin/env python3
"""Copy already-scraped local JSON snapshots into the Bronze landing Volume.

Source of truth for what to upload: this repo's own data/ folder (gitignored
-- never commit, this repo is public). This script does no scraping and no
transformation -- it only moves files that already exist locally into cloud
storage, skipping anything already uploaded. Run manually after a scrape
session (`/as3jobs`).

Usage: python3 ingest/upload_to_volume.py [--profile datajobs] [--dry-run]
"""
import argparse
import subprocess
import sys
from pathlib import Path

REPO_DATA = Path(__file__).resolve().parent.parent / "data"

# source_platform -> local folder, matching ingest/source_contract.md.
# AS3 only -- its own `source` field already aggregates LinkedIn and
# several other boards, so a separate linkedin_jobs_scan ingestion path
# would be redundant (see source_contract.md).
SOURCES = {
    "as3": REPO_DATA / "as3_jobs_scan",
}

VOLUME_ROOT = "dbfs:/Volumes/workspace/datajobs/landing"


def run(cmd: list[str], dry_run: bool) -> str:
    if dry_run:
        print("would run:", " ".join(cmd))
        return ""
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        result.check_returncode()
    return result.stdout


def already_uploaded(source_platform: str, profile: str, dry_run: bool) -> set[str]:
    remote_dir = f"{VOLUME_ROOT}/{source_platform}"
    cmd = ["databricks", "fs", "ls", remote_dir, "--profile", profile]
    if dry_run:
        return set()
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        # Directory doesn't exist yet -- nothing uploaded so far, not an error.
        return set()
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default="datajobs")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    total_uploaded = 0
    for source_platform, local_dir in SOURCES.items():
        if not local_dir.is_dir():
            print(f"skip {source_platform}: {local_dir} does not exist")
            continue

        remote_dir = f"{VOLUME_ROOT}/{source_platform}"
        run(["databricks", "fs", "mkdir", remote_dir, "--profile", args.profile], args.dry_run)

        remote_existing = already_uploaded(source_platform, args.profile, args.dry_run)
        local_files = sorted(local_dir.glob("*.json"))

        for local_file in local_files:
            if local_file.name in remote_existing:
                continue
            remote_path = f"{VOLUME_ROOT}/{source_platform}/{local_file.name}"
            run(
                ["databricks", "fs", "cp", str(local_file), remote_path, "--profile", args.profile],
                args.dry_run,
            )
            print(f"uploaded {source_platform}/{local_file.name}")
            total_uploaded += 1

    print(f"\n{total_uploaded} file(s) uploaded" + (" (dry run)" if args.dry_run else ""))


if __name__ == "__main__":
    main()
