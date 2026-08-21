# ---------------------------------------
#
# Shared configuration for the Grunnkart pre-processing (gk_*)
#   sourced by BOTH the interactive driver (scripts/run_gk_all.R) and the standalone
#   per-fylke runner (scripts/run_fylke.R), so a single edit keeps them in sync.
#   Assumes fs::path() is available (load `fs` before sourcing).
#
# ---------------------------------------

ninaServer <- FALSE   # TRUE on the NINA linux R server, FALSE on a local PC

# import paths
pdrive <- if (ninaServer) "~/Mounts/P-Prosjekter2/" else "P:/"
rdrive <- if (ninaServer) "/data/R/" else "R:/"
gdb_folder <- path(rdrive, "GeoSpatialData/LandUse/Norway_Arealregnskap/Original/GrunnkartArealregnskap FGDB-format/")

# export paths (glue templates -- fill {f_id} and {yr} with glue::glue)
out_folder <- path(pdrive, "412413_2023_no_egd/git_data/GK_processed/")
out_etm <- path(out_folder, "BC", "GK_ETM_L1_{f_id}_{yr}.gpkg")    # dissolved level-1 ET maps per fylke
out_ms1 <- path(out_folder, "BC", "GK_masks_s1_{f_id}_{yr}.gpkg")  # simplified masks, method s1 (EDDE)
out_ms2 <- path(out_folder, "BC", "GK_masks_s2_{f_id}_{yr}.gpkg")  # simplified masks, method s2 (DEED)

# further knobs
yr <- "2025"       # year of the GK data processed
t_sliver <-  0.5   # sliver area threshold [m2] (polygons smaller than this are dropped)
t_tol1   <-  0.3   # vertex simplification "bandwidth" [m] for the ETM step
t_tol2   <-  3     # vertex simplification "bandwidth" [m] for the morph filtering (well below t_morph)
n_seg    <-  2     # ST_Buffer segments per quarter-circle for the morph filtering (default 8)
t_morph  <- 20     # morph(ological) filtering threshold [m] (2x the erosion/dilation buffer width)

# per-(fylke)-process resource limits (DuckDB threads & memory)
#   >8 threads buys little per job, so keep threads modest and run several fylke jobs concurrently
#   DuckDB likes ~1-4 GB RAM per active thread
nthreads <- if (ninaServer) 8  else 4
memlimit <- if (ninaServer) 32 else 4   # GB

# DuckDB temp/spill directory: set to a path on a large disk if DuckDB spills under memory
# pressure (e.g. "/data/tmp" on the server); NULL falls back to R's default tempdir().
gk_tmpdir <- NULL
