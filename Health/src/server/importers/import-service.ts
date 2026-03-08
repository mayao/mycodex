import type { DatabaseSync } from "node:sqlite";

import { getFailedImportRowLogs, getImportRowLogs } from "./import-log";
import { importers } from "./importer-registry";
import type { ImportExecutionResult, ImportRequest, ImporterKey } from "./types";

export function importHealthData(
  database: DatabaseSync,
  request: ImportRequest
): ImportExecutionResult {
  const importer = importers[request.importerKey];

  if (!importer) {
    throw new Error(`Unsupported importer: ${request.importerKey}`);
  }

  return importer.import(database, request);
}

export function getImporterKeys(): ImporterKey[] {
  return Object.keys(importers) as ImporterKey[];
}

export { getImportRowLogs, getFailedImportRowLogs };
