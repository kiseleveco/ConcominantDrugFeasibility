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

#' Plot the index date difference bins, one plot per drug
#'
#' Reads the censored \code{intersections.csv} and \code{dayDifferenceBins.csv}
#' written by \code{\link{runOverlapAnalysis}} and draws, for each drug cohort, the
#' number of persons per bin of the drug minus prostate cancer index date
#' difference. The central bin is highlighted and its count is labelled. Bins
#' with fewer than \code{minCellCount} persons are censored in the input and are
#' not drawn. A drug without any person in both cohorts gets a plot stating so.
#'
#' One PNG per drug is written to \code{<outputFolder>/overlapAnalysis/plots/}. The
#' plots are \pkg{ggplot2} objects; to zoom in on the days around the prostate
#' cancer index date add for example
#' \code{ggplot2::coord_cartesian(xlim = c(-365, 365))} to a returned plot.
#'
#' @param outputFolder Path holding the \code{overlapAnalysis} folder written by
#'   \code{\link{runOverlapAnalysis}}.
#' @param minCellCount Minimum cell count used when censoring, only used in the
#'   plot caption.
#' @param width,height,dpi Size of the PNG files (inches) and resolution.
#'
#' @return Invisibly, a named list of ggplot objects (one per drug cohort).
#'
#' @export
plotDayDifferenceBins <- function(outputFolder,
                                  minCellCount = 5,
                                  width = 8,
                                  height = 4.5,
                                  dpi = 300) {

  analysisFolder <- file.path(outputFolder, "overlapAnalysis")
  intersectionsFile <- file.path(analysisFolder, "intersections.csv")
  binsFile <- file.path(analysisFolder, "dayDifferenceBins.csv")
  if (!file.exists(intersectionsFile)) {
    stop("intersections.csv not found in ", analysisFolder, ". Run runOverlapAnalysis() first.")
  }
  intersections <- readr::read_csv(intersectionsFile, show_col_types = FALSE)
  bins <- if (file.exists(binsFile)) readr::read_csv(binsFile, show_col_types = FALSE) else NULL

  plotFolder <- file.path(analysisFolder, "plots")
  if (!dir.exists(plotFolder)) {
    dir.create(plotFolder, recursive = TRUE)
  }

  plots <- list()
  for (i in seq_len(nrow(intersections))) {
    overlap <- intersections[i, ]
    targetBins <- if (is.null(bins)) NULL else bins[bins$analysisId == overlap$analysisId, ]
    plot <- buildDayDifferencePlot(targetBins, overlap, minCellCount)

    targetName <- shortCohortName(overlap$targetCohortName)
    plotName <- sprintf("dayDifference_%s_%s", overlap$targetCohortId, gsub("[^A-Za-z0-9]+", "_", targetName))
    ggplot2::ggsave(
      filename = file.path(plotFolder, paste0(plotName, ".png")),
      plot = plot, width = width, height = height, dpi = dpi, bg = surfaceColor
    )
    plots[[plotName]] <- plot
  }
  ParallelLogger::logInfo(length(plots), " plot(s) written to ", plotFolder)

  invisible(plots)
}

# Chart colours: categorical slots 1 and 2 of the validated reference palette, light mode
surfaceColor <- "#fcfcfb"
otherBinColor <- "#2a78d6"
centralBinColor <- "#eb6834"
primaryInk <- "#0b0b0b"
secondaryInk <- "#52514e"
gridColor <- "#e6e5e1"

# One plot: persons per bin of target minus anchor index date. `bins` holds the rows
# of dayDifferenceBins.csv of this analysis (NULL or empty without any overlap) and
# `overlap` the row of intersections.csv.
buildDayDifferencePlot <- function(bins, overlap, minCellCount = 5) {
  anchorName <- shortCohortName(overlap$anchorCohortName)
  targetName <- shortCohortName(overlap$targetCohortName)
  hasBins <- !is.null(bins) && nrow(bins) > 0
  binWidth <- if (hasBins) bins$binUpper[1] - bins$binLower[1] else 10

  centralLabel <- sprintf("Central bin [%s, %s)", format(-binWidth / 2), format(binWidth / 2))
  otherLabel <- "Other bins"

  nIntersection <- overlap$intersectionN
  nText <- if (nIntersection < 0) {
    sprintf("fewer than %s", minCellCount)
  } else {
    formatNumber(nIntersection)
  }

  plot <- ggplot2::ggplot() +
    ggplot2::labs(
      title    = sprintf("%s: index date relative to %s", targetName, anchorName),
      subtitle = sprintf("Persons in both cohorts: %s", nText),
      x        = sprintf("%s index date minus %s index date (days)", targetName, anchorName),
      y        = "Persons"
    ) +
    dayDifferenceTheme()

  drawn <- if (hasBins) bins[bins$nPersons > 0, ] else NULL
  nCensored <- if (hasBins) sum(bins$nPersons < 0) else 0
  if (is.null(drawn) || nrow(drawn) == 0) {
    emptyText <- if (nIntersection == 0) {
      "No persons in both cohorts"
    } else if (nIntersection < 0) {
      sprintf("Fewer than %s persons in both cohorts", minCellCount)
    } else {
      sprintf("All bins have fewer than %s persons", minCellCount)
    }
    return(
      plot +
        ggplot2::annotate("text", x = 0, y = 0, label = emptyText, colour = secondaryInk) +
        ggplot2::scale_x_continuous(limits = c(-5 * binWidth, 5 * binWidth)) +
        ggplot2::theme(
          axis.text   = ggplot2::element_blank(),
          panel.grid.major.y = ggplot2::element_blank()
        ) +
        ggplot2::labs(caption = captionText(binWidth, minCellCount, nCensored))
    )
  }

  drawn$binMid <- (drawn$binLower + drawn$binUpper) / 2
  drawn$group <- factor(ifelse(drawn$binIndex == 0, centralLabel, otherLabel), levels = c(centralLabel, otherLabel))
  central <- drawn[drawn$binIndex == 0, ]

  fillColors <- c(centralBinColor, otherBinColor)
  names(fillColors) <- c(centralLabel, otherLabel)

  plot <- plot +
    ggplot2::geom_col(
      data = drawn,
      mapping = ggplot2::aes(x = .data$binMid, y = .data$nPersons, fill = .data$group),
      width = 0.9 * binWidth
    ) +
    ggplot2::scale_fill_manual(values = fillColors, drop = FALSE) +
    ggplot2::scale_x_continuous(labels = formatNumber) +
    ggplot2::scale_y_continuous(
      breaks = integerBreaks,
      labels = formatNumber,
      expand = ggplot2::expansion(mult = c(0, 0.08))
    ) +
    ggplot2::labs(caption = captionText(binWidth, minCellCount, nCensored))

  if (nrow(central) > 0) {
    plot <- plot +
      ggplot2::geom_text(
        data = central,
        mapping = ggplot2::aes(x = .data$binMid, y = .data$nPersons, label = formatNumber(.data$nPersons)),
        vjust = -0.5, colour = primaryInk, size = 3.2
      )
  }
  plot
}

# Axis breaks that are whole numbers (persons are counted)
integerBreaks <- function(limits) {
  breaks <- pretty(limits)
  breaks[breaks == round(breaks)]
}

formatNumber <- function(x) {
  format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
}

captionText <- function(binWidth, minCellCount, nCensored) {
  text <- sprintf(
    "Index date = first cohort entry of a person. Bins are %s days wide; a positive difference means the drug starts after the prostate cancer index date.",
    format(binWidth)
  )
  if (nCensored > 0) {
    text <- paste0(text, sprintf("\n%d bin(s) with fewer than %s persons are censored and not drawn.", nCensored, minCellCount))
  }
  text
}

dayDifferenceTheme <- function() {
  ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      plot.background      = ggplot2::element_rect(fill = surfaceColor, colour = NA),
      panel.grid.minor     = ggplot2::element_blank(),
      panel.grid.major.x   = ggplot2::element_blank(),
      panel.grid.major.y   = ggplot2::element_line(colour = gridColor, linewidth = 0.3),
      plot.title           = ggplot2::element_text(face = "bold", colour = primaryInk),
      plot.subtitle        = ggplot2::element_text(colour = secondaryInk),
      plot.caption         = ggplot2::element_text(colour = secondaryInk, size = 8, hjust = 0),
      plot.title.position  = "plot",
      plot.caption.position = "plot",
      axis.text            = ggplot2::element_text(colour = secondaryInk),
      axis.title           = ggplot2::element_text(colour = secondaryInk),
      legend.position      = "top",
      legend.justification = "left",
      legend.title         = ggplot2::element_blank(),
      legend.key.size      = ggplot2::unit(0.9, "lines"),
      legend.text          = ggplot2::element_text(colour = secondaryInk)
    )
}
