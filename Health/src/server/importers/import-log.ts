import type { DatabaseSync } from "node:sqlite";

import type { ImportLogEntry, ImportRowStatus } from "./types";

interface ImportRowLogRow {
  row_number: number;
  row_status: ImportRowStatus;
  metric_code: string | null;
  source_field: string | null;
  error_message: string | null;
  raw_payload_json: string;
  created_at: string;
}

function safeParseRawPayload(rawPayloadJson: string): Record<string, string> {
  try {
    return JSON.parse(rawPayloadJson) as Record<string, string>;
  } catch {
    return {};
  }
}

export function getImportRowLogs(
  database: DatabaseSync,
  importTaskId: string,
  rowStatus?: ImportRowStatus
): ImportLogEntry[] {
  const rows = rowStatus
    ? (database
        .prepare(
          `
          SELECT
            row_number,
            row_status,
            metric_code,
            source_field,
            error_message,
            raw_payload_json,
            created_at
          FROM import_row_log
          WHERE import_task_id = ? AND row_status = ?
          ORDER BY row_number ASC, created_at ASC
        `
        )
        .all(importTaskId, rowStatus) as unknown as ImportRowLogRow[])
    : (database
        .prepare(
          `
          SELECT
            row_number,
            row_status,
            metric_code,
            source_field,
            error_message,
            raw_payload_json,
            created_at
          FROM import_row_log
          WHERE import_task_id = ?
          ORDER BY row_number ASC, created_at ASC
        `
        )
        .all(importTaskId) as unknown as ImportRowLogRow[]);

  return rows.map((row) => ({
    rowNumber: row.row_number,
    rowStatus: row.row_status,
    metricCode: row.metric_code ?? undefined,
    sourceField: row.source_field ?? undefined,
    errorMessage: row.error_message ?? undefined,
    rawPayload: safeParseRawPayload(row.raw_payload_json),
    createdAt: row.created_at
  }));
}

export function getFailedImportRowLogs(
  database: DatabaseSync,
  importTaskId: string
): ImportLogEntry[] {
  return getImportRowLogs(database, importTaskId, "failed");
}
