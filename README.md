## Purpose of this document
This document gives brief information on project 112644 -  Ferdigstilling av indikatorer til Eurostat og nasjonalt naturregnskap. It also provides information on how to run the code, the data, packages and functions used.

## Project
This project was commissioned by Miljødirektoratet to NINA over the summer 2026 for a deadline on the 30th of September 2024. The purpose of the this project is to re-run the condition indicators from ecRxiv that have to be reported to Eurostat under Regulation 2024/3024. Here we only are concerened with three indicators:

- URGR (share of blue/green spaces in cities)
- URAQ (concentration pf PM2.5)
- TCCD (tree cover density)

The code was taken from ecRxiv and adapted, the code is available in the ecrxiv_URGR_URAQ_TCCD repository. The sections on data preparation has been relocated in this repository.

## Structure of the R project
This project has 3 sub-folders:

- .src where the R scripts for the main code (.code) and functions (.functions) are available.


## Data

For this project I used:



Path where they are stored: R:\GeoSpatialData\Natur\Norway_Miljodirektoratet_KartlagteFriluftslivsomr\Original\Natur_NaturtyperUtvalgte_norge_med_svalbard_25833.zip

Path to metadata: https://kartkatalog.geonorge.no/metadata/friluftslivsomraader-kartlagte/91e31bb7-356f-4478-bcba-d5c2de6e91bc

## Packages
```{r}
library(sf)
```


## Functions
XX functions have been created for the purposes of this code:

- extract_zip_files.R: script creating virtual rasters.
- list_zip_files.R: script extracting the raster files from .zip files.

## Running the code
Two scripts have been designed:

- prep_Copernicus_IMD.qmd : script pre-processing Copernicus IMD for URGR condition indicators.
- prep_Grunnkart.qmd: script pre-processing the grunnkart for URGR, URAQ and TCCD condition indicators.
