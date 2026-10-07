Place one ATLAS cohort definition JSON export per study cohort here, named `<atlasId>.json`
(the `atlasId` column of `../settings/CohortsToCreate.csv`: 1856-1863). Running
`../settings/insertCohortDefinition.R` downloads them from ATLAS.
The study cohort id (`cohortId` column) is what is written to the cohort table.
If `inst/sql/sql_server/<atlasId>.sql` does not exist, the SQL is generated from the JSON with CirceR.
