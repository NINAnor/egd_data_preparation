#' List the zip files present in one or more folders
#'
#' This function lists all the zip files that are present in one or more folders.
#' It returns a list object with the path to the files and the name of the dataset.
#' This function has been designed for Copernicus datasets only. The paths returned
#' include `/vsizip/{` which is a prefix in GDAL Virtual File System (VSI) driver 
#' that allows you to read contents directly from a ZIP file without extracting it first.

#' @param path the path to the folder with the zip files (`files_list_one_fn`), 
#' or the path to the directory with the folders containing the zip files (`files_list_sev_fn`).
#' 
#' @export
#'
#' @examples

# List rasters to read within zip files in ONE folder------------------------------
files_list_one_fn <- function(path){
  files_names <- list.files(path, pattern = "\\.zip$", 
                            full.names = FALSE) %>%
    str_remove("\\.zip$")
  
  zip_files <- list.files(path, pattern = "\\.zip$", 
                          full.names = TRUE)
  
  files_to_read <- map_vec(seq_along(zip_files), function(i){paste0("/vsizip/{", zip_files[i], "}/", files_names[i], ".tif")})
  
  return(list(files_to_read, files_names))
}


# List rasters to read within zip files in MORE THAN ONE folder------------------------------

files_list_sev_fn <- function(path){
  
  files_names <- dir(path, recursive = TRUE, full.names = TRUE, pattern="\\.zip$") %>%
    str_remove("\\.zip$") %>%
    str_extract("CLMS.*")
  
  zip_files <- dir(path, recursive = TRUE, full.names = TRUE, pattern="\\.zip$")
  
  files_to_read <- map_vec(seq_along(zip_files), function(i){paste0("/vsizip/{", zip_files[i], "}/", files_names[i], ".tif")})
  
  return(list(files_to_read, files_names))
}