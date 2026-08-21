# ---------------------------------------
# title:   Data pre-processing for the Norwegian **Nasjonalt Grunnkart for arealanalyse**  
# authors: Sylvie Clappe, Bálint Czúcz
#          Norwegian Institute for Nature Research # Enter affiliations
# date:    2026
# ---------------------------------------

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
###
### Config, setup ---
###

ninaServer <- F

# import paths
pdrive <- if(ninaServer) "~/Mounts/P-Prosjekter2/" else "P:/"
rdrive <- if(ninaServer) "/data/R/" else "R:/"
gdb_folder <- path(rdrive, "GeoSpatialData/LandUse/Norway_Arealregnskap/Original/GrunnkartArealregnskap FGDB-format/")
                  
# export paths (use with glue::glue)
out_folder <- path(pdrive, "412413_2023_no_egd/git_data/GK_processed/")
out_etm <- path(out_folder, "BC", "GK_ETM_L1_{f_id}_{yr}.gpkg")     # dissolved ET maps per fylke (or national level for "f00")
out_ms1 <- path(out_folder, "BC", "GK_masks_s1_{f_id}_{yr}.gpkg")   # simplified masks with method s1 for ET eID and fylke fID (or national for "f00") 
out_ms2 <- path(out_folder, "BC", "GK_masks_s2_{f_id}_{yr}.gpkg")   # simplified masks with method s2 for ET eID and fylke fID (or national for "f00") 

# further knobs
yr <- "2025"       # year of the GK data processed
t_sliver <-  0.5  # sliver area threshold [m2] (polygons smaller than this will be dropped)
t_tol1   <-  0.3  # vertex simplification "bandwidth" [m] for the ETM step (curves within such a band will be straightened out)
t_tol2   <-  3    # vertex simplification "bandwidth" [m] for the morph filtering [m] (should be well below t_morph)
n_seg    <-  2    # ST_Buffer segments per quarter-circle for the morph filtering (default 8)
t_morph  <- 20    # morph(ological) filtering threshold [m] (2x of the erosion/dilation buffer width used in both simplification methods)

# helpers, sql queries
source(here::here("src/code", "BC_prep_GK_helpers.R"))

###
###
### Initialise ---
###

# # detect the available resources (# typical reserver / low-usage values in comments)
# mem_info <- readLines("/proc/meminfo")
# # system("awk '$3==\"kB\" {$2=sprintf(\"%.2f\", $2/1024/1024); $3=\"GB\"} 1' /proc/meminfo | column -t") # attempt to transfor it into GB
# mem_info %>% str_subset("MemTotal")     # (rstudio-geo.nina.no, 260807): ~1056 GB !
# mem_info %>% str_subset("MemAvailable") # (rstudio-geo.nina.no, 260807):  ~970 GB !
# parallel::detectCores(logical = TRUE)   # (rstudio-geo.nina.no, 260807): 96 cores !

# preset suitable values -- customise as needed
#   (from Gemini): DuckDB functions best when allocated between 1 GB and 4 GB of RAM per active thread
#   (from Claude): >8 threads buys you nothing, so it's kinder to reserve capacity (& e.g. run several ET/fylke jobs concurrently)
nthreads= if (ninaServer) 8  else 4  # numbers for ninapc suggested by Gemini, for the server by Claude (after diagnostic checks)
memlimit= if (ninaServer) 32 else 4  

f_db0 <- file_temp(ext= "ddb") %>% {cat("\nDuckDB Database set to: ", ., "\n"); .}      # database in a temp file
# f_db1 <- "/tmp/RtmpYJ337f/file3556bc64df8ac6.ddb" # ...or reload a previous file here
conn_gk <- ddbs_create_conn(dbdir= f_db0, threads= nthreads, memory_limit_gb= memlimit) #
# side notes: 
#   * DuckDB automatically parallelises processes (except for ST_Union_Agg)
#     With 10 cores and a memory limit of 30GB, it takes about 1h-2h for the union and cleaning to run on one dataset. 
#     So in total, the code below should take about 4-5h (patience is a virtue!). 

