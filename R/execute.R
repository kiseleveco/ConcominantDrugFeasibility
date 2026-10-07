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

#' Execute the ConcominantDrugFeasibility study
#'
#' Runs the full analysis end to end. Each step is individually switchable so a
#' site can (re)run just part of the study. The steps run in the following order:
#' \enumerate{
#'   \item \strong{generateCohorts} - instantiate the cohorts listed in
#'     \code{inst/settings/CohortsToCreate.csv} (prostate cancer 1856 and drugs
#'     1857-1863) on the CDM with \code{\link{generateStudyCohorts}}.
#'   \item \strong{calculateOverlaps} - overlap of each drug cohort with the
#'     prostate cancer cohort and the binned drug minus prostate cancer index date
#'     difference with \code{\link{runOverlapAnalysis}}.
#'   \item \strong{createPlots} - one plot of the binned index date differences per
#'     drug with \code{\link{plotDayDifferenceBins}}.
#' }
#' All exported counts below \code{minCellCount} are censored. When
#' \code{zipResults} is \code{TRUE} the files to share are zipped into
#' \code{<outputFolder>/ConcominantDrugFeasibility_Results_<databaseId>.zip}.
#'
#' @param connectionDetails        DatabaseConnector connection details object.
#' @param cdmDatabaseSchema        Schema containing the OMOP CDM tables
#'   (read-only).
#' @param cohortDatabaseSchema     Schema where the cohort table will be written
#'   (needs read / write / delete).
#' @param cohortTable              Base name for the cohort table populated by
#'   \code{\link{generateStudyCohorts}}.
#' @param outputFolder             Path where all result files will be written.
#' @param databaseId               Short database identifier (no spaces).
#' @param minCellCount             Minimum cell count for censoring small counts
#'   in the exported results.
#' @param incrementalCohorts       Logical. Passed to
#'   \code{\link{generateStudyCohorts}} as \code{incremental}.
#' @param includeCohortStats       Logical. Passed to
#'   \code{\link{generateStudyCohorts}}.
#' @param generateCohorts          Logical. Run the cohort generation step.
#' @param calculateOverlaps        Logical. Run the overlap analysis step.
#' @param createPlots              Logical. Run the plotting step.
#' @param zipResults               Logical. Zip the files to share.
#' @param packageName              Name of this package.
#'
#' @export
execute <- function(connectionDetails,
                    cdmDatabaseSchema,
                    cohortDatabaseSchema,
                    cohortTable,
                    outputFolder,
                    databaseId,
                    minCellCount       = 5,
                    incrementalCohorts = TRUE,
                    includeCohortStats = FALSE,
                    generateCohorts    = TRUE,
                    calculateOverlaps  = TRUE,
                    createPlots        = TRUE,
                    zipResults         = TRUE,
                    packageName        = "ConcominantDrugFeasibility") {

  if (!dir.exists(outputFolder)) {
    dir.create(outputFolder, recursive = TRUE)
  }

  ParallelLogger::addDefaultFileLogger(file.path(outputFolder, "log.txt"), name = "ConcominantDrugFeasibilityFileLogger")
  ParallelLogger::addDefaultErrorReportLogger(file.path(outputFolder, "errorReportR.txt"), name = "ConcominantDrugFeasibilityErrorLogger")
  on.exit(ParallelLogger::unregisterLogger("ConcominantDrugFeasibilityFileLogger", silent = TRUE), add = TRUE)
  on.exit(ParallelLogger::unregisterLogger("ConcominantDrugFeasibilityErrorLogger", silent = TRUE), add = TRUE)

  # --------------------------------------------------------------------------
  # 1. Generate the cohorts
  # --------------------------------------------------------------------------
  if (generateCohorts) {
    ParallelLogger::logInfo("Generating study cohorts")
    generateStudyCohorts(
      connectionDetails    = connectionDetails,
      cdmDatabaseSchema    = cdmDatabaseSchema,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortTable          = cohortTable,
      outputFolder         = outputFolder,
      incremental          = incrementalCohorts,
      includeCohortStats   = includeCohortStats,
      minCellCount         = minCellCount,
      packageName          = packageName
    )
  }

  # --------------------------------------------------------------------------
  # 2. Overlap with the prostate cancer cohort and index date differences
  # --------------------------------------------------------------------------
  if (calculateOverlaps) {
    ParallelLogger::logInfo("Running overlap analysis")
    runOverlapAnalysis(
      connectionDetails    = connectionDetails,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortTable          = cohortTable,
      databaseId           = databaseId,
      minCellCount         = minCellCount,
      outputFolder         = outputFolder,
      packageName          = packageName
    )
  }

  # --------------------------------------------------------------------------
  # 3. One plot per drug
  # --------------------------------------------------------------------------
  if (createPlots) {
    ParallelLogger::logInfo("Plotting index date differences")
    plotDayDifferenceBins(
      outputFolder = outputFolder,
      minCellCount = minCellCount
    )
  }

  if (zipResults) {
    zipFile <- zipStudyResults(outputFolder, databaseId)
    ParallelLogger::logInfo("Results to share: ", zipFile)
  }

  invisible(NULL)
}
