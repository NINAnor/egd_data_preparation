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
library(pipetime) 

###
###
### Config, setup ---
###

ninaServer <- T

# import paths
pdrive <- if(ninaServer) "~/Mounts/P-Prosjekter2/" else "P:/"
rdrive <- if(ninaServer) "/data/R/" else "R:/"
gdb_folder <- path(rdrive, "GeoSpatialData/LandUse/Norway_Arealregnskap/Original/GrunnkartArealregnskap FGDB-format/")
                  
# export paths (use with glue::glue)
out_folder <- path(pdrive, "412413_2023_no_egd/git_data/GK_processed/")
out_etm <- path(out_folder, "BC", "GK_ETM_L1_{f_id}_{yr}.gpkg")     # dissolved ET maps per fylke (or national level for "f00")
out_ms1 <- path(out_folder, "BC", "GK_s1_{e_id}_{f_id}_{yr}.gpkg")   # simplified masks with method s1 for ET eID and fylke fID (or national for "f00") 
out_ms2 <- path(out_folder, "BC", "GK_s2_{e_id}_{f_id}_{yr}.gpkg")   # simplified masks with method s2 for ET eID and fylke fID (or national for "f00") 

# further knobs
yr <- "2025"       # year of the GK data processed
th_sliver <-  0.5  # sliver threshold [m2] (polygons smaller than this will be dropped)
th_morph  <- 20    # morphological threshold [m] (2x of the erosion/dilation buffer width used in both simplification methods)

# helper functions
h_cleanup_db <- function(conn) {  # Clean up a duckDB database (conn): remove temporary tables & views 
  walk(dbListTables(conn), 
       \(x) switch(str_sub(x, 1, 9), 
                   temp_view= {dbExecute(conn_gk, sprintf("DROP VIEW IF EXISTS %s", dbQuoteIdentifier(conn_gk, x))); 0},
                   temp_tabl= {dbExecute(conn_gk, sprintf("DROP TABLE IF EXISTS %s", dbQuoteIdentifier(conn_gk, x))); 0},
                   1))
  }

#tabl="gk_raw"; feat= "e_id"; lon=10.7; lat=59.6; rr=1000; conn=conn_gk
h_zoomplot <- function(tabl, feat=NULL, lon, lat, rr=2000, conn=conn_gk) { #custom zoom-in plots for visual inspection
  # conn:    a connection (pointing at a duckspatial DB)
  # tabl:    name of a table in conn 
  # feat:    a colname in tabl (used for setting colours) 
  # lon,lat: unprojected coordinates of an interesting place (looked up e.g. from google maps) 
  # rr:      radius (m) around the point that should be shown
  crs1 <- as_duckspatial_df(tabl, conn=conn) %>% ddbs_crs() 
  print(tabl); print(feat); print(lat); print(lon); print(rr); print(conn)
  zoombox <- c(lon, lat) %>% st_point %>% st_sfc(crs= 4326) %>% st_transform(crs1) %>% st_buffer(rr) %>% st_bbox() 
  as_duckspatial_df(tabl, conn=conn) %>%
    ddbs_crop(st_as_sf(st_as_sfc(zoombox))) %>%       # annoying false warning...
    collect() %>%
    mutate(types= if (is.null(feat)) "mask" else .data[[feat]]) %>%
    ggplot() + geom_sf(aes(fill= types), alpha=.33) + scale_fill_discrete() + theme_minimal() 
  }
# rm(tabl, feat, lon, lat, rr, conn)

zoom1 <- list(lon=10.7, lat=59.6, rr=1000) # a nice neighborhood to zoom in, relevant for BmB2 (Elvia case)
# exec(h_zoomplot, "gk_raw", "e_id", !!!(zoom1)) #--> this is how zoom1 can be "splashed" into funbction calls 


###
###
### Initialise ---
###

# detect the available resources (# typical reserver / low-usage values in comments)
mem_info <- readLines("/proc/meminfo")
# system("awk '$3==\"kB\" {$2=sprintf(\"%.2f\", $2/1024/1024); $3=\"GB\"} 1' /proc/meminfo | column -t") # attempt to transfor it into GB
mem_info %>% str_subset("MemTotal")     # (rstudio-geo.nina.no, 260807): ~1056 GB !
mem_info %>% str_subset("MemAvailable") # (rstudio-geo.nina.no, 260807):  ~970 GB !
parallel::detectCores(logical = TRUE)   # (rstudio-geo.nina.no, 260807): 96 cores !

# preset suitable values -- customise as needed
#   (from Gemini): DuckDB functions best when allocated between 1 GB and 4 GB of RAM per active thread
nthreads= 32
memlimit= 200 # in GB

f_db1 <- file_temp(ext= "ddb") %>% {cat("\nDuckDB Database set to: ", ., "\n"); .}      # database in a temp file
conn_gk <- ddbs_create_conn(dbdir= f_db1, threads= nthreads, memory_limit_gb= memlimit) #
# side notes: 
#   * DuckDB automatically parallelises processes (hence it is very important to set cores and memory limits in the duckdb connection!)
#     With 10 cores and a memory limit of 30GB, it takes about 1h-2h for the union and cleaning to run on one dataset. 
#     So in total, the code below should take about 4-5h (patience is a virtue!). 

if (F) {  ### -- potentially useful database commands 
  conn_gk %>% dbGetInfo() %>% pluck("dbname")               # to locate the temp file used
  conn_gk %>% dbGetQuery("PRAGMA database_size;")           # to query database size
  conn_gk %>% dbExecute("DROP TABLE IF EXISTS gk_raw")      # to delete a specific table
  ddbs_stop_conn(conn_gk)     # to close the connection (does not instantly delete the temp file, it will only be deleted at session end)
  }

# # conn2 <- ddbs_create_conn(f_tmp) # 
# # as_duckspatial_df("gk_valid", conn2) %>% head %>% ddbs_collect() %>% st_crs
# # ddbs_stop_conn(conn2)     


###
###
### Load GK input files ---
###

gdb_files <-  dir_ls(gdb_folder, regexp = "gdb$") 

# BC: EDA phase -- restrict the exercise to a single fylke ---------------------------------!!!!
gdb_file1 <- gdb_files[str_detect(gdb_files,"/32_")] # fylke #32 is Akershus
fID_file1 <- gdb_file1 %>% str_extract("(?<=format/).{2}") %>% paste0("f",.) # RE finding "format/", and pulling out the next 2 characters
# gk_crs <- st_read(gdb_files[1], query = "SELECT * FROM arealregnskap LIMIT 10") %>% st_crs()
# ------------------------------------------------------------------------------------------

ddbs_open_dataset(gdb_file1) %>% #, layer= "arealregnskap", geom_col= "geo") %>% # starts a lazy ddbs object (in memory)
  mutate(f_id= fID_file1) %>%  # fylkes are used as "tiles" -- using fid or fID as colname would be in conflict with GeoPackage primary key(!)
  # mutate(eID= okosystemtype_kode %>% str_split_i(fixed("."), 1) %>% as.numeric %>% sprintf('e%02d', .)) %>%
  mutate(e_id= sql("'e' || lpad(split_part(okosystemtype_kode, '.', 1), 2, '0')")) %>% # the dbplyr-compatible version of the line above
  select(f_id, e_id, et_name= okosystemtype_1, areal_m2, geo) %>% 
  ddbs_write_table(conn= conn_gk, name= "gk_raw", overwrite =T) %>% # evaluates the lazy object & save it to the DB
  time_pipe() # puts the whole pipe into a timing wrapper   ~30s

if (F) { ### -- optional DB inspection 
  ddbs_list_tables(conn_gk)
  conn_gk %>% dbGetQuery("PRAGMA database_size;")
  conn_gk %>% dbGetQuery("SELECT * FROM gk_raw LIMIT 100" ) %>% str()
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw") 
  tbl(conn_gk, "gk_raw") %>% glimpse()  # an alternative way to inspect the structure
  #
  # Visual smoke tests
  exec(h_zoomplot, "gk_raw", "e_id", !!!(zoom1))  #--> test plot looks nice :)
  } 


###
###
### From raw GK to clean level-1 ET maps ---
###

# remove slivers
as_duckspatial_df("gk_raw", conn_gk) %>% 
  mutate(geo = sql("(UNNEST(ST_Dump(geo))).geom")) %>% # explode possible MULTIPOLYGONS into individual POLYGONS
  mutate(area_m2_proj = sql("ST_Area(geo)")) %>%       # now calculate area for the individual polygons
  dplyr::filter(area_m2_proj > th_sliver) %>%          # sliver cleaning
  mutate(geo= sql("ST_MakeValid(geo)")) %>% 
  # mutate(area_m2_valid= sql("ST_Area(geo)"))           # recalculate areas (is this needed?)
  ddbs_write_table(conn= conn_gk, name= "gk_valid", overwrite =T) %>%
  time_pipe() # ~30s
h_cleanup_db(conn_gk)
# side note: 
#   * these "mutate+sql" operations use memory/disk more efficiently (the ddbs_... couterparts create a temporary copy of the entire table)  

if (F) { ### Optional DB inspection 
  ddbs_list_tables(conn_gk)
  conn_gk %>% dbGetQuery("PRAGMA database_size;") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_valid")  # in Østfold ~16000 (~4%) polygons have area < 0.5m2 (most of them are also <0.05m2) 
  conn_gk %>% dbGetQuery("SELECT * FROM gk_raw LIMIT 100" ) %>% str()
  conn_gk %>% dbGetQuery("SELECT * FROM gk_valid LIMIT 100" ) %>% str()
  #  
  # Validity checks - should all disply 0 rows
  ddbs_is_valid("gk_valid", conn= conn_gk) %>% filter(!is_valid) %>% ddbs_collect %>% nrow
  ddbs_is_empty("gk_valid", conn= conn_gk) %>% filter(is_empty) %>% ddbs_collect %>% nrow
  ddbs_is_simple("gk_valid", conn= conn_gk) %>% filter(!is_simple) %>% ddbs_collect %>% nrow
  #
  # Visual smoke tests
  exec(h_zoomplot, "gk_raw", "e_id", !!!(zoom1))  # the previous plot again 
  exec(h_zoomplot, "gk_valid", "e_id", !!!(zoom1))  # gk_valid no: visible difference (as expected)
  #
  # Optional export (intermediate product)
  f_tmp <- file_temp(ext="ddb")
  as_duckspatial_df("gk_valid", conn= conn_gk) %>%
    ddbs_write_dataset(f_tmp, gdal_driver= "GPKG", overwrite= T, layer= "gk_valid")
    # ..., crs = "EPSG:25832",...  # BC: unsure if this is needed...
  }

# Dissolve polygons based on level-1 ET
#   an optimised pure-SQL alternative (suggested by Gemini, works directly within the DB)
#   writes the results directly into conn_gk, and returns a single number (the number of rows touched) 
dbExecute(conn_gk, " 
  CREATE OR REPLACE TABLE gk_union AS 
    WITH dumped AS (
      SELECT e_id, f_id, 
        UNNEST(ST_Dump(ST_Union_Agg(geo))) AS dump_struct
      FROM gk_valid
      GROUP BY e_id, f_id)
    SELECT e_id, f_id, 
      ST_MakeValid(dump_struct.geom) AS geo
    FROM dumped ") %>% 
  time_pipe(unit="mins") # ~5 min (for Akershus)

if (F) { ### Optional DB inspections
  ddbs_list_tables(conn_gk)
  conn_gk %>% dbGetQuery("PRAGMA database_size;") %>% print()
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw") %>% {.[[1]]}
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_valid") %>% {.[[1]]}
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_union") %>% {.[[1]]} # the N of polygons is drastically reduced (to ~20% of its orig value)
  conn_gk %>% dbGetQuery("SELECT * FROM gk_union LIMIT 100" ) %>% str() #only 3 cols: e_id, f_id, & geo (with a POLYGON geometry)
  #
  # Visual smoke tests
  exec(h_zoomplot, "gk_raw", "e_id", !!!(zoom1))  # gk_raw again 
  exec(h_zoomplot, "gk_union", "e_id", !!!(zoom1))  # gk_union: most internal boundaries (eg. in e01-urban, e04-forest) disappeared... 
    # ... but a few still remain, plus some very narrow channels & small islands -- these are still "nuisance" from an EC perspective)
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
# glue(out_etm, fID= "f31", yr=yr) %>% 
#   ddbs_open_dataset(geom_col= "geo") %>%
#   ddbs_write_table(conn= conn_gk, name= "gk_union", overwrite =T)
# ddbs_list_tables(conn_gk)
# tbl(conn_gk, "gk_union") %>% glimpse()  


# Define SQL query templates
query_DE <- " -- dilation --> erosion
  CREATE OR REPLACE TABLE {oo} AS 
  WITH dilated_and_unioned AS (
    SELECT ST_Union_Agg(ST_Buffer(geo, {bd})) AS merged_geo
    FROM {ii}
    WHERE e_id = '{e_id}'
      AND geo IS NOT NULL
    ),
  eroded AS (
    SELECT ST_Buffer(merged_geo, -{bd}) AS closed_geo
    FROM dilated_and_unioned
    WHERE merged_geo IS NOT NULL
    ),
  dumped AS (
    SELECT UNNEST(ST_Dump(closed_geo)) AS dump_struct
    FROM eroded
    WHERE closed_geo IS NOT NULL
    )
  SELECT ST_MakeValid(dump_struct.geom) AS geo
  FROM dumped"

query_ED  <- " -- erosion --> dilation 
  CREATE OR REPLACE TABLE {oo} AS 
  WITH eroded AS (
    SELECT ST_Buffer(geo, -{bd}) AS eroded_geo
    FROM {ii}
    WHERE e_id = '{e_id}'
      AND geo IS NOT NULL
    ),
  dilated_and_unioned AS (
    SELECT ST_Union_Agg(ST_Buffer(closed_geo, {bd})) AS merged_geo
    FROM eroded
    WHERE eroded_geo IS NOT NULL
    ),
  dumped AS (
    SELECT UNNEST(ST_Dump(merged_geo)) AS dump_struct
    FROM dilated_and_unioned
    WHERE merged_geo IS NOT NULL
    )
  SELECT ST_MakeValid(dump_struct.geom) AS geo
  FROM dumped"

## pilot exercise: pick one specific ET #urban
#  with method s2

format(Sys.time(), "%H:%M:%S")
query_DE %>% 
  glue(ii="gk_union", oo="gk_DE", bd= th_morph/2, e_id= "e01") %>%
  dbExecute(conn= conn_gk) %>%
  time_pipe(unit="mins")
format(Sys.time(), "%H:%M:%S")

out_tmp <- out_folder %>% path("BC", "tmp_{e_id}_{f_id}_{yr}-{nn}.gpkg")
as_duckspatial_df("gk_DE", conn= conn_gk) %>% # export as a geopackage
  ddbs_write_dataset(glue(out_tmp, e_id="e01", f_id= "f32", yr=yr, nn=1), gdal_driver= "GPKG", overwrite= T) %>%  # Akershus
  time_pipe() # ~30s


ddbs_list_tables(conn_gk)
conn_gk %>% dbGetQuery("PRAGMA database_size;") %>% print()

#
# Visual smoke tests
exec(h_zoomplot, "gk_raw", "e_id", !!!(zoom1))  # the previous plot again 
exec(h_zoomplot, "gk_valid", "e_id", !!!(zoom1))  # gk_valid no: visible difference (as expected)