if (F) {  ### -- potentially useful database commands 
  conn_gk %>% dbGetInfo() %>% pluck("dbname")               # to locate the temp file used
  conn_gk %>% dbGetQuery("PRAGMA database_size")           # to query database size
  conn_gk %>% dbExecute("DROP TABLE IF EXISTS gk_raw")      # to delete a specific table
  ddbs_stop_conn(conn_gk)     # to close the connection (does not instantly delete the temp file, it will only be deleted at session end)
  }


###
###
### Load GK input files ---
###

gdb_files <-  dir_ls(gdb_folder, regexp = "gdb$") 

#-- placeholder: the "purr::map(gdb_files, function \(gdb1) {...})"-style cycle (optimised with paralell/mirai) will start here

gdb_1 <- gdb_files[str_detect(gdb_files,"/32_")] # fylke #32 is Akershus
fdb_1 <- file_temp(ext= "fgb") # a temporary fgb (FlatGeobuf) file -- which is much better for duckdb(!)
fid_1 <- gdb_1 %>% str_extract("(?<=format/).{2}") %>% paste0("f",.) # RE finding "format/", and pulling out the next 2 characters

# if (file_exists(fdb_1)) file_delete(fdb_1)
with_envvar(  # serialize the gdb into an fdb as is -- skipping all validation attampts at this point
  new =  c("OGR_ORGANIZE_POLYGONS" = "SKIP"),
  code = gdal_utils(util= "vectortranslate", source = gdb_1, destination= fdb_1,  
                    options= c("-f", "FlatGeobuf", "-overwrite", "arealregnskap")) %>%
           time_pipe() %>% invisible() # super fast on server, ~50s on local pc 
  )

tbl(conn_gk, sql(paste0("SELECT * FROM ST_Read('", fdb_1, "')"))) %>% 
  # rename(geom = geo) %>%    # GDAL defaults to "geom" for the geometry column, it is better to get rid of the ESRI conventions before thay cause pain 
                              #  -- this is not necessary after passign the data through the FlatGeobuf file
  mutate(f_id= fid_1) %>%  # fylkes are used as "tiles" -- using fid or fID as colname would be in conflict with GeoPackage primary key(!)
  # mutate(eID= okosystemtype_kode %>% str_split_i(fixed("."), 1) %>% as.numeric %>% sprintf('e%02d', .)) %>%
  mutate(e_id= sql("'e' || lpad(split_part(okosystemtype_kode, '.', 1), 2, '0')")) %>% # the dbplyr-compatible version of the line above
  mutate(geom = sql("ST_MakeValid(geom)")) %>% # we need this here to make up for the bypassed validations at gdb import 
  select(f_id, e_id, et_name= okosystemtype_1, areal_m2, geom) %>% 
  compute(name = "gk_raw", temporary = FALSE, overwrite = TRUE) %>%
  time_pipe() %>% invisible() #  server: ~30s, local: ~5 min

crs_1 <- as_duckspatial_df("gk_raw", conn=conn_gk) %>% ddbs_crs() 
# crs_1 <- st_read(gdb_1, query = "SELECT * FROM arealregnskap LIMIT 10") %>% st_crs()


# ---------------- EDA-phase hack: restrict the exercise to a small region around the "zoom1" site ---------------------------------!!!!
#   (zoom1 is in f32 / Akershus, this hack will only work there!!!)
if (FALSE) {
  conn_gk %>% dbExecute("CREATE OR REPLACE TABLE gk_raw_orig AS FROM gk_raw") # make a safety copy of the original gk_raw...
  zoombox <- c(zoom1$lon, zoom1$lat) %>% st_point %>% st_sfc(crs= 4326) %>% 
    st_transform(crs_1) %>% st_buffer(2000) %>% st_bbox() 
  as_duckspatial_df("gk_raw", conn=conn_gk) %>%
    ddbs_crop(st_as_sf(st_as_sfc(zoombox))) %>%       # annoying "false" crs warning... :(
    ddbs_write_table(conn= conn_gk, name= "gk_raw", overwrite =T) %>%   # and overwrite it with a small part of it   
    time_pipe() #  ~2s  -- keeps only ~3000 polygons from the original 660k
  h_cleanup_db(conn_gk)
  } #-------------------------------------------------------------------------------------------------------------------------------!!!!

