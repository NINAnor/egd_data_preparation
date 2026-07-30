#' Read and re-project Grunnkart data
#'
#' This function reads and transform to EPSG:25832 the Grunnkart data. These data
#' have one .gdb per county.
#'
#' @param data_path_gdb is the vector if paths to the geodatabase. Can have one or several paths.
#' 
#' @param conn name of the duckdb connection
#' 
#' @param crs_proj CRS projection of interest. 
#' 
#' 
#' @export
#'
#' @examples

# Code co-created by Sylvie Clappe and Jennifer Hansen
ddbs_read_and_transform_gk <- function(data_path_gdb, conn_name, crs_proj){
  
  # Tile name
  tile_name <- paste0("tile_", str_extract(data_path_gdb, "(?<=format/).{2}"))
  
  # Tile CRS
  tile_crs <- st_read(data_path_gdb, query = "SELECT * FROM arealregnskap LIMIT 10") %>%
    st_crs()
  
  # Ref to the tile
  ddbs_sd <- ddbs_open_dataset(data_path_gdb, 
                               layer = "arealregnskap", 
                               geom_col = "geo",
                               conn = conn_name) %>%
    mutate(tile_name = tile_name)
  
  # Re-project if tile is not in the CRS of interest
  if (!identical(tile_crs$wkt, crs_proj$wkt)) {
    ddbs_sd <- ddbs_sd %>% 
      ddbs_transform(y = gk_crs,
                     conn = conn_name)
  }
  
  # Write a new database
  if (!DBI::dbExistsTable(conn_name, "grunnkart_raw")) {
    
    # First tile: create the table
    ddbs_sd %>% 
      ddbs_write_table(conn = conn_name, name = "grunnkart_raw")
    
  } else {
    
    # Subsequent tiles: append
    rows_append(
      tbl(conn_name, "grunnkart_raw"),
      ddbs_sd,
      in_place = TRUE
    )
  }
  
  ddbs_sd %>%
  select(tile_name, id, okosystemtype_1, areal_m2, geo)
}