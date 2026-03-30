import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import type {
  ImportExecutionResult,
  ImportFieldMapping,
  ImportRequest,
  ImportRowResult,
  ImportTaskStatus,
  ImportWarning,
  ImporterSpec
} from "./types";

export interface DataSourceConfig {
  sourceType: string;
  sourceName: string;
  ingestChannel: string;
  sourceFile?: string;
  notes?: string;
}

export interface ImportTaskConfig {
  dataSourceId: string;
  taskType: string;
  taskStatus?: ImportTaskStatus;
  sourceType: string;
  sourceFile?: string;
  notes?: string;
}

export interface MetricRecordInsertInput {
  userId: string;
  dataSourceId: string;
  importTaskId?: string;
  metricCode: string;
  metricName: string;
  category: string;
  rawValue: string;
  normalizedValue: number;
  unit: string;
  referenceRange?: string | null;
  abnormalFlag: string;
  sampleTime: string;
  sourceType: string;
  sourceFile?: string;
  notes?: string | null;
  replaceExisting?: boolean;
}

function formatNoteEntries(entries: Array<[string, string | undefined]>): string | undefined {
  const parts = entries
    .map(([key, value]) => [key.trim(), value?.trim()] as const)
    .filter(([, value]) => Boolean(value))
    .map(([key, value]) => `${key}=${value}`);

  return parts.length > 0 ? parts.join(" | ") : undefined;
}

export function appendTaskNotes(base: string | undefined, next: string | undefined): string | undefined {
  if (base && next) {
    return `${base} | ${next}`;
  }

  return base ?? next;
}

export function makeTaskNoteEntries(entries: Array<[string, string | undefined]>): string | undefined {
  return formatNoteEntries(entries);
}

export function buildReferenceRange(mapping: ImportFieldMapping): string | null {
  if (mapping.referenceRange) {
    return mapping.referenceRange;
  }

  if (typeof mapping.referenceLow === "number" && typeof mapping.referenceHigh === "number") {
    return `${mapping.referenceLow} - ${mapping.referenceHigh} ${mapping.canonicalUnit}`;
  }

  if (typeof mapping.referenceLow === "number") {
    return `>= ${mapping.referenceLow} ${mapping.canonicalUnit}`;
  }

  if (typeof mapping.referenceHigh === "number") {
    return `<= ${mapping.referenceHigh} ${mapping.canonicalUnit}`;
  }

  return null;
}

export function ensureMetricDefinition(
  database: DatabaseSync,
  mapping: ImportFieldMapping,
  supportedSourceTypes: string
): void {
  database
    .prepare(
      `
      INSERT INTO metric_definition (
        metric_code,
        metric_name,
        category,
        description,
        canonical_unit,
        better_direction,
        reference_range,
        supported_source_types,
        is_active,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT(metric_code) DO UPDATE SET
        metric_name = excluded.metric_name,
        category = excluded.category,
        description = excluded.description,
        canonical_unit = excluded.canonical_unit,
        better_direction = excluded.better_direction,
        reference_range = excluded.reference_range,
        supported_source_types = excluded.supported_source_types,
        updated_at = CURRENT_TIMESTAMP
    `
    )
    .run(
      mapping.metricCode,
      mapping.metricName,
      mapping.category,
      mapping.description,
      mapping.canonicalUnit,
      mapping.betterDirection,
      buildReferenceRange(mapping),
      supportedSourceTypes
    );
}

export function ensureDataSource(
  database: DatabaseSync,
  userId: string,
  config: DataSourceConfig
): string {
  const sourceId = `data-source::${userId}::${config.sourceType}`;

  database
    .prepare(
      `
      INSERT INTO data_source (
        id, user_id, source_type, source_name, vendor, ingest_channel,
        source_file, notes, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT(id) DO UPDATE SET
        source_name = excluded.source_name,
        ingest_channel = excluded.ingest_channel,
        source_file = excluded.source_file,
        notes = excluded.notes,
        updated_at = CURRENT_TIMESTAMP
    `
    )
    .run(
      sourceId,
      userId,
      config.sourceType,
      config.sourceName,
      null,
      config.ingestChannel,
      config.sourceFile ?? null,
      config.notes ?? null
    );

  return sourceId;
}

export function createImportTask(
  database: DatabaseSync,
  request: Pick<ImportRequest, "userId">,
  config: ImportTaskConfig
): string {
  const importTaskId = `import-task::${randomUUID()}`;

  database
    .prepare(
      `
      INSERT INTO import_task (
        id, user_id, data_source_id, task_type, task_status, source_type,
        source_file, started_at, finished_at, total_records, success_records,
        failed_records, notes, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    `
    )
    .run(
      importTaskId,
      request.userId,
      config.dataSourceId,
      config.taskType,
      config.taskStatus ?? "running",
      config.sourceType,
      config.sourceFile ?? null,
      new Date().toISOString(),
      null,
      0,
      0,
      0,
      config.notes ?? null
    );

  return importTaskId;
}

export function finalizeImportTask(
  database: DatabaseSync,
  importTaskId: string,
  taskStatus: ImportTaskStatus,
  totalRecords: number,
  successRecords: number,
  failedRecords: number,
  notes?: string
): void {
  database
    .prepare(
      `
      UPDATE import_task
      SET
        task_status = ?,
        finished_at = ?,
        total_records = ?,
        success_records = ?,
        failed_records = ?,
        notes = ?,
        created_at = created_at
      WHERE id = ?
    `
    )
    .run(
      taskStatus,
      new Date().toISOString(),
      totalRecords,
      successRecords,
      failedRecords,
      notes ?? null,
      importTaskId
    );
}

export function insertImportRowLog(
  database: DatabaseSync,
  importTaskId: string,
  result: ImportRowResult,
  auditPayload: Record<string, string>
): void {
  database
    .prepare(
      `
      INSERT INTO import_row_log (
        id, import_task_id, row_number, row_status, metric_code,
        source_field, error_message, raw_payload_json, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    `
    )
    .run(
      randomUUID(),
      importTaskId,
      result.rowNumber,
      result.status,
      result.metricCode ?? null,
      result.sourceField ?? null,
      result.errorMessage ?? null,
      JSON.stringify(auditPayload)
    );
}

export function buildTaskNotes(warnings: ImportWarning[], fatalError?: string): string {
  const notes = [`warning_count=${warnings.length}`];
  const warningCodes = [...new Set(warnings.map((warning) => warning.code))];

  if (warningCodes.length > 0) {
    notes.push(`warning_codes=${warningCodes.join(",")}`);
  }

  if (fatalError) {
    notes.push(`fatal_reason=${fatalError}`);
  }

  return notes.join(" | ");
}

export function upsertMetricRecord(
  database: DatabaseSync,
  input: MetricRecordInsertInput
): void {
  if (input.replaceExisting) {
    database
      .prepare(
        `
        DELETE FROM metric_record
        WHERE user_id = ? AND source_type = ? AND metric_code = ? AND sample_time = ?
      `
      )
      .run(input.userId, input.sourceType, input.metricCode, input.sampleTime);
  }

  database
    .prepare(
      `
      INSERT INTO metric_record (
        id, user_id, data_source_id, import_task_id, metric_code,
        metric_name, category, raw_value, normalized_value, unit,
        reference_range, abnormal_flag, sample_time, source_type,
        source_file, notes, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    `
    )
    .run(
      randomUUID(),
      input.userId,
      input.dataSourceId,
      input.importTaskId ?? null,
      input.metricCode,
      input.metricName,
      input.category,
      input.rawValue,
      input.normalizedValue,
      input.unit,
      input.referenceRange ?? null,
      input.abnormalFlag,
      input.sampleTime,
      input.sourceType,
      input.sourceFile ?? null,
      input.notes ?? null
    );
}

export interface ImportTaskRow extends ImportExecutionResult {
  taskType: string;
  sourceType: string;
  sourceFile?: string;
  startedAt: string;
  finishedAt?: string;
  notes?: string;
  parseMode?: string;
}

interface ImportTaskQueryRow {
  id: string;
  task_type: string;
  task_status: ImportTaskStatus;
  source_type: string;
  source_file: string | null;
  started_at: string;
  finished_at: string | null;
  total_records: number;
  success_records: number;
  failed_records: number;
  notes: string | null;
}

function parseTaskNotes(notes: string | null): Record<string, string> {
  return Object.fromEntries(
    (notes ?? "")
      .split("|")
      .map((item) => item.trim())
      .filter(Boolean)
      .map((item) => {
        const separator = item.indexOf("=");
        return separator === -1
          ? [item, ""]
          : [item.slice(0, separator).trim(), item.slice(separator + 1).trim()];
      })
  );
}

