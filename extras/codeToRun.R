# Copyright 2026 Observational Health Data Sciences and Informatics
#
# This file is part of ConcominantDrugFeasibility
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ==============================================================================
# ConcominantDrugFeasibility - study execution script
#
# This is the single file a site edits and runs to execute the study. Fill in
# the site-specific parameters below, then call
# ConcominantDrugFeasibility::execute().
# Share ONLY the zip file reported at the end.
# ==============================================================================

# Restore the package versions recorded in renv.lock, then install the package
# install.packages("renv")
# renv::restore()
# remotes::install_local("path/to/ConcominantDrugFeasibility")

library(ConcominantDrugFeasibility)

# ------------------------------------------------------------------------------
# 1. Site-specific database connection  (edit these for every site)
# ------------------------------------------------------------------------------
source("../credentials.r")

JDBC <- "/path/to/Jdbc"
connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms         = DBMS,
  user         = USER,
  password     = PASSWORD,
  server       = SERVER,
  port         = DB_PORT,
  pathToDriver = JDBC
)

# ------------------------------------------------------------------------------
# 2. Schema and table names
# ------------------------------------------------------------------------------
cdmDatabaseSchema    <- "your_cdm"                  # read-only CDM
cohortDatabaseSchema <- "your_results"              # write-enabled; needs read/write/delete
cohortTable          <- "cohortConcominantDrugFeasibility"

databaseId <- "YourDb"                              # short identifier, no spaces

outputFolder <- file.path("output", paste0(databaseId, "_ConcominantDrugFeasibility_v0.1"))

# Temp table emulation (Oracle / some Spark configs)
options(sqlRenderTempEmulationSchema = NULL)

# ------------------------------------------------------------------------------
# 3. Cohort ids  (inst/settings/*.csv; definitions in inst/cohorts/)
#
#   Cohorts           (CohortsToCreate.csv; ATLAS ids in the atlasId column, JSON/SQL in
#                      inst/cohorts/<atlasId>.json and inst/sql/sql_server/<atlasId>.sql)
#     1856 PCa ARPI
#     1857 Losartan      1858 Amlodipine     1859 Nifedipine    1860 Apixaban
#     1861 Warfarin      1862 Atorvastatin   1863 Simvastatin
#   Overlaps          (CohortOverlaps.csv)
#     1856 x each of 1857-1863
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# 4. Run options
# ------------------------------------------------------------------------------
minCellCount       <- 5       # counts below this are censored in all exported files
includeCohortStats <- FALSE
incrementalCohorts <- TRUE
generateCohorts    <- TRUE
calculateOverlaps  <- TRUE
createPlots        <- TRUE
zipResults         <- TRUE

# ------------------------------------------------------------------------------
# 5. Execute the study
# ------------------------------------------------------------------------------
ConcominantDrugFeasibility::execute(
  connectionDetails    = connectionDetails,
  cdmDatabaseSchema    = cdmDatabaseSchema,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTable          = cohortTable,
  outputFolder         = outputFolder,
  databaseId           = databaseId,
  minCellCount         = minCellCount,
  incrementalCohorts   = incrementalCohorts,
  includeCohortStats   = includeCohortStats,
  generateCohorts      = generateCohorts,
  calculateOverlaps    = calculateOverlaps,
  createPlots          = createPlots,
  zipResults           = zipResults
)

# ------------------------------------------------------------------------------
# 6. Share
# ------------------------------------------------------------------------------
list.files(outputFolder, pattern = "ConcominantDrugFeasibility_Results_.*\\.zip", full.names = TRUE)
