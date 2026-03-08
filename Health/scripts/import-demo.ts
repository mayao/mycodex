import path from "node:path";

import { runPendingMigrations } from "../src/server/db/migration-runner";
import { createInMemoryDatabase } from "../src/server/db/sqlite";
import { seedDatabase } from "../src/server/db/seed";
import { generateStructuredInsights } from "../src/server/insights/structured-rule-engine";
import { getFailedImportRowLogs, importHealthData } from "../src/server/importers/import-service";

const database = createInMemoryDatabase();
seedDatabase(database);
runPendingMigrations(database);

const sampleDirectory = path.join(process.cwd(), "samples", "import");

const jobs = [
  ["annual_exam", "annual_exam_sample.csv"],
  ["blood_test", "blood_test_sample.csv"],
  ["body_scale", "body_scale_sample.csv"],
  ["activity", "activity_sample.csv"],
  ["activity", "activity_invalid_sample.csv"]
] as const;

const results = jobs.map(([importerKey, fileName]) =>
  importHealthData(database, {
    importerKey,
    userId: "user-self",
    filePath: path.join(sampleDirectory, fileName)
  })
);

console.log("Import task summary:");
console.table(
  results.map((result) => ({
    importer: result.importerKey,
    file: path.basename(result.filePath),
    taskId: result.importTaskId,
    status: result.taskStatus,
    total: result.totalRecords,
    success: result.successRecords,
    failed: result.failedRecords,
    warnings: result.warnings.length
  }))
);

const taskIds = results.map((result) => result.importTaskId);
const placeholders = taskIds.map(() => "?").join(", ");

const importedRows = database
  .prepare(
    `
    SELECT
      metric_code,
      abnormal_flag,
      source_type,
      COUNT(*) AS record_count
    FROM metric_record
    WHERE import_task_id IN (${placeholders})
    GROUP BY metric_code, abnormal_flag, source_type
    ORDER BY metric_code ASC, source_type ASC
    LIMIT 20
  `
  )
  .all(...taskIds);

console.log("\nImported metric_record summary:");
console.table(importedRows);

const failedRows = results.flatMap((result) =>
  getFailedImportRowLogs(database, result.importTaskId).map((row) => ({
    importTaskId: result.importTaskId,
    rowNumber: row.rowNumber,
    metricCode: row.metricCode,
    sourceField: row.sourceField,
    errorMessage: row.errorMessage,
    auditFieldCount: Object.keys(row.rawPayload).length,
    auditFields: Object.keys(row.rawPayload).join(", ")
  }))
);

console.log("\nFailed import rows:");
console.table(failedRows);

const structuredInsights = generateStructuredInsights(database, "user-self");

console.log("\nStructured insights summary:");
console.table(
  structuredInsights.insights.slice(0, 10).map((insight) => ({
    id: insight.id,
    severity: insight.severity,
    title: insight.title
  }))
);