if (F) { ### -- optional DB inspection 
  ddbs_list_tables(conn_gk)
  conn_gk %>% dbGetQuery("PRAGMA database_size")
  conn_gk %>% dbGetQuery("SELECT * FROM gk_raw LIMIT 100" ) %>% str()
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw_orig") 
  tbl(conn_gk, "gk_raw") %>% glimpse()  # an alternative way to inspect the structure
  #
  # Visual smoke tests
  exec(h_zoomplot, "gk_raw", "e_id", !!!(zoom1))  #--> test plot looks nice :)
  } 


###
###
### From raw GK to clean level-1 ET maps ---
###

# Explode, de-sliver, and dissolve polygons based on level-1 ET
#   an optimised pure-SQL alternative (developed with Gemini/Claude, works directly on the DB)
query_dissolve_full %>%
  glue(ii= "gk_raw", oo= "gk_union", sv= t_sliver, ts= t_tol1) %>%
  dbExecute(conn = conn_gk) %>%
  time_pipe(unit = "mins")  # ~5 min (for Akershus)
# side note: sql GROUP BY operations are internally parallelised by duckDB  

if (F) { ### Optional DB inspection 
  ddbs_list_tables(conn_gk)
  conn_gk %>% dbGetQuery("PRAGMA database_size") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_union")  # the N of polygons is drastically reduced (to ~20% of its orig value)
  conn_gk %>% dbGetQuery("SELECT * FROM gk_union LIMIT 100" ) %>% str() #only 3 cols: e_id, f_id, & geom (with a POLYGON geometry)
  #  
  # Validity checks - should all disply 0 rows
  ddbs_is_valid("gk_union", conn= conn_gk) %>% filter(!is_valid) %>% ddbs_collect %>% nrow
  ddbs_is_empty("gk_union", conn= conn_gk) %>% filter(is_empty) %>% ddbs_collect %>% nrow
  ddbs_is_simple("gk_union", conn= conn_gk) %>% filter(!is_simple) %>% ddbs_collect %>% nrow
  #
  # Visual smoke tests
  exec(h_zoomplot, "gk_union", "e_id", !!!(zoom1))  # gk_union: most internal boundaries (eg. in e01-urban, e04-forest) disappeared... 
  exec(h_zoomplot, "gk_union", "e_id", lon=10.7, lat=59.6, rr=200)  # gk_union: most internal boundaries (eg. in e01-urban, e04-forest) disappeared... 
  }

# Export level-1 ETM for each fylke (-- except the national "f00")
as_duckspatial_df("gk_union", conn= conn_gk) %>% # export as a geopackage
  ddbs_write_dataset(glue(out_etm, f_id= "f32", yr=yr), gdal_driver= "GPKG", overwrite= T) %>%  # Akershus: 461 MB
  time_pipe() # ~30s


###
###
### From L1 ET maps to simplified ET masks 
###

# # Re-read L1 ETM if needed 
# ddbs_open_dataset(glue(out_etm, f_id= "f32", yr=yr)) %>%
#   ddbs_write_table(conn= conn_gk, name= "gk_union", overwrite =T)


### pilot exercise: pick one specific ET #urban
###  with method s2
# out_tmp <- out_folder %>% path("BC", "tmp_s2_{e_id}_{f_id}_{yr}-{nn}.gpkg")

# # explorative DEED with _just one_ ET:
# et1 <- "e04"; o1 <- paste0("gk_DE_", et1); o2 <-paste0("gk_DEED_", et1)
# query_DE %>%                                             # substep 1: DE
#   glue(ii="gk_union", oo=o1, f_id="f32", e_id= et1, bd= t_morph/2, ts= t_tol2, ns= n_seg) %>%
#   dbExecute(conn= conn_gk) %>%
#   time_pipe(unit= "mins") # ~20 min for e01 in f32 ((was ~100 min w/o ST_Simplify & the curve vertex argument argument of ST_Buffer)) 
# query_ED %>%                                             #substep 2: ED
#   glue(ii= o1, oo= o2, f_id="f32", e_id= et1, bd= t_morph/2, ts= t_tol2, ns= n_seg) %>%
#   dbExecute(conn= conn_gk) %>%
#   time_pipe(unit="mins") # ~4 min (for e01 in f32)
# h_cleanup_db(conn_gk)

