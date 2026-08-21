# ---------------------------------------
# 
# Helper functions and SQL queries for the Grunnkart pipeline (gk_pipeline.R)
#
# ---------------------------------------


###
###
### helper functions
###


### Clean up a duckDB database (conn): remove temporary tables & views  
h_cleanup_db <- function(conn) {   
  walk(dbListTables(conn), 
       \(x) switch(str_sub(x, 1, 9), 
                   temp_view= {dbExecute(conn, sprintf("DROP VIEW IF EXISTS %s", dbQuoteIdentifier(conn, x))); 0},
                   temp_tabl= {dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", dbQuoteIdentifier(conn, x))); 0},
                   1))
  }


### Custom zoom-in plots for visual inspection of duckspatial datasets
h_zoomplot <- function(tabl, feat=NULL, lon, lat, rr=2000, conn=conn_gk) { 
  # conn:    a connection (pointing at a duckspatial DB)
  # tabl:    name of a table in conn 
  # feat:    a colname in tabl (used for setting colours) 
  # lon,lat: unprojected coordinates of an interesting place (looked up e.g. from google maps) 
  # rr:      radius (m) around the point that should be shown
  crs1 <- as_duckspatial_df(tabl, conn=conn) %>% ddbs_crs() 
  # print(tabl); print(feat); print(lat); print(lon); print(rr); print(conn)
  zoombox <- c(lon, lat) %>% st_point %>% st_sfc(crs= 4326) %>% st_transform(crs1) %>% st_buffer(rr) %>% st_bbox() 
  as_duckspatial_df(tabl, conn=conn) %>%
    ddbs_crop(st_as_sf(st_as_sfc(zoombox))) %>%       # annoying false warning...
    collect() %>%
    mutate(types= if (is.null(feat)) "mask" else .data[[feat]]) %>%
    ggplot() + geom_sf(aes(fill= types), alpha=.33) + scale_fill_discrete() + theme_minimal() 
  }
# tabl="gk_raw"; feat= "e_id"; lon=10.7; lat=59.6; rr=1000; conn=conn_gk
# rm(tabl, feat, lon, lat, rr, conn)


### Interesting locations for inspection (--> use Google Maps to find relevant places & get their raw coordinates)

# https://www.google.com/maps/@59.6,10.7,1632m/data=!3m1!1e3
zoom1 <- list(lon=10.7, lat=59.6, rr=1000) # a messy place in  relevant for BmB2 (Elvia case)
# exec(h_zoomplot, "gk_raw", "e_id", !!!(zoom1)) #--> this is how zoom1 can be "splashed" into funbction calls 




###
###
### SQL query templates
###

### Glue knobs (all queries):
# {ii}:   input table name
# {oo}:   output table name
# {sv}:   sliver area threshold (t_sliver)
# {ts}:   topology tolerance bandwitdh (t_tol1, t_tol2) 
# {ns}:   number of points on circle segments for ST_Buffer (n_seg) 
# {bd}:   buffer distance for the morph operations (should be t_morph/2)
# {e_id}: ET identifier (e_id)
# {f_id}: fylke identifier (f_id)


### Dissolve (and slightly topology-simplify) ET maps 
#   preserving the integrity of the partition as much as possible ("relatively" exhaustive & mutually exclusive level-1 polygons)

# everything from raw to dissolved (slightly faster) 
query_dissolve_full <- "
  CREATE OR REPLACE TABLE {oo} AS
  WITH exploded AS (
    SELECT e_id, f_id, (UNNEST(ST_Dump(geom))).geom AS geom
    FROM {ii}),
  deslivered AS (
    SELECT e_id, f_id, geom
    FROM exploded
    WHERE ST_Area(geom) > {sv} AND geom IS NOT NULL),
  dissolved AS (
    SELECT e_id, f_id, UNNEST(ST_Dump(ST_Union_Agg(geom))) AS dump_struct
    FROM deslivered
    GROUP BY e_id, f_id)
  SELECT e_id, f_id, ST_MakeValid(dump_struct.geom) AS geom
  FROM dissolved"

# just the dissolve step
query_dissolve_only <- " 
  CREATE OR REPLACE TABLE {oo} AS 
    WITH dissolved AS (
      SELECT e_id, f_id, UNNEST(ST_Dump(ST_Union_Agg(ST_SimplifyPreserveTopology(geom, {ts})))) AS dump_struct
      FROM {ii} 
      GROUP BY e_id, f_id)
    SELECT e_id, f_id, ST_MakeValid(dump_struct.geom) AS geom
    FROM dissolved"
# # if used this query should be preambled with:
# as_duckspatial_df("gk_raw", conn_gk) %>% 
#   mutate(geom = sql("(UNNEST(ST_Dump(geom))).geom")) %>%  # explode possible MULTIPOLYGONS into individual POLYGONS
#   mutate(area_m2_proj = sql("ST_Area(geom)")) %>%         # now calculate area for the individual polygons
#   dplyr::filter(area_m2_proj > t_sliver) %>%              # sliver cleaning
#   mutate(geom= sql("ST_MakeValid(geom)")) %>% 
#   # mutate(area_m2_valid= sql("ST_Area(geom)"))           # recalculate areas (...if really needed(?))
#   ddbs_write_table(conn= conn_gk, name= "gk_valid", overwrite =T) 
# h_cleanup_db(conn_gk)



### Morphological filtering queries (DE: dilation-erosion, ED: erosion-dilation) 
#   a full filtering will consist of both directions: EDDE: method s1, and DEED: method s2

# a DE query handling all ETs (e01-e09) in one go
query_DE_all <- " 
  CREATE OR REPLACE TABLE {oo} AS
  WITH dilated_and_unioned AS (
    SELECT e_id, ST_Union_Agg(ST_Buffer(ST_SimplifyPreserveTopology(geom, {ts}), {bd}, {ns})) AS merged_geom
    FROM {ii} WHERE e_id <= 'e09' AND geom IS NOT NULL
    GROUP BY e_id),
  eroded AS (
    SELECT e_id, ST_Buffer(ST_MakeValid(merged_geom), -{bd}, {ns}) AS closed_geom
    FROM dilated_and_unioned WHERE merged_geom IS NOT NULL),
  dumped AS (
    SELECT e_id, UNNEST(ST_Dump(closed_geom)) AS dump_struct
    FROM eroded WHERE closed_geom IS NOT NULL)
  SELECT '{f_id}' AS f_id, e_id, dump_struct.geom AS geom
  FROM dumped"

# an ED query handling all ETs (e01-e09) in one go
query_ED_all <- " 
  CREATE OR REPLACE TABLE {oo} AS
  WITH eroded AS (
    SELECT e_id, ST_Buffer(ST_SimplifyPreserveTopology(geom, {ts}), -{bd}, {ns}) AS eroded_geom
    FROM {ii} WHERE e_id <= 'e09' AND geom IS NOT NULL),
  dilated_and_unioned AS (
    SELECT e_id, ST_Union_Agg(ST_Buffer(eroded_geom, {bd}, {ns})) AS merged_geom
    FROM eroded WHERE eroded_geom IS NOT NULL
    GROUP BY e_id),
  dumped AS (
    SELECT e_id, UNNEST(ST_Dump(merged_geom)) AS dump_struct
    FROM dilated_and_unioned WHERE merged_geom IS NOT NULL)
  SELECT '{f_id}' AS f_id, e_id, ST_MakeValid(dump_struct.geom) AS geom
  FROM dumped"

# a DE query handling just a single ET (={e_id})
query_DE <- " 
  CREATE OR REPLACE TABLE {oo} AS
  WITH dilated_and_unioned AS (
    SELECT ST_Union_Agg(ST_Buffer(ST_SimplifyPreserveTopology(geom, {ts}), {bd}, {ns})) AS merged_geom
    FROM {ii} WHERE e_id = '{e_id}' AND geom IS NOT NULL),
  eroded AS (
    SELECT ST_Buffer(ST_MakeValid(merged_geom), -{bd}, {ns}) AS eroded_geom
    FROM dilated_and_unioned WHERE merged_geom IS NOT NULL),
  dumped AS (
    SELECT UNNEST(ST_Dump(eroded_geom)) AS dump_struct
    FROM eroded WHERE eroded_geom IS NOT NULL)
  SELECT '{f_id}' AS f_id, '{e_id}' AS e_id, dump_struct.geom AS geom
  FROM dumped"

# an ED query handling just a single ET (={e_id})
query_ED  <- "
  CREATE OR REPLACE TABLE {oo} AS 
  WITH eroded AS (
    SELECT ST_Buffer(ST_SimplifyPreserveTopology(geom, {ts}), -{bd}, {ns}) AS eroded_geom
    FROM {ii} WHERE e_id = '{e_id}' AND geom IS NOT NULL),
  dilated_and_unioned AS (
    SELECT ST_Union_Agg(ST_Buffer(eroded_geom, {bd}, {ns})) AS merged_geom
    FROM eroded WHERE eroded_geom IS NOT NULL),
  dumped AS (
    SELECT UNNEST(ST_Dump(merged_geom)) AS dump_struct
    FROM dilated_and_unioned WHERE merged_geom IS NOT NULL)
  SELECT '{f_id}' AS f_id, '{e_id}' AS e_id, ST_MakeValid(dump_struct.geom) AS geom
  FROM dumped"