function importerKeyFromRow(row: ImportTaskQueryRow): ImportRequest["importerKey"] | undefined {
  const noteMap = parseTaskNotes(row.notes);
  const importerKey = noteMap.importer_key;

  if (
    importerKey === "annual_exam" ||
    importerKey === "blood_test" ||
    importerKey === "body_scale" ||
    importerKey === "activity" ||
    importerKey === "genetic" ||
    importerKey === "diet"
  ) {
    return importerKey;
  }

  switch (row.task_type) {
    case "annual_exam_import":
      return "annual_exam";
    case "blood_test_import":
      return "blood_test";
    case "body_scale_import":
      return "body_scale";
    case "activity_import":
      return "activity";
    case "genetic_import":
      return "genetic";
    case "diet_import":
      return "diet";
    default:
      return undefined;
  }
}

function toImportTaskRow(row: ImportTaskQueryRow): ImportTaskRow {
  const noteMap = parseTaskNotes(row.notes);
  const importerKey = importerKeyFromRow(row);

  return {
    importTaskId: row.id,
    importerKey: importerKey ?? "activity",
    filePath: row.source_file ?? "",
    taskStatus: row.task_status,
    totalRecords: row.total_records,
    successRecords: row.success_records,
    failedRecords: row.failed_records,
    logSummary: [],
    warnings: [],
    taskType: row.task_type,
    sourceType: row.source_type,
    sourceFile: row.source_file ?? undefined,
    startedAt: row.started_at,
    finishedAt: row.finished_at ?? undefined,
    notes: row.notes ?? undefined,
    parseMode: noteMap.parse_mode
  };
}

export function listRecentImportTasks(
  database: DatabaseSync,
  userId: string,
  limit = 12
): ImportTaskRow[] {
  const rows = database
    .prepare(
      `
      SELECT
        id,
        task_type,
        task_status,
        source_type,
        source_file,
        started_at,
        finished_at,
        total_records,
        success_records,
        failed_records,
        notes
      FROM import_task
      WHERE user_id = ?
      ORDER BY started_at DESC, created_at DESC
      LIMIT ?
    `
    )
    .all(userId, limit) as unknown as ImportTaskQueryRow[];

  return rows.map((row) => toImportTaskRow(row));
}

export function getImportTaskRow(
  database: DatabaseSync,
  userId: string,
  importTaskId: string
): ImportTaskRow | undefined {
  const row = database
    .prepare(
      `
      SELECT
        id,
        task_type,
        task_status,
        source_type,
        source_file,
        started_at,
        finished_at,
        total_records,
        success_records,
        failed_records,
        notes
      FROM import_task
      WHERE user_id = ? AND id = ?
      LIMIT 1
    `
    )
    .get(userId, importTaskId) as ImportTaskQueryRow | undefined;

  return row ? toImportTaskRow(row) : undefined;
}

export function markImportTaskFailed(
  database: DatabaseSync,
  importTaskId: string,
  message: string
): void {
  const existing = database
    .prepare(
      `
      SELECT
        total_records,
        success_records,
        failed_records,
        notes
      FROM import_task
      WHERE id = ?
      LIMIT 1
    `
    )
    .get(importTaskId) as
    | {
        total_records: number;
        success_records: number;
        failed_records: number;
        notes: string | null;
      }
    | undefined;

  finalizeImportTask(
    database,
    importTaskId,
    "failed",
    existing?.total_records ?? 0,
    existing?.success_records ?? 0,
    Math.max(existing?.failed_records ?? 0, 1),
    appendTaskNotes(existing?.notes ?? undefined, `fatal_reason=${message}`)
  );
}

export function taskRowDisplayTitle(task: ImportTaskRow): string {
  switch (task.taskType) {
    case "annual_exam_import":
      return "年度体检导入";
    case "blood_test_import":
      return "血液检查导入";
    case "body_scale_import":
      return "体脂秤导入";
    case "activity_import":
      return "运动数据导入";
    case "genetic_import":
      return "基因报告导入";
    case "diet_import":
      return "饮食健康导入";
    case "document_import":
      return "文档识别导入";
    case "healthkit_sync":
      return "Apple 健康同步";
    default:
      return "数据任务";
  }
}
