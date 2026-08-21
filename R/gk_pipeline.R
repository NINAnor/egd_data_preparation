# ---------------------------------------
#
# Per-fylke pipeline for the Grunnkart pre-processing.
#   process_fylke() runs the whole chain for ONE fylke and exports the three gpkgs:
#     - level-1 dissolved ET map (out_etm)
#     - simplified masks, method s1 = EDDE (out_ms1)
#     - simplified masks, method s2 = DEED (out_ms2)
#   Relies on config globals (out_*, yr, t_*, n_seg) and the query_* templates + helpers.
#
# ---------------------------------------


#' Process a single Grunnkart fylke end-to-end
#'
#' @param gdb_file path to one fylke .gdb
#' @param conn     an open DuckDB connection (with duckspatial/spatial available)
#' @param force    if FALSE, skip the fylke when all three outputs already exist
#' @param cleanup  if TRUE, drop the fylke's working tables at the end (set FALSE to
#'                 keep gk_* tables around for interactive inspection)
#' @return invisibly one of "skipped" / "done"
process_fylke <- function(gdb_file, conn, force = FALSE, cleanup = TRUE) {

  fid <- gdb_file %>% str_extract("(?<=format/).{2}") %>% paste0("f", .)  # e.g. ".../format/32_..." -> "f32"
  message(glue("\n=== {format(Sys.time(), '%H:%M:%S')}  processing {fid}  ({path_file(gdb_file)}) ==="))

  # target outputs for this fylke
  p_etm <- glue(out_etm, f_id = fid, yr = yr)
  p_ms1 <- glue(out_ms1, f_id = fid, yr = yr)
  p_ms2 <- glue(out_ms2, f_id = fid, yr = yr)
  dir_create(path_dir(p_etm))

  if (!force && all(file_exists(c(p_etm, p_ms1, p_ms2)))) {
    message(glue("  all outputs exist -- skipping {fid} (use force = TRUE to overwrite)"))
    return(invisible("skipped"))
  }

  ### 1) serialize the gdb into a temporary FlatGeobuf (much friendlier for duckdb) ---
  fdb <- file_temp(ext = "fgb")
  on.exit(if (file_exists(fdb)) file_delete(fdb), add = TRUE)
  with_envvar(  # skip all validation attempts at this point -- we fix validity on load below
    new  = c("OGR_ORGANIZE_POLYGONS" = "SKIP"),
    code = gdal_utils(util = "vectortranslate", source = gdb_file, destination = fdb,
                      options = c("-f", "FlatGeobuf", "-overwrite", "arealregnskap")) %>%
             time_pipe() %>% invisible()
  )

  ### 2) load raw GK into the DB (ST_MakeValid makes up for the bypassed gdb-import checks) ---
  tbl(conn, sql(paste0("SELECT * FROM ST_Read('", fdb, "')"))) %>%
    mutate(f_id = fid) %>%                                                  # fylkes act as "tiles"
    mutate(e_id = sql("'e' || lpad(split_part(okosystemtype_kode, '.', 1), 2, '0')")) %>%
    mutate(geom = sql("ST_MakeValid(geom)")) %>%
    select(f_id, e_id, et_name = okosystemtype_1, areal_m2, geom) %>%
    compute(name = "gk_raw", temporary = FALSE, overwrite = TRUE) %>%
    time_pipe() %>% invisible()

  ### 3) raw -> clean level-1 ET map (explode, de-sliver, dissolve) & export ---
  query_dissolve_full %>%
    glue(ii = "gk_raw", oo = "gk_union", sv = t_sliver, ts = t_tol1) %>%
    dbExecute(conn = conn) %>%
    time_pipe(unit = "mins")
  as_duckspatial_df("gk_union", conn = conn) %>%
    ddbs_write_dataset(p_etm, gdal_driver = "GPKG", overwrite = TRUE) %>%
    time_pipe()

  ### 4) method s1 (EDDE): non-overlapping almost-tessellation & export ---
  query_ED_all %>%
    glue(ii = "gk_union", oo = "gk_ED", f_id = fid, bd = t_morph / 2, ts = t_tol2, ns = n_seg) %>%
    dbExecute(conn = conn) %>% time_pipe(unit = "mins")
  query_DE_all %>%
    glue(ii = "gk_ED", oo = "gk_EDDE", f_id = fid, bd = t_morph / 2, ts = t_tol2, ns = n_seg) %>%
    dbExecute(conn = conn) %>% time_pipe(unit = "mins")
  as_duckspatial_df("gk_EDDE", conn = conn) %>%
    ddbs_write_dataset(p_ms1, gdal_driver = "GPKG", overwrite = TRUE) %>%
    time_pipe()

  ### 5) method s2 (DEED): overlapping ET masks & export ---
  query_DE_all %>%
    glue(ii = "gk_union", oo = "gk_DE", f_id = fid, bd = t_morph / 2, ts = t_tol2, ns = n_seg) %>%
    dbExecute(conn = conn) %>% time_pipe(unit = "mins")
  query_ED_all %>%
    glue(ii = "gk_DE", oo = "gk_DEED", f_id = fid, bd = t_morph / 2, ts = t_tol2, ns = n_seg) %>%
    dbExecute(conn = conn) %>% time_pipe(unit = "mins")
  as_duckspatial_df("gk_DEED", conn = conn) %>%
    ddbs_write_dataset(p_ms2, gdal_driver = "GPKG", overwrite = TRUE) %>%
    time_pipe()

  ### 6) drop the fylke's working tables so a reused connection starts clean next time ---
  if (cleanup)
    walk(c("gk_raw", "gk_union", "gk_ED", "gk_EDDE", "gk_DE", "gk_DEED"),
         \(t) dbExecute(conn, paste0("DROP TABLE IF EXISTS ", t)))

  message(glue("  {format(Sys.time(), '%H:%M:%S')}  done: {fid}"))
  invisible("done")
}
