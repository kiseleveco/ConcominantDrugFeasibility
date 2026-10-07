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

# ------------------------------------------------------------------------------
# Internal helpers shared by the analysis functions
# ------------------------------------------------------------------------------

# Read one of the CSV files in inst/settings
readSettings <- function(fileName, packageName = "ConcominantDrugFeasibility") {
  path <- system.file("settings", fileName, package = packageName)
  if (!nzchar(path)) {
    stop("Settings file not found in package ", packageName, ": ", fileName)
  }
  utils::read.csv(path, stringsAsFactors = FALSE)
}

# cohortId -> cohortName of the cohorts in CohortsToCreate.csv
getCohortNameMap <- function(packageName = "ConcominantDrugFeasibility") {
  base <- readSettings("CohortsToCreate.csv", packageName)
  data.frame(cohortId = base$cohortId, cohortName = base$cohort_name, stringsAsFactors = FALSE)
}

# Cohort name without the leading "[Project tag] " used in ATLAS, for titles and file names
shortCohortName <- function(cohortName) {
  trimws(sub("^\\[[^]]*\\]", "", cohortName))
}

executeSqlFile <- function(connection, sqlFilename, packageName, ...) {
  sql <- SqlRender::loadRenderTranslateSql(
    sqlFilename         = sqlFilename,
    packageName         = packageName,
    dbms                = DatabaseConnector::dbms(connection),
    tempEmulationSchema = getOption("sqlRenderTempEmulationSchema"),
    ...
  )
  DatabaseConnector::executeSql(connection, sql, progressBar = FALSE, reportOverallTime = FALSE)
  invisible(NULL)
}

querySqlFile <- function(connection, sqlFilename, packageName, ...) {
  sql <- SqlRender::loadRenderTranslateSql(
    sqlFilename         = sqlFilename,
    packageName         = packageName,
    dbms                = DatabaseConnector::dbms(connection),
    tempEmulationSchema = getOption("sqlRenderTempEmulationSchema"),
    ...
  )
  DatabaseConnector::querySql(connection, sql, snakeCaseToCamelCase = TRUE)
}

# Non-zero counts below minCellCount are replaced by -minCellCount (OHDSI convention)
censorCounts <- function(data, countColumns, minCellCount = 5) {
  if (is.null(data) || nrow(data) == 0 || minCellCount <= 1) {
    return(data)
  }
  for (column in countColumns) {
    small <- !is.na(data[[column]]) & data[[column]] > 0 & data[[column]] < minCellCount
    data[[column]][small] <- -minCellCount
  }
  data
}

addCohortNames <- function(data, nameMap, idColumn, nameColumn) {
  data[[nameColumn]] <- nameMap$cohortName[match(data[[idColumn]], nameMap$cohortId)]
  data
}

# Half-open bins `[lower, upper)` of binWidth days. With the defaults the central
# bin is [-5, 5), followed by [5, 15), [-15, -5) and so on. Empty bins between the
# smallest and the largest occupied bin are returned with a count of zero.
binDayDifference <- function(dayDifference,
                             nPersons = rep(1, length(dayDifference)),
                             binWidth = 10,
                             centerHalfWidth = binWidth / 2) {
  checkmate::assertNumeric(dayDifference)
  checkmate::assertNumeric(nPersons, len = length(dayDifference))
  checkmate::assertNumber(binWidth, lower = 1)
  checkmate::assertNumber(centerHalfWidth, lower = 0)

  if (length(dayDifference) == 0) {
    return(data.frame(
      binIndex = integer(), binLower = numeric(), binUpper = numeric(),
      binLabel = character(), nPersons = numeric()
    ))
  }
  binIndex <- floor((dayDifference + centerHalfWidth) / binWidth)
  counts <- tapply(nPersons, binIndex, sum)
  allIndex <- seq(min(binIndex), max(binIndex))
  n <- as.numeric(counts[as.character(allIndex)])
  n[is.na(n)] <- 0
  lower <- allIndex * binWidth - centerHalfWidth
  upper <- lower + binWidth
  data.frame(
    binIndex = as.integer(allIndex),
    binLower = lower,
    binUpper = upper,
    binLabel = sprintf("[%s, %s)", format(lower, trim = TRUE), format(upper, trim = TRUE)),
    nPersons = n,
    stringsAsFactors = FALSE
  )
}

# Zip the censored result files (and plots) for sharing
zipStudyResults <- function(outputFolder, databaseId) {
  zipFile <- file.path(outputFolder, sprintf("ConcominantDrugFeasibility_Results_%s.zip", databaseId))
  # Paths relative to outputFolder so the archive does not contain the local folder structure
  files <- c(
    list.files(outputFolder, pattern = "^CohortCounts\\.csv$"),
    list.files(outputFolder, pattern = "^overlapAnalysis$")
  )
  zip::zip(zipfile = zipFile, files = files, recurse = TRUE, root = outputFolder)
  zipFile
}
