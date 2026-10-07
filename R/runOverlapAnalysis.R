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

#' Overlap of the drug cohorts with the prostate cancer cohort
#'
#' For each row of \code{inst/settings/CohortOverlaps.csv} (the prostate cancer
#' cohort 1856 as anchor and each drug cohort 1857-1863 as target) reports the
#' size of the intersection between the anchor and the target cohort and the
#' target minus anchor index date difference in days, counted in bins of
#' \code{binWidth} days. The bins are half-open, \code{[lower, upper)}, and the
#' central bin is \code{[-5, 5)} for the default width of 10. A positive
#' difference means that the drug cohort starts after the prostate cancer
#' cohort. The index date of a person in a cohort is the first
#' \code{cohort_start_date}. Counts below \code{minCellCount} are censored.
#'
#' Results are written to \code{<outputFolder>/overlapAnalysis/}:
#' \code{intersections.csv} and \code{dayDifferenceBins.csv}. Use
#' \code{\link{plotDayDifferenceBins}} to plot the bins.
#'
#' @param connectionDetails    DatabaseConnector connection details object.
#'   Ignored when \code{connection} is supplied.
#' @param connection           An optional open DatabaseConnector connection.
#' @param cohortDatabaseSchema Schema holding the cohort table.
#' @param cohortTable          Cohort table populated by
#'   \code{\link{generateStudyCohorts}}.
#' @param databaseId           Short database identifier (no spaces).
#' @param binWidth             Bin width in days. Default 10.
#' @param minCellCount         Minimum cell count for censoring small counts.
#' @param outputFolder         Path where result files will be written.
#' @param packageName          Name of the package holding the SQL and settings.
#'
#' @return Invisibly, a list with the censored tables \code{intersections} and
#'   \code{dayDifferenceBins}.
#'
#' @export
runOverlapAnalysis <- function(connectionDetails = NULL,
                               connection = NULL,
                               cohortDatabaseSchema,
                               cohortTable,
                               databaseId,
                               binWidth = 10,
                               minCellCount = 5,
                               outputFolder,
                               packageName = "ConcominantDrugFeasibility") {

  analysisFolder <- file.path(outputFolder, "overlapAnalysis")
  if (!dir.exists(analysisFolder)) {
    dir.create(analysisFolder, recursive = TRUE)
  }
  overlaps <- readSettings("CohortOverlaps.csv", packageName)
  nameMap <- getCohortNameMap(packageName)

  unknownIds <- setdiff(c(overlaps$anchorCohortId, overlaps$targetCohortId), nameMap$cohortId)
  if (length(unknownIds) > 0) {
    stop("CohortOverlaps.csv refers to cohort id(s) not listed in CohortsToCreate.csv: ",
         paste(unknownIds, collapse = ", "))
  }

  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }

  intersections <- list()
  bins <- list()

  for (i in seq_len(nrow(overlaps))) {
    spec <- overlaps[i, ]
    ParallelLogger::logInfo(sprintf(
      "Analysis %d: cohort %d x cohort %d", spec$analysisId, spec$anchorCohortId, spec$targetCohortId
    ))

    executeSqlFile(
      connection, "getOverlap.sql", packageName,
      cohort_database_schema = cohortDatabaseSchema,
      cohort_table           = cohortTable,
      anchor_cohort_id       = spec$anchorCohortId,
      target_cohort_id       = spec$targetCohortId
    )
    counts <- querySqlFile(connection, "getOverlapCounts.sql", packageName)
    distribution <- querySqlFile(connection, "getDayDifference.sql", packageName)
    executeSqlFile(connection, "dropOverlapTables.sql", packageName)

    ids <- data.frame(
      databaseId = databaseId, analysisId = spec$analysisId,
      anchorCohortId = spec$anchorCohortId, targetCohortId = spec$targetCohortId
    )
    intersections[[i]] <- cbind(ids, counts)

    binTable <- binDayDifference(
      dayDifference = distribution$dayDiff,
      nPersons      = distribution$nPersons,
      binWidth      = binWidth
    )
    if (nrow(binTable) > 0) {
      bins[[i]] <- cbind(ids[rep(1, nrow(binTable)), ], binTable, row.names = NULL)
    }
    ParallelLogger::logInfo(sprintf(
      "  anchor n = %s; target n = %s; intersection n = %s",
      counts$anchorN, counts$targetN, counts$intersectionN
    ))
  }

  intersections <- do.call(rbind, intersections)
  intersections <- censorCounts(intersections, c("anchorN", "targetN", "intersectionN"), minCellCount)
  intersections <- addCohortNames(intersections, nameMap, "anchorCohortId", "anchorCohortName")
  intersections <- addCohortNames(intersections, nameMap, "targetCohortId", "targetCohortName")

  bins <- do.call(rbind, bins)
  if (!is.null(bins)) {
    bins <- censorCounts(bins, "nPersons", minCellCount)
    bins <- addCohortNames(bins, nameMap, "anchorCohortId", "anchorCohortName")
    bins <- addCohortNames(bins, nameMap, "targetCohortId", "targetCohortName")
  }

  readr::write_excel_csv(intersections, file.path(analysisFolder, "intersections.csv"), na = "")
  binsFile <- file.path(analysisFolder, "dayDifferenceBins.csv")
  if (is.null(bins)) {
    unlink(binsFile)  # no overlap at all: do not leave the file of an earlier run behind
  } else {
    readr::write_excel_csv(bins, binsFile, na = "")
  }
  ParallelLogger::logInfo("Overlap analysis written to ", analysisFolder)

  invisible(list(intersections = intersections, dayDifferenceBins = bins))
}