# Method s1: ED-DE -- Non-overlapping "almost-tessellation", with many small (and few larger) gaps between the ETs
format(Sys.time(), "%H:%M:%S")
query_ED_all %>%                                             # substep 1: ED
  glue(ii="gk_union", oo="gk_ED", f_id="f32", bd= t_morph/2, ts= t_tol2, ns= n_seg) %>%
  dbExecute(conn= conn_gk) %>%
  time_pipe(unit= "mins") # ~8 min (Akershus)
format(Sys.time(), "%H:%M:%S")
query_DE_all %>%                                             # substep 2: DE
  glue(ii="gk_ED", oo="gk_EDDE", f_id="f32", bd= t_morph/2, ts= t_tol2, ns= n_seg) %>%
  dbExecute(conn= conn_gk) %>%
  time_pipe(unit= "mins") # ~3 min (Akershus)
format(Sys.time(), "%H:%M:%S")
as_duckspatial_df("gk_DE", conn= conn_gk) %>% # export as a geopackage
  ddbs_write_dataset(glue(out_ms1, e_id="e01", f_id= "f32", yr=yr, nn="DEED"), gdal_driver= "GPKG", overwrite= T) %>%  # Akershus
  time_pipe() # ~1s

# Method s2: DE-ED -- Overlapping ET masks, with many small (and few larger) overlaps and few tiny gaps between the ETs 
format(Sys.time(), "%H:%M:%S")
query_DE_all %>%                                             # substep 1: DE
  glue(ii="gk_union", oo="gk_DE", f_id="f32", bd= t_morph/2, ts= t_tol2, ns= n_seg) %>%
  dbExecute(conn= conn_gk) %>%
  time_pipe(unit= "mins") # ~15 min (Akershus) 
format(Sys.time(), "%H:%M:%S")
query_ED_all %>%                                             # substep 2: ED
  glue(ii="gk_DE", oo="gk_DEED", f_id="f32", bd= t_morph/2, ts= t_tol2, ns= n_seg) %>%
  dbExecute(conn= conn_gk) %>%
  time_pipe(unit= "mins") # ~7 min (Akershus)
format(Sys.time(), "%H:%M:%S")
as_duckspatial_df("gk_DE", conn= conn_gk) %>% # export as a geopackage
  ddbs_write_dataset(glue(out_ms2, e_id="e01", f_id= "f32", yr=yr, nn="DEED"), gdal_driver= "GPKG", overwrite= T) %>%  # Akershus
  time_pipe() # ~ 1s

h_cleanup_db(conn_gk)

if (F) { ### Optional DB inspections
  ddbs_list_tables(conn_gk)
  conn_gk %>% dbGetQuery("PRAGMA database_size") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_union") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_DE") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_ED") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_DEED")
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_EDDE") 
  # the N of polygons is drastically reduced (to ~20% of its orig value)
  conn_gk %>% dbGetQuery("SELECT * FROM gk_union LIMIT 100" ) %>% str() #only 3 cols: e_id, f_id, & geom (with a POLYGON geometry)
  #
  # Visual smoke tests
  exec(h_zoomplot, "gk_DE", "e_id", !!!(zoom1))   #  
  exec(h_zoomplot, "gk_ED", "e_id", !!!(zoom1))   #  
  exec(h_zoomplot, "gk_DEED", "e_id", !!!(zoom1)) #  
  exec(h_zoomplot, "gk_EDDE", "e_id", !!!(zoom1)) #  
  # ... but a few still remain, plus some very narrow channels & small islands -- these are still "nuisance" from an EC perspective)
  }

#-- placeholder: the the end of the paralell/mirai/etc -optimised cycle




