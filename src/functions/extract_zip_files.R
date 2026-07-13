#' Extract zip files listed with `files_list_one_fn` or `files_list_sev_fn`
#'
#' This function extracts all the zip files that are present in one or more folders
#' and listed by `files_list_one_fn` or `files_list_sev_fn`. This function has been 
#' designed for Copernicus rasters downloaded from the Copernicus platform. It can
#' mask the raster with a selected maks. It returns the raster and writes it on the disk.

#' @param path_read is the path to the zip files to read. Typically the first item of the list
#' returned by `files_list_one_fn` or `files_list_sev_fn`.
#' 
#' @param norway_mask is a shapefile used to mask the rasters to be read and written,
#' if relevant. Its defaut value is NULL, which means that no mask is applied.
#' 
#' @param path_write is the path to where the rasters should be written on the disk.
#' This cannot be first item of the list returned by `files_list_one_fn` or 
#' `files_list_sev_fn` because these are path containing the pattern `/vsizip/{`. 
#' A new path has to be written here. It should not contain the name of the raster.
#' 
#' @param files_names is the name of the raster. Typically the second item of the list
#' returned by `files_list_one_fn` or `files_list_sev_fn`.
#' 
#' @export
#'
#' @examples

process_raster_fn <- function(path_read, norway_mask = NULL, path_write, files_names){
  
  # Load libraries for parallel computing
  library(terra)
  library(sf)
  
  # Read
  tif_rast <- rast(path_read)
  
  if(is.null(norway_mask) == FALSE){
    # Re-project norway boundary
    norway_mask_pj <- st_transform(norway_mask, crs = crs(tif_rast))
    
    # Test overlap, crop and export 
    ext_tif_rast <- ext(tif_rast)
    ext_no <- ext(norway_mask_pj)
    test_intersect <- intersect(ext_tif_rast, ext_no)
    if(is.null(test_intersect) == TRUE){
      return("Not in Norway")
    } else{
      # Mask
      rast_tif_no_mask <- crop(tif_rast, norway_mask_pj, mask = TRUE)
      
      # Clean values 255
      tif_rast_reclfy <- classify(rast_tif_no_mask, cbind(255,NaN))
      levels(tif_rast_reclfy) <- levels(tif_rast)[[1]]
      
      # Export
      writeRaster(tif_rast_reclfy, paste0(path_write, files_names, "_NOcln.tif"))
      
      return("Successfully written")
    }
    
  }else{
    
    # Export
    writeRaster(tif_rast, paste0(path_write, files_names, ".tif"))
    
    return("Successfully written")
  }
  
  
}
