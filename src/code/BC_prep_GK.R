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


###
###
### Config ---

# import paths
gdb_folder <- path("/data/R/GeoSpatialData/LandUse/Norway_Arealregnskap/Original/GrunnkartArealregnskap FGDB-format")
gdb_files <-  dir_ls(gdb_folder, regexp = "gdb$") 

# knobs
yr <- "2025"      # year of the GK data processed
th_sliver <- 0.5  # sliver threshold [m2] (polygons smaller than this will be dropped)
th_morph  <- 20   # morphological threshold [m] (2x of the erosion/dilation buffer width used in both simplification methods)
                  
# export paths (use with glue::glue)
# out_folder <- "P:/412413_2023_no_egd/git_data/GK_processed/"
out_folder <- "~/Mounts/P-Prosjekter2/412413_2023_no_egd/git_data/GK_processed/"
out_etm <- out_folder %>% path("BC", "GK_ETM_L1_{fID}_{yr}.gpkg")     # dissolved ET maps per fylke (or national level for "f00")
out_ms1 <- out_folder %>% path("BC", "GK_s1_{eID}_{fID}_{yr}.gpkg")   # simplified masks with method s1 for ET eID and fylke fID (or national for "f00") 
out_ms2 <- out_folder %>% path("BC", "GK_s2_{eID}_{fID}_{yr}.gpkg")   # simplified masks with method s2 for ET eID and fylke fID (or national for "f00") 


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
nthreads= 20
memlimit= 100 # in GB

# conn_gk <- ddbs_create_conn(dbdir= "tempdir", threads= nthreads, memory_limit_gb= memlimit)
f_db1 <- file_temp(ext= "ddb") 
conn_gk <- ddbs_create_conn(threads= nthreads, memory_limit_gb= memlimit, dbdir= f_db1) # let's try the default ("memory") -- individual fylke's should fit into memory
# side notes: 
#   * these "mutate+sql" operations use memory/disk more efficiently (the ddbs_... couterparts create a temporary copy of the entire table)  
#   * DuckDB automatically parallelises processes (hence it is very important to set cores and memory limits in the duckdb connection!)
#     With 10 cores and a memory limit of 30GB, it takes about 1h-2h for the union and cleaning to run on one dataset. 
#     So in total, the code below should take about 4-5h (patience is a virtue!). 

if (F) {  ### -- potentially useful database commands 
  conn_gk %>% dbGetInfo()$dbname                                # to locate the temp file used
  conn_gk %>% dbGetQuery("PRAGMA database_size;")           # to query database size
  conn_gk %>% dbExecute("DROP TABLE IF EXISTS gk_raw")    # to delete a specific table
  ddbs_stop_conn(conn_gk)     # to close the connection (does not instantly delete the temp file, it will only be deleted at session end)
  }

# # conn2 <- ddbs_create_conn(f_tmp) # 
# # as_duckspatial_df("gk_valid", conn2) %>% head %>% ddbs_collect() %>% st_crs
# # ddbs_stop_conn(conn2)     


###
###
### Load GK input files ---
###

# BC: EDA phase -- restrict the exercise to a single fylke ---------------------------------!!!!
gdb_file1 <- gdb_files[str_detect(gdb_files,"/31_")] # fylke #31 is Østfold, a tiny fylke
fID_file1 <- gdb_file1 %>% str_extract("(?<=format/).{2}") %>% paste0("f",.) # RE finding "format/", and pulling out the next 2 characters
# gk_crs <- st_read(gdb_files[1], query = "SELECT * FROM arealregnskap LIMIT 10") %>% st_crs()
# ------------------------------------------------------------------------------------------

db_gk_raw <- gdb_file1 %>%  # a lazy ddbs object (linked to a temporary table in the connection?)
  ddbs_open_dataset(layer= "arealregnskap", geom_col= "geo") %>%
  mutate(fID= fID_file1) %>%  # fylkes are used as "tiles"
  # mutate(eID= okosystemtype_kode %>% str_split_i(fixed("."), 1) %>% as.numeric %>% sprintf('e%02d', .)) %>%
  mutate(eID= sql("'e' || lpad(split_part(okosystemtype_kode, '.', 1), 2, '0')")) %>% # the dbplyr-compatible version of the line above
  select(fID, eID, et_name= okosystemtype_1, areal_m2, geo) 
db_gk_raw %>%
  ddbs_write_table(conn= conn_gk, name= "gk_raw", overwrite =T) # do the maths & make the temp table permanent

if (F) { ### -- optional database ispection 
  ddbs_list_tables(conn_gk)
  conn_gk %>% dbGetQuery("PRAGMA database_size;")
  conn_gk %>% dbGetQuery("SELECT * FROM gk_raw LIMIT 100" ) %>% str()
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw") 
  tbl(conn_gk, "gk_raw") %>% glimpse()  # an alternative way to inspect the structure
  } 


###
###
### From raw GK to clean level-1 ET maps ---
###

# recalculate areas and remove slivers
db_gk_valid <- as_duckspatial_df("gk_raw", conn_gk) %>%
  mutate(geo = sql("(UNNEST(ST_Dump(geo))).geom")) %>% # explode possible MULTIPOLYGONS into individual POLYGONS
  mutate(area_m2_proj = sql("ST_Area(geo)")) %>%       # now calculate area for the individual polygons
  dplyr::filter(area_m2_proj > th_sliver) %>%          # sliver cleaning
  mutate(geo= sql("ST_MakeValid(geo)")) %>%            
  mutate(area_m2_valid= sql("ST_Area(geo)"))           # recalculate areas (to be on the safe side...)
  # side notes: 
  #   * these "mutate+sql" operations use memory/disk more efficiently (the ddbs_... couterparts create a temporary copy of the entire table)  
db_gk_valid %>% 
  ddbs_write_table(conn= conn_gk, name= "gk_valid", overwrite =T)  # checkpoint - create a new table in duckdb database

if (F) { ### Optional inspections 
  ddbs_list_tables(conn_gk)
  conn_gk %>% dbGetQuery("PRAGMA database_size;") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw") 
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_valid")  # in Østfold ~16000 (~4%) polygons have area < 0.5m2 (most of them are also <0.05m2) 
  conn_gk %>% dbGetQuery("SELECT * FROM gk_raw LIMIT 100" ) %>% str()
  conn_gk %>% dbGetQuery("SELECT * FROM gk_valid LIMIT 100" ) %>% str()
  
  # Validity checks - should all disply 0 rows
  ddbs_is_valid("gk_valid", conn= conn_gk) %>% filter(!is_valid) %>% ddbs_collect %>% nrow
  ddbs_is_empty("gk_valid", conn= conn_gk) %>% filter(is_empty) %>% ddbs_collect %>% nrow
  ddbs_is_simple("gk_valid", conn= conn_gk) %>% filter(!is_simple) %>% ddbs_collect %>% nrow
  
  # Optional export (intermediate product)
  f_tmp <- file_temp(ext="ddb")
  as_duckspatial_df("gk_valid", conn= conn_gk) %>%
    ddbs_write_dataset(f_tmp, gdal_driver= "GPKG", overwrite= T, layer= "gk_valid")
    # ..., crs = "EPSG:25832",...  # BC: unsure if this is needed...
  }

# Clean duckdb databse
dbListTables(conn_gk) %>%
  walk(\(x) switch(str_sub(x, 1, 9), 
                   temp_view= {dbExecute(conn_gk, sprintf("DROP VIEW IF EXISTS %s", dbQuoteIdentifier(conn_gk, x))); 0},
                   temp_tabl= {dbExecute(conn_gk, sprintf("DROP TABLE IF EXISTS %s", dbQuoteIdentifier(conn_gk, x))); 0},
                   1))
# ddbs_list_tables(conn_gk) # inspect list of tables

# Dissolve polygons based on level-1 ET
  # # Sylvie's original solution:
  # db_gk_union <- as_duckspatial_df("gk_valid", conn= conn_gk) %>% # a lazy duckspatial_sf object
  #   ddbs_union_agg(by= "eID") %>%  # dissolve
  #   ddbs_dump() %>%                # cast complex geom into simple polygons
  #   ddbs_make_valid(conn= conn_gk, name= "gk_union")
# an optimised pure-SQL alternative (suggested by Gemini, does not need a pipe) 
dbExecute(conn_gk, "
  CREATE OR REPLACE TABLE gk_union AS 
    WITH dumped AS (
      SELECT 
        eID, fID, 
        UNNEST(ST_Dump(ST_Union_Agg(geo))) AS dump_struct
      FROM gk_valid
      GROUP BY eID, fID
      )
    SELECT 
      eID, fID, 
      ST_MakeValid(dump_struct.geom) AS geo
    FROM dumped  
  ") # writes the new table into conn_gk, and returns a single number (the number of remaining rows) ...~1 min/100k polygons)

if (F) { ### Optional inspections
  ddbs_list_tables(conn_gk)
  conn_gk %>% dbGetQuery("PRAGMA database_size;") %>% print()
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_raw") %>% {.[[1]]}
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_valid") %>% {.[[1]]}
  conn_gk %>% dbGetQuery("SELECT COUNT(*) FROM gk_union") %>% {.[[1]]} # the N of polygons is drastically reduced (to ~20% of its orig value)
  conn_gk %>% dbGetQuery("SELECT * FROM gk_union LIMIT 100" ) %>% str() #only 3 cols: eID, fID, & geo (with a POLYGON geometry)
  }

# Export level-1 ETM for each fylke (-- except the national "f00")
as_duckspatial_df("gk_union", conn= conn_gk) %>% # export as a geopackage
  ddbs_write_dataset(glue(out_etm, fID= "f31", yr=yr), gdal_driver= "GPKG", overwrite= T)  # Østfold: 345 MB


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

query_DE <- " -- dilation --> erosion
  CREATE OR REPLACE TABLE {oo} AS 
  WITH dilated_and_unioned AS (
    SELECT ST_Union_Agg(ST_Buffer(geo, {bd})) AS merged_geo
    FROM {ii}
    WHERE eID = '{eid}'
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
    WHERE eID = '{eid}'
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
  glue(ii="gk_union", oo="gk_DE", bd= th_morph/2, eid= "e01") %>%
  dbExecute(conn= conn_gk)
format(Sys.time(), "%H:%M:%S")

out_tmp <- out_folder %>% path("BC", "tmp_{eID}_{fID}_{yr}-{nn}.gpkg")
ddbs_list_tables(conn_gk)
conn_gk %>% dbGetQuery("PRAGMA database_size;") %>% print()


