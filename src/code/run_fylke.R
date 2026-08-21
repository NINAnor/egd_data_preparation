#!/usr/bin/env Rscript
# ---------------------------------------
#
# Standalone per-fylke runner for the Grunnkart pre-processing.
#   Processes ONE fylke in an isolated R process with its own DuckDB connection.
#   Designed to be dispatched by GNU parallel (one process per fylke, see
#   run_all_fylker.sh) on the server, but also runnable directly on a PC.
#
# Usage:  Rscript src/code/run_fylke.R <path/to/fylke.gdb> [--force]
#
# ---------------------------------------

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
  library(duckdb)
  library(duckspatial)
  library(sf)
  library(fs)
  library(glue)
  library(withr)
  library(pipetime)
})

# --- parse args ---
args     <- commandArgs(trailingOnly = TRUE)
force    <- "--force" %in% args
gdb_file <- args[!startsWith(args, "--")][1]
if (is.na(gdb_file) || !dir_exists(gdb_file))
  stop("Provide a valid .gdb path as the first argument. Got: ", gdb_file %||% "<none>")

# --- config, helpers, per-fylke pipeline ---
source(here::here("src/code", "BC_prep_GK_config.R"))
source(here::here("src/code", "BC_prep_GK_helpers.R"))
source(here::here("src/code", "BC_prep_GK_fylke.R"))

# --- per-process DuckDB connection (own temp database) ---
if (!is.null(gk_tmpdir)) dir_create(gk_tmpdir)
f_db <- file_temp(ext = "ddb", tmp_dir = gk_tmpdir %||% tempdir())
conn <- ddbs_create_conn(dbdir = f_db, threads = nthreads, memory_limit_gb = memlimit)
on.exit({
  try(ddbs_stop_conn(conn), silent = TRUE)
  if (file_exists(f_db)) try(file_delete(f_db), silent = TRUE)
  }, add = TRUE)

# --- run, with error handling / exit code (non-zero -> GNU parallel joblog flags it) ---
ok <- tryCatch({
  process_fylke(gdb_file, conn = conn, force = force)
  TRUE
 }, error = function(e) {
  message("ERROR processing ", gdb_file, ": ", conditionMessage(e))
  FALSE
  })

quit(status = if (isTRUE(ok)) 0L else 1L)
