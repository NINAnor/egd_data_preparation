# egd-data-preparation: Multi-purpose simplified ecosystem type maps for ecosystem condition variable calculations  

Authors: Sylvie Clappe, Balint Czucz, Jenny Hansen -- NINA


## Introduction 

**Ecosystem condition (EC)** variables are always linked to one or more specific **ecosystem types (ET)** 
(=their "parent" ETs, cf. Czucz et al. 2025). Working with EC variables thus always requires some information 
about the spatial distribution of their "parent" ETs. This makes **ecosystem type (ET) maps** a critically 
important *multi-purpose* "input" data source required for the calculation of almost all EC variables. 
Accordingly, it makes sense to decouple any data preparation steps required by the ET maps from the EC variable 
calculations themselves. This yields more modular and and more efficient calculation workflows and simpler, clearer, 
less redundant, and easier to maintain variable descriptions (presented in [ecrXiv](https://ecrxiv.com/)). 

The main purpose of this repository is to offer such general preprocessing workflows for the **Grunnkart (GK)** dataset.
GK is the official national ET map for Norway, with a (planned) annual update cycle. The raw GK dataset, however, needs 
heavy preprocessing before it becomes fit-for-purpose for EC applications. Here we present a series of R scripts for 
this purpose, which generate a series of "analsis-ready" ET maps and masks from the annual editions of the raw GK data. 

In addition to the GK dataset, this repository also collects preparatory scripts for several *single-purpose* datasets 
used for calculating EC variables. We particularly focus on the data needs of variables URGR, URAQ and TCCD, including:

- [Copernicus IMD](url...)
- [Copernicus TCD](url...)

In the case of these single-purpose datasets, [ecrXiv](https://ecrxiv.com/) is the main source presenting the entire 
indicator development process. Nevertheless, for clarity and reproducibility purposes few data preparatory steps 
are only described in ecrXiv (without a runnable script included there). This repository offers a home for such "not-run" 
preliminary steps for the aforementioned datasets. 


## The Grunnkart dataset

### Challenges

The **Grunkart (GK, Nasjonalt grunnkart for arealanalyse)** dataset is vector dataset describing the main ecosystem 
types (ET) of Norway. It largely follows Eurostat's ecosystem typology (Eurostat, 2026), and one of its main declared 
purposes is to support the development of ecosystem condition accounts (tilstandsregnskap) in Norway. Nevertheless, 
from the perspective of this purpose, the (current versions of the) raw GK dataset have several shortcomings:
* For some map features & land cover types types (especially artificial objects) it applies very fine-scale spatial distinctions 
  (individual buildings, small roads), while for others it just provides a broad-brush picture
* The thematic resolution of the dataset is also uneven: for urban ecosystems lots of tiny "ecosystem subtypes" are distinguished 
  (based on land use/cover), for most of the other, ecologically more relevant ETs there are no subtypes identified.   

In other words, the GK dataset does not consistently follow a "functional ecosystem" perspective, with a clear MMU-based 
operationalisation (Rendon et al. 2025). This results in very complex and fragmented polygons and huge file sizes. 
In addition, the final polygon dataset of Version 2025 still contains many geometric errors, inconsistencies, tiny sliver polygons, etc. 

The geometric challenges and the file sizes make the original vector files very difficult to work with. 
In addition, spatial and thematic resolution inconsistencies are also conceptually problematic, 
especially for ecosystem condition accounting (Rendon et al. 2025).


### Data source

| Dataset name | Citation | Original URI | NINA URI |
|------|------|------|------------|
| Nasjonalt grunnkart for arealanalyse, Årsversjon 2025 | Aune-Lundberg et al., 2025 | [GeoNorge](https://kartkatalog.geonorge.no/metadata/nasjonalt-grunnkart-for-arealanalyse/28c28e3a-d88f-4a34-8c60-5efe6d56a44d) | "R:/GeoSpatialData/LandUse/Norway_Arealregnskap/Original/GrunnkartArealregnskap FGDB-format"


### Methods

To improve the suitability of the GK for EC analysis, we first 
 * perform geometric corrections on the polygon geometries,
 * and dissolve all polygons representing level-2 ET subtypes into their level-1 ET class.

Dissolving level-2 polygons into larger level-1 categories also reduces the spatial complexity of the datset, 
especially in urban and peri-urban areas. The resulting clean level-1 spatial partition of the terrestrial area 
of mainland Norway (a *level-1 ET map* for all ETs) is the *first main output* of our analysis. 

In addition, we also produce several further secondary outputs, which are *simplified ET masks* for all major 
terrestrial ETs (e01-e07, one by one). To acheive this, we start out form the clean *level-1 ET map*, taking all polygons 
belonging to the selected ET. Then we simplify its spatial structure in a series of dilation & erosion operations, 
which makes e.g. small fragments of the ET disappear, and small holes within the ET to be filled in. 

Here we follow two different "simplification methods":
* method **s1**: *erosion* followed by *dilation*, optimised for "simplicity", 
  slightly "underestimating" the area of the ET in complex mosaic landscapes. 
* method **s2**: *dilation* followed by *erosion*, optimised for maintaining "connectivity", 
  slightly "overestimating" in complex mosaic landscapes.

For both methods we applied a dilation/erosion buffer of 10m, which gets rid of every "island" (finger, channel, etc) 
of the selected ET that narrower than `th_morph = 20`m, and similarly, every "gap" narrower than 20m gets swallowed by the selected ET.
The only difference between the two methods is in the *order* of the dilation and erosion operations. 
In a coarse-grained landscape with few small gaps and few small islands the two methods will lead to closely the same result, 
which also closely coincides with the ET boundaries of the level-1 ET map. 
However, areas of very finely grained landscape with masses of small island and gaps of the studied ET, will be handled 
differently by the two methods. Such highly fragmented areas will be included in **s2** ET maps, and will be excluded form 
**s1** masks.

The simplified ET masks produced for the different ETs will *never* form a perfect partition of the whole ecosystem 
accounting area (EAA). The differnet ET masks will inevitably overlap with each other, and there will also inevitably 
be some "white spots" between them -- no matter which method was used. 
This is the reason why we call these product *ET masks*, and not an *ET map*. For applications that demand a strict partition 
the level-1 ET maps (or the original raw GK) are the suitable starting datasets. 
Nevertheless, for several EC variables (especially the ones tightly linked to a single (or few) specific *parent ET*(s) 
via *field observations* (FO) or *spatial overlay* (SO)  -- see Czucz et al. 2025) the simplified ET masks can 
offer a much simpler yet ecologically well-justified input dataset.

 
## Notation

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

The The simplified ET masks are only produced for the "strictly" terrestrial ETs (e01-e07).

To make the output files more useful for local-regional (fine-scale) context, we produce dedicated output files for 
each Norwegian county (*fylke*), as well as the national level. To identify the fylkes we use their official codes 
(complemented with a pseudocode for the national level):
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


### Output files

We produce the following output files from the Grunnkart (GK): 

| File_name(s) | Description | 
|:------|:------------------------------|
| GK_ETM_L1_fYY_2025.gpkg | The level-1 *ET map* for fylke fYY (16 files, ~1-3 Gb for each fylke, 20 Gb for the national level) |
| GK_s1_eXX_fYY_2025.gpkg | *Simplified ET mask* generated for eXX with method s1 (erosion-dilation) for fylke fYY (7x15 files, <1 Gb each fylke) |
| GK_s2_eXX_fYY_2025.gpkg | *Simplified ET mask* generated for eXX with method s2 (dilation-erosion) for fylke fYY (7x15 files, <1 Gb each fylke) |

<!-- Sylvie, we should use epsg 25833 for the national versions, and the default fylke projection for the fylke-level files 
     It is enough if you make the files in the first row above, and then I will make the rest (starting out from your files, 
     and possibly reusing parts of your script). -->  


### References 

Aune-Lundberg, L., Steinnes, M., Keshav Prasad Paudel, Arneberg, E., Lund, M. O., Moraru, A., & Foss, S. V. (2025). Nasjonalt grunnkart for arealanalyse – Årsversjon 2025. Norsk institutt for bioøkonomi. https://doi.org/10.21350/4M2K-7Z04

Czúcz, B., Framstad, E., Clappe, S., & Nowell, M. (2025). Exploring the use of Eurostat’s mandatory and voluntary indicators in Norway. In 78 (No. 2604). Norsk institutt for naturforskning (NINA). https://hdl.handle.net/11250/3199708

Eurostat (2026). EU Ecosystem typology. Technical Note. Version: Version: July 2026. https://ec.europa.eu/eurostat/documents/1798247/12357920/EU-ecosystem-typology.pdf/265ef6e5-b146-e501-499a-d1467f7a6a90?t=1734604764993

Rendón, P., Watson, M., Czúcz, B., Ruf, K., Kleeschulte, S., & Santos-Martín, F. (2025). Integrating national and international ecosystem typologies for condition assessments: Principles for typology design and policy alignment. One Ecosystem, 10, e163068. https://doi.org/10.3897/oneeco.10.e163068


## Other preparatory scripts

The source datasets and the analysis related analysis steps are described in detail in ecrXiv (under the 
corresponding EC variables: URGR, URAQ, TCCD), including a description of the data preprocessing steps. 
Here we don't duplicate these descriptions -- we just provide the script for the preprocessing steps
(with embedded #-comments, as necessary).


<!--  Sylvie, FWIW, I increasingly think that this .md file is enough for the overall description of this workflow -- 
      i.e. we could do with a simple R script (with simple #-comments, as needed, versioned in git... but no qmd). 
      If you don't mind I will transform the current qmd into such an R script when I add my parts (s1, s2...) to its end. --> 

