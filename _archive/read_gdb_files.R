#' Read the spatial data whitin gdb files
#'
#' This function reads the spatial data within gdb files.

#' @param gdb_path is the path(s) to the gdb files. Should be character.
#' 
#' 
#' @export
#'
#' @examples

# Code co-created by Sylvie Clappe and Jennifer Hansen
read_gdb <- function(gdb_path) {
  
  # Catch reading error
  tryCatch({
    layer <- st_read(dsn = gdb_path, layer = "arealregnskap")
    
  }, error = function(e) {
    
    message("Error reading: ", gdb_path, "\n", e)
    return(NULL)  # error handling
    
  })
  
  # if reading failed
  if (is.null(layer)) {
    return(NULL)
  }

  return(layer)
}



# read_gdb <- function(gdb_path, projection_crs) {
#   
#   # Catch reading error
#   tryCatch({
#     layer <- st_read(dsn = gdb_path, layer = "arealregnskap")
#   
#     }, error = function(e) {
#     
#       message("Error reading: ", gdb_path, "\n", e)
#     return(NULL)  # error handling
#   
#       })
#   
#   # if reading failed
#   if (is.null(layer)) {
#     return(NULL)
#   }
#   
#   
#   # Reproject the layer if CRS is not the one intended
#   if (st_crs(layer) != projection_crs) {
#     layer <- st_transform(layer, crs = projection_crs)
#   }
#   
#   
#   # Make geometry valid
#   layer_valid <- tryCatch({
#     st_make_valid(layer)
#   }, error = function(e) {
#     
#     message("st_make_valid() failed for ", gdb_path, ": ", conditionMessage(e),
#             "\nFalling back to st_buffer(dist = 0)")
#     
#     st_buffer(layer, dist = 0)
#  
#      })
#   
#   return(layer_valid)
# }