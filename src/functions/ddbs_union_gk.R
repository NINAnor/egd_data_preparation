#' Union the polygons of one ecosystem type at level 1 of the Grunnkart
#'
#' This function merges all the polygons of one ecosystem type at level 1
#' of the Grunnkart across all the available tiles (fylke). This results in
#' on table of united polygons for the ecosystem type of interest.
#'
#'This function allows for the users to choose to either do the union across
#'all tiles, or do the union more progressively by first merging across groups
#'of tiles, before merging again across the groups. This helps with memory issues
#'and computing time.
#'
#' @param duckspatial_obj is a duckspatial object, or an sf object. 
#' 
#' @param union_col is the column by which the union should be performed. It can be
#'  one column name or a vector of column names. This argument should be a character.
#' 
#' @param conn name of the duckdb connection
#' 
#' @param output_name name of output layer. Should be a character.
#' 
#' 
#' @export
#'
#' @examples

ddbs_union_gk <- function(duckspatial_obj, union_col, conn_name, output_name){
  
  duckspatial_obj %>%
    
      # union
      ddbs_union_agg(by = union_col) %>% 
      
      # cast complex geom into simple polygons
      ddbs_dump() %>%
      
      # make geometry valid
      ddbs_make_valid(conn = conn_name,
                      name = output_name)
    
}