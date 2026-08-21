# ---------------------------------------
# title:   Data pre-processing for the Norwegian **Nasjonalt Grunnkart for arealanalyse**
# authors: Sylvie Clappe, Bálint Czúcz
#          Norwegian Institute for Nature Research
# date:    2026
# ---------------------------------------
#
# Driver for the per-fylke Grunnkart cycle. It sources the shared config, the SQL/helpers
# and the per-fylke pipeline (process_fylke), then runs every fylke. On the NINA linux
# server the heavy lifting is dispatched one process per fylke via GNU parallel (see
# run_all_fylker.sh); the sequential loop below is the PC fallback. Per fylke it exports
# three gpkgs: the level-1 dissolved ET map, the s1 (EDDE) masks, and the s2 (DEED) masks.

library(tidyverse)
library(here)
library(duckdb)
library(duckspatial)
library(sf)
library(fs)
library(glue)
library(withr)
library(pipetime)

###
### Config, helpers, per-fylke pipeline ---
###

source(here::here("src/code", "BC_prep_GK_config.R"))   # paths, year, thresholds, resource limits
source(here::here("src/code", "BC_prep_GK_helpers.R"))  # SQL query templates & helper functions
source(here::here("src/code", "BC_prep_GK_fylke.R"))    # process_fylke(): the full per-fylke pipeline

# # detect the available resources (# typical reserved / low-usage values in comments)
# mem_info <- readLines("/proc/meminfo")
# mem_info %>% str_subset("MemTotal")     # (rstudio-geo.nina.no, 260807): ~1056 GB !
# mem_info %>% str_subset("MemAvailable") # (rstudio-geo.nina.no, 260807):  ~970 GB !
# parallel::detectCores(logical = TRUE)   # (rstudio-geo.nina.no, 260807): 96 cores !

gdb_files <- dir_ls(gdb_folder, regexp = "gdb$")


###
### Driver A -- server: one isolated process per fylke via GNU parallel ---
###
# Run from a shell (NOT from R). Each fylke gets its own R process + DuckDB connection, so
# memory is reclaimed cleanly on exit and a crash in one fylke cannot affect the others.
# Restartable: fylkes whose three gpkgs already exist are skipped.
#
#   bash run_all_fylker.sh 8      # 8 = concurrent fylke jobs (each uses nthreads/memlimit from config)
#
# Logs & per-fylke stdout/stderr land in ./logs (joblog.tsv holds the exit codes).


###
### Driver B -- PC / small runs: sequential loop (fresh DB per fylke) ---
###
# Flip to TRUE to process all fylkes one after another on this machine (can take many hours).
run_sequential <- FALSE
if (run_sequential) {
  for (gdb in gdb_files) {
    f_db    <- file_temp(ext = "ddb")
    conn_gk <- ddbs_create_conn(dbdir = f_db, threads = nthreads, memory_limit_gb = memlimit)
    tryCatch(process_fylke(gdb, conn = conn_gk, force = FALSE),
             error = function(e) message("ERROR on ", path_file(gdb), ": ", conditionMessage(e)))
    ddbs_stop_conn(conn_gk)
    if (file_exists(f_db)) file_delete(f_db)
  }
}


###
### Interactive single-fylke debugging ---
###
# Run ONE fylke without cleaning up the intermediate tables, then inspect with the
# DB queries and h_zoomplot() smoke tests below.
if (FALSE) {
  gdb_1   <- gdb_files[str_detect(gdb_files, "/32_")]   # fylke #32 = Akershus
  f_db0   <- file_temp(ext = "ddb") %>% {cat("\nDuckDB Database set to: ", ., "\n"); .}
  conn_gk <- ddbs_create_conn(dbdir = f_db0, threads = nthreads, memory_limit_gb = memlimit)

  process_fylke(gdb_1, conn = conn_gk, force = TRUE, cleanup = FALSE)  # keep gk_* tables for inspection

  ### -- optional DB inspection
  ddbs_list_tables(conn_gk)
  conn_gk %>% dbGetQuery("PRAGMA database_size")
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw")
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_union")   # N of polygons drastically reduced (~20% of raw)
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_EDDE")
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_DEED")

  ### -- validity checks (should all be 0 rows)
  ddbs_is_valid("gk_union", conn = conn_gk)  %>% filter(!is_valid)  %>% ddbs_collect %>% nrow
  ddbs_is_empty("gk_union", conn = conn_gk)  %>% filter(is_empty)   %>% ddbs_collect %>% nrow
  ddbs_is_simple("gk_union", conn = conn_gk) %>% filter(!is_simple) %>% ddbs_collect %>% nrow

  ### -- visual smoke tests (zoom1 is in f32 / Akershus)
  exec(h_zoomplot, "gk_raw",   "e_id", !!!(zoom1))
  exec(h_zoomplot, "gk_union", "e_id", !!!(zoom1))
  exec(h_zoomplot, "gk_EDDE",  "e_id", !!!(zoom1))
  exec(h_zoomplot, "gk_DEED",  "e_id", !!!(zoom1))

  ddbs_stop_conn(conn_gk)
}
