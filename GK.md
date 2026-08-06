# Data pre-processing for the Norwegian **Nasjonalt Grunnkart for arealanalyse**  

## Introduction

The Grunkart (GK, Nasjonalt grunnkart for arealanalyse) dataset is a national ecosystem type (ET) map of Norway. 
One of its main purposes is to support the development of ecosystem extent and condition accounts (arealregnskap, tilstandsregnskap). 
Nevertheless, it's does not apply a consistent "functional ecosystem" perspective, and it is also challenged by several technical problems. 

Accordingly it falls short of its declared purpose in several respects:
* For some map features & land cover types types (especially artificial objects) it applies very fine-scale spatial distinctions 
  (individual buildings, small roads), while for others it just provides a broad-brush picture
* The thematic resolution of the dataset is also uneven: for urban ecosystems lots of tiny "ecosystem subtypes" are distinguished 
  (based on land use/cover), for most of the other, ecologically more relevant ETs there are no subtypes identified.   

Consequently, the dataset does not consistently follow a "functional ecosystem" perspective, with a clear MMU-based 
operationalisation (Rendon et al. 2025). 
This results in a very complex and fragmented polygon dataset (especially in urban areas), which is of huge size.
In addition, the final polygon dataset of Version 2025 still contains many geometric errors, inconsistencies, tiny sliver polygons, etc. 

The geometric challenges and the huge file sizes make the original vector files very difficult to work with. 
In addition, spatial and thematic resolution inconsistencies are also conceptually problematic, 
especially for ecosystem condition accounting (Rendon et al. 2025).

Here we present a general preprocessing of the Grunnkart (version 2025) which aims to reduce the spatial and thematic 
complexity of the dataset, and to produce simple coherent and thematically balanced ET masks designed to support spatial 
calculations with ecosystem condition variables. 

## Data sources

| Dataset name | Citation | Original URI | NINA URI |
|------|------|------|------------|
| Nasjonalt grunnkart for arealanalyse, Årsversjon 2025 | Aune-Lundberg et al., 2025 | [GeoNorge](https://kartkatalog.geonorge.no/metadata/nasjonalt-grunnkart-for-arealanalyse/28c28e3a-d88f-4a34-8c60-5efe6d56a44d) | "R:/GeoSpatialData/LandUse/Norway_Arealregnskap/Original/GrunnkartArealregnskap FGDB-format"


## Methods

EC variables are always linked to one or more specific ETs. Working with such EC variables thus requires information about 
the spatial distribution of their "parent" ETs (ET masks). For this purpose,
 * we perform geometric corrections on the polygon geometries,
 * we dissolve all polygons representing level-2 ET subtypes into their level-1 ET class.

This results in a clean level-1 spatial partition of the terrestrial area of mainland Norway (*level-1 ET map*, all ETs). 

In addition, we also produce further *simplified ET masks* for specific ecosystem types. 
For this, we always start out form the polygons belonging to a single ET, and then we simplify its spatial structure 
in a series of dilation & erosion operations, which makes e.g. small fragments of the ET disappear, and small holes 
within the ET to be filled in. Here we followed two different approaches:

* simplification method **s1**: erosion followed by dilation, optimised for "simplicity", 
  slightly "underestimating" the area of in complex mosaic landscapes. 
* simplification method **s2**: dilation followed by erosion, optimised for maintaining "connectivity", 
  slightly "overestimating" in complex mosaic landscapes.



The series of these simplified ET masks will, however, inevitably contain some overlaps 
and holes, so they will not add up to a valid map any more.   



 
## Outputs

We produce the following output files from the Grunnkart (GK): 

| File_name(s) | Description | 
|:------|:------------------------------|
| GK_ETM_L1_fYY_2025.gpkg | The level-1 *ET map* for fylke fYY (16 files, ~1-3 Gb for each fylke, 20 Gb for the national level) |
| GK_s1_eXX_fYY_2025.gpkg | *Simplified ET mask* generated for eXX with method s1 () for fylke fYY (7x15 files, <1 Gb each fylke) |
| GK_s2_eXX_fYY_2025.gpkg | *Simplified ET mask* generated for eXX with method s2 (dilation followed by erosion, optimised for connectivity, slightly "overestimating" in mosiac landscapes) for fylke fYY (7x15 files, <1 Gb each fylke) |

<!-- Sylvie, we should use epsg 25833 for the national versions, and the default fylke projection for the fylke-level files !-->  

We use the official fylke codes, complemented with the pseudocode "f00" containing all fylkes in one file (national level):
* f00 – National level (all fylkes)
* f03 – Oslo
* f11 – Rogaland
* f15 – Møre og Romsdal
* f18 – Nordland
* f31 – Østfold
* f32 – Akershus
* f33 – Buskerud
* f34 – Innlandet
* f39 – Vestfold
* f40 – Telemark
* f42 – Agder
* f46 – Vestland
* f50 – Trøndelag
* f55 – Troms
* f56 – Finnmark

To denote level-1 ETs we use Eurostat's official ET classification, which is also followed by the GK:
* e01 – Settlements and other artificial areas
* e02 – Cropland
* e03 – Grassland (pastures, semi-natural and natural grasslands)
* e04 – Forest and woodland
* e05 – Heathland and shrub
* e06 – Sparsely vegetated ecosystems
* e07 – Inland wetlands 
* e08 – Rivers and canals 
* e09 – Lakes and reservoirs
* e10 – Marine inlets and transitional waters
* e11 – Coastal beaches, dunes and wetlands
* e12 – Marine ecosystems (coastal waters, shelf and open ocean)

The GK s1 & s2 files are only produced for "strictly" terrestrial ETs (e01-e07).


## References 


Aune-Lundberg, L., Steinnes, M., Keshav Prasad Paudel, Arneberg, E., Lund, M. O., Moraru, A., & Foss, S. V. (2025). Nasjonalt grunnkart for arealanalyse – Årsversjon 2025. Norsk institutt for bioøkonomi. https://doi.org/10.21350/4M2K-7Z04

Eurostat (2026). EU Ecosystem typology. Technical Note. Version: Version: July 2026. https://ec.europa.eu/eurostat/documents/1798247/12357920/EU-ecosystem-typology.pdf/265ef6e5-b146-e501-499a-d1467f7a6a90?t=1734604764993

Rendón, P., Watson, M., Czúcz, B., Ruf, K., Kleeschulte, S., & Santos-Martín, F. (2025). Integrating national and international ecosystem typologies for condition assessments: Principles for typology design and policy alignment. One Ecosystem, 10, e163068. https://doi.org/10.3897/oneeco.10.e163068

