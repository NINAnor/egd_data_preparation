#' Read data from Geonroge through an API request
#'
#' This function aims at reading Norway administrative boundaries spatial data 
#' from Geonorge in EPSG:25833, and format .gdb through an API request. It is not 
#' guaranteed that this function will work "as is" with all Geonorge datasets, 
#' minor adjustments might be needed. If the user wishes to download using another 
#' project than EPSG:25833, the code of the function should be modified to reflect 
#' this. Likewise, the code buidls the API request based on the geographic area
#' requested. THe code needs to be updated (looking at cap_choice) to reflect
#' the correct goegraphic area.

#' @param geonorge_url the access url of the Geonorge dataset. It should be entered as a
#' character. Displayed in Geonorge webpage of the dataset.
#' 
#' @param email_address the email address that should be put in the API request
#'
#' @return the function downloads the data into a temporary file and read the data
#' from there. The function thus returns the path of all .gdb file that have been
#' downloaded in the temporary directory.
#' 
#' @export
#'
#' @examples

api_geonorge <- function(geonorge_url, email_address){
  
  # Libraries
  library(httr2)
  library(dplyr)
  
  if(is.character(geonorge_url) == FALSE){
    
    return("The URL should be entered as a character.")
    
  }else{
    
    #1# dataset specific ID from Geonorge
    dataset_uuid <- basename(geonorge_url)
    
    #2# httr2:::req_perform() sends API request for dataset's capabilities
    dt_cap <- request(sprintf(geonorge_url)) %>% # create request
      req_headers("Accept" = "application/json") %>% # create request
      req_perform()
    
    cap_all <- resp_body_json(dt_cap, simplifyVector = TRUE)
    
    #3# Extract the capablities into a dataframe so it's easier to choose from
    cap_choice <- request(cap_all$`_links`[cap_all$`_links`$rel == "http://rel.geonorge.no/download/area", "href"]) %>%
                    req_perform() %>%
                    resp_body_json()
    
    projection <- cap_choice[[373]]$projections[[1]] # ESPG:25833
    
    format <- cap_choice[[373]]$formats[[2]]$name # FILEGDB
    
    area <- cap_choice[[373]] # Norway with Svalbard
    
    order_url <- cap_all$`_links`[cap_all$`_links`$rel == "http://rel.geonorge.no/download/order", "href"]
    
    #4# Create the order by listing the dataset id and capabilities of relevance
    order_body <- list(
      downloadAsBundle = FALSE,
      email = {{email_address}},
      orderLines = list(
        list(
          areas = list(
            list(
              code = area$code,  
              name = area$name,
              type = area$type
            )
          ),
          formats = list(
            list(name = format)
          ),
          metadataUuid = dataset_uuid,
          projections = list(
            list(
              code = projection$code,
              name = projection$name,
              codespace = projection$codespace
            )
          )
        )
      )
    )
    
    
    order_req <- request(order_url) %>% # create request
      req_body_json(order_body) %>% # create request
      req_headers("Accept" = "application/json") %>% # create request
      req_perform() # send request
    
    order_info <- resp_body_json(order_req)
    
    #5# Download
    
    # URL to download the data
    down_url <- order_info$files[[1]]$downloadUrl
    
    # Create a temporary directory to store the dataset .zip and unzipped
    temp_dir <- tempdir()
    
    # Create a temporary file to store the dataset .zip
    destination_tmp <- tempfile(fileext = ".zip", tmpdir = temp_dir)
    
    # Download the .zip file containing the dataset
    download.file(down_url, destfile = destination_tmp, mode = "wb")
    
    # Unzip the .zip
    unzip(destination_tmp, exdir = temp_dir)
    
    # Use "\\.gdb$" pattern to identify the file to read
    gdb_file <- list.files(temp_dir, pattern = "\\.gdb$", full.names = TRUE)
    
    }
    
    return(gdb_file)
  }
  

