# egd-data-preparation: General purpose preparatory scripts for ecosystem condition variable calculations  

## Context 
Many ecosystem condition variables rely on public datasets. 
Some of these datasets are required by multiple EC variables. 
**Ecosystem type maps** are particularly important such multi-purpose datsets. 

If such multi-purpose variables require a series of data preparation steps, then these it makes sense to 
decouple the  data preparation. This makes the EC variable calculation pathways cleaner, more modular, 
and more efficient (the shared data preparation steps do not need to be repeated for each EC variable). 
This also makes the variable descriptions in the [ecRxiv](https://ecrxiv.com/) simpler, clearer, and less redundant. 

Here we present such *shared data preparation steps* for a number of primary datasets relevant for the the calculation of EC variables. 
We particularly focus on the data needs of variables URGR, URAQ and TCCD, as well as a general purpose dataset for ET maps:

- the [GK dataset](GK.md)
- [Copernicus IMD](xxx.md)
- [Copernicus TCD](xxx.md)

The preprocessing of each dataset is described in detail in the dedicated document linked above.

---
<!-- BC: From here I did not change this file. We might want to update the rest of the file, too when we arrived on the final structure/content --> 


## Structure of the R project
This project has 3 sub-folders:

- .src where the R scripts for the main code (.code) and functions (.functions) are available.


## Data

For this project I used:



Path where they are stored: R:\GeoSpatialData\Natur\Norway_Miljodirektoratet_KartlagteFriluftslivsomr\Original\Natur_NaturtyperUtvalgte_norge_med_svalbard_25833.zip

Path to metadata: https://kartkatalog.geonorge.no/metadata/friluftslivsomraader-kartlagte/91e31bb7-356f-4478-bcba-d5c2de6e91bc

## Packages
```{r}
library(knitr)
library(tidyverse)
library(kableExtra)
library(here)
library(yaml)
library(tibble)
library(conflicted)
library(duckdb)
library(duckspatial)
library(sf)
library(dplyr)
library(stringr)
library(terra)

```


## Functions
Three functions have been created for the purposes of this code:

- extract_zip_files.R: script creating virtual rasters.
- list_zip_files.R: script extracting the raster files from .zip files.
- ddbs_union_gk.R: does spatial union and clean geometries.

## Running the code
Two scripts have been designed:

- prep_Copernicus_IMD.qmd : script pre-processing Copernicus IMD for URGR condition indicators.
- prep_Grunnkart.qmd: script pre-processing the Grunnkart for URGR, URAQ and TCCD condition indicators.
- prep_PM.qmd: script pre-processing PM2.5 data for URAQ indicators.
