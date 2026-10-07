# ConcominantDrugFeasibility

Feasibility of concomitant drug analysis in a prostate cancer cohort in an OMOP CDM

- **Analytics use case(s):** Characterization
- **Study type:** Data assessment
- **Tags:** Prostate cancer, ARPI, Concomitant drugs, Losartan, Amlodipine, Nifedipine, Apixaban, Warfarin, Atorvastatin, Simvastatin
- **Data model:** OMOP CDM v5.x
- **Study package status:** In development

## Introduction

`ConcominantDrugFeasibility` is an OHDSI ([HADES](https://ohdsi.github.io/Hades/)) study package that
assesses how many patients of a prostate cancer cohort (`PCa ARPI`, cohort 1856) also have a
cohort entry for each of seven concomitant drugs (cohorts 1857-1863), and how far apart the index
dates are. It is structured like the `DataAssessment` study package.

## Features

- Generates the cohorts listed in `inst/settings/CohortsToCreate.csv` with
  [CohortGenerator](https://ohdsi.github.io/CohortGenerator/).
- Reports the overlap (persons in both cohorts) of each drug cohort with the prostate cancer cohort.
- Reports the number of persons in bins of 10 days of the difference between the drug and the
  prostate cancer index dates; the central bin is -5 to 5.
- Draws one plot of these bins for each drug.
- Censors counts below `minCellCount` in every exported file.

## Requirements

- R (>= 4.3.0)
- Java (for [DatabaseConnector](https://ohdsi.github.io/DatabaseConnector/) / the JDBC drivers)
- A database account with:
  - **read** access to the OMOP CDM schema, and
  - **read / write / delete** access to a results (work) schema.

## Installation

1. Restore the package versions recorded in `renv.lock`
   ([`renv`](https://rstudio.github.io/renv/)):

   ```r
   install.packages("renv")
   renv::restore()
   ```

2. Add the ATLAS cohort definition JSON files to `inst/cohorts/`, named by ATLAS id
   (`<atlasId>.json`, see the `atlasId` column of `inst/settings/CohortsToCreate.csv`). They are
   downloaded from ATLAS by [`inst/settings/insertCohortDefinition.R`](inst/settings/insertCohortDefinition.R)
   (set `token` first). If `inst/sql/sql_server/<atlasId>.sql` is absent, the SQL is built from the
   JSON with CirceR.

3. Install the package itself:

   ```r
   remotes::install_local("path/to/ConcominantDrugFeasibility")
   # or, during development:
   devtools::install(".")
   ```

## How to run

The single file a site edits and runs is [`extras/codeToRun.R`](extras/codeToRun.R). Fill in the
connection details and schema names, then source it. It calls the package's main entry point,
`execute()`.

```r
library(ConcominantDrugFeasibility)

connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms         = "...",
  user         = "...",
  password     = "...",
  server       = "...",
  port         = ...,
  pathToDriver = "/path/to/jdbc"
)

ConcominantDrugFeasibility::execute(
  connectionDetails    = connectionDetails,
  cdmDatabaseSchema    = "your_cdm",           # read-only CDM
  cohortDatabaseSchema = "your_results",       # read/write/delete
  cohortTable          = "cohortConcominantDrugFeasibility",
  outputFolder         = "/path/to/output",
  databaseId           = "YourDb"
)
```

`execute()` runs the study steps, each individually switchable via its `generateCohorts` /
`calculateOverlaps` / `createPlots` arguments so a site can re-run just part of the study (for
example `generateCohorts = FALSE` to reuse the cohorts already in the cohort table).

Results are written under `outputFolder`:

| File | Content |
|------|---------|
| `CohortCounts.csv` | Entries and persons of each generated cohort. |
| `overlapAnalysis/intersections.csv` | For each drug: persons in the prostate cancer cohort (`anchorN`), in the drug cohort (`targetN`) and in both (`intersectionN`). |
| `overlapAnalysis/dayDifferenceBins.csv` | For each drug: persons per 10-day bin of the index date difference (`binLower`, `binUpper`, `binLabel`, `nPersons`). |
| `overlapAnalysis/plots/dayDifference_<cohortId>_<drug>.png` | One plot of the bins per drug. |

With `zipResults = TRUE` the files to share are zipped into
`ConcominantDrugFeasibility_Results_<databaseId>.zip`.

## Package structure

Each analytical function lives in its own file under `R/`, with inline documentation.

| File | Function | Role |
|------|----------|------|
| `R/execute.R` | `execute()` | **Main entry point** — orchestrates the steps below. |
| `R/generateStudyCohorts.R` | `generateStudyCohorts()` | Instantiates the cohorts on the CDM. |
| `R/runOverlapAnalysis.R` | `runOverlapAnalysis()` | Overlap with the prostate cancer cohort and binned index date differences. |
| `R/plotDayDifferenceBins.R` | `plotDayDifferenceBins()` | One plot of the binned index date differences per drug. |
| `R/utils.R` | (internal) | Settings readers, SQL helpers, binning, censoring. |

Supporting resources under `inst/`:

- `inst/cohorts/` — Circe cohort definitions (JSON), named `<atlasId>.json`.
- `inst/sql/sql_server/` — SQL for the overlap analysis.
- `inst/settings/CohortsToCreate.csv` — cohorts to generate (1856-1863).
- `inst/settings/CohortOverlaps.csv` — the anchor (prostate cancer) and target (drug) cohort of each overlap analysis.

## Cohorts

| id | ATLAS id | Cohort | id | ATLAS id | Cohort |
|----|----------|--------|----|----------|--------|
| 1856 | 1856 | PCa ARPI (anchor) | 1860 | 1860 | Apixaban |
| 1857 | 1857 | Losartan | 1861 | 1861 | Warfarin |
| 1858 | 1858 | Amlodipine | 1862 | 1862 | Atorvastatin |
| 1859 | 1859 | Nifedipine | 1863 | 1863 | Simvastatin |

## Index date difference

- The index date of a person in a cohort is the first `cohort_start_date`.
- A person is in the overlap when they are in both the prostate cancer cohort and the drug cohort.
- The difference is the **drug index date minus the prostate cancer index date**, in days. A positive
  value means that the drug cohort starts after the prostate cancer cohort.
- Bins are 10 days wide and half-open, `[lower, upper)`. The central bin is `[-5, 5)` (differences
  -5 to 4), followed by `[5, 15)`, `[-15, -5)` and so on. Empty bins between the smallest and the
  largest occupied bin are reported with a count of zero.
- Counts below `minCellCount` (default 5) are replaced by `-minCellCount` in the exported CSV files.
  Censored bins are not drawn in the plots.
- `plotDayDifferenceBins()` returns the plots as `ggplot2` objects. To zoom in on the days around
  the prostate cancer index date add for example `ggplot2::coord_cartesian(xlim = c(-365, 365))`.

## License

`ConcominantDrugFeasibility` is licensed under Apache License 2.0.
