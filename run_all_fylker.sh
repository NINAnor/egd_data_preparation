#!/usr/bin/env bash
# ---------------------------------------
# Dispatch one run_fylke.R process per fylke via GNU parallel (NINA linux R server).
#
# Usage:  bash run_all_fylker.sh [JOBS]
#   JOBS = number of concurrent fylke jobs (default 8). Each job uses `nthreads`
#   DuckDB threads and `memlimit` GB as set in src/code/BC_prep_GK_config.R, so keep
#   JOBS * nthreads <= cores and JOBS * memlimit <= available RAM.
#
# Restartable: fylkes whose three gpkgs already exist are skipped (unless run_fylke.R
# is called with --force). Per-fylke stdout/stderr and exit codes land in ./logs.
# ---------------------------------------
set -euo pipefail

JOBS="${1:-8}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"

# Pre-install the DuckDB spatial extension once so parallel workers only *load* it
# (avoids a download/install race when many processes start simultaneously).
Rscript -e 'suppressPackageStartupMessages(library(duckdb)); con <- dbConnect(duckdb()); dbExecute(con, "INSTALL spatial"); dbDisconnect(con, shutdown = TRUE)'

# Single source of truth for the fylke list: read it from the R config.
Rscript -e 'suppressPackageStartupMessages(library(fs)); source("src/code/BC_prep_GK_config.R"); cat(dir_ls(gdb_folder, regexp = "gdb$"), sep = "\n")' \
  | parallel -j "$JOBS" --joblog "$LOG_DIR/joblog.tsv" --results "$LOG_DIR/{/.}/" \
      Rscript src/code/run_fylke.R {}

echo "All fylke jobs finished. Exit codes: $LOG_DIR/joblog.tsv"
