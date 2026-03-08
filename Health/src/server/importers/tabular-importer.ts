import { randomUUID } from "node:crypto";
import { basename } from "node:path";
import type { DatabaseSync } from "node:sqlite";

import { buildImportAuditPayload } from "./import-privacy";
import { canonicalizeUnit, extractUnitFromHeader, normalizeHeader, stripHeaderUnit } from "./header-utils";
import { readTabularFile } from "./tabular-reader";
import { computeAbnormalFlag, normalizeMetricValue } from "./unit-normalizer";
import type {
  ImportExecutionResult,
  ImportFieldMapping,
  ImportRequest,
  ImportRowResult,
  ImportTaskStatus,
  ImportWarning,
  ImporterSpec,
  MappedHeader
} from "./types";

function buildReferenceRange(mapping: ImportFieldMapping): string | null {
  if (mapping.referenceRange) {
    return mapping.referenceRange;
  }

  if (
    typeof mapping.referenceLow === "number" &&
    typeof mapping.referenceHigh === "number"
  ) {
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

function formatSampleTime(value: string): string | undefined {
  const trimmed = value.trim();

  if (!trimmed) {
    return undefined;
  }

  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return `${trimmed}T08:00:00+08:00`;
  }

  if (/^\d{4}\/\d{2}\/\d{2}$/.test(trimmed)) {
    return `${trimmed.replaceAll("/", "-")}T08:00:00+08:00`;
  }

  if (/^\d{4}-\d{2}-\d{2}[ tT]\d{2}:\d{2}(:\d{2})?$/.test(trimmed)) {
    const normalized = trimmed.replace(" ", "T");
    return normalized.includes("+") ? normalized : `${normalized}+08:00`;
  }

  if (/^\d{4}\/\d{2}\/\d{2}[ tT]\d{2}:\d{2}(:\d{2})?$/.test(trimmed)) {
    return `${trimmed.replaceAll("/", "-").replace(" ", "T")}+08:00`;
  }

  return undefined;
}

function resolveSampleTime(row: Record<string, string>, aliases: string[]): string | undefined {
  const aliasSet = new Set(aliases.map((alias) => normalizeHeader(alias)));

  for (const [header, value] of Object.entries(row)) {
    if (aliasSet.has(normalizeHeader(header))) {
      const parsed = formatSampleTime(value);

      if (parsed) {
        return parsed;
      }
    }
  }

  return undefined;
}

function collectValues(row: Record<string, string>, aliases: string[]): string[] {
  const aliasSet = new Set(aliases.map((alias) => normalizeHeader(alias)));

  return Object.entries(row)
    .filter(([header, value]) => aliasSet.has(normalizeHeader(header)) && value.trim())
    .map(([, value]) => value.trim());
}

function resolveMappedHeaders(
  headers: string[],
  fieldMappings: ImportFieldMapping[]
): MappedHeader[] {
  return headers.flatMap((header) => {
    const baseHeader = normalizeHeader(stripHeaderUnit(header));
    const mapping = fieldMappings.find((candidate) =>
      candidate.aliases.some((alias) => normalizeHeader(alias) === baseHeader)
    );

    return mapping
      ? [
          {
            header,
            headerUnit: canonicalizeUnit(extractUnitFromHeader(header)),
            mapping
          }
        ]
      : [];
  });
}

function parseNumericValue(rawValue: string): number {
  const numeric = Number(
    rawValue
      .trim()
      .replace(/,/g, "")
      .replace(/，/g, "")
      .replace(/%$/g, "")
  );

  if (!Number.isFinite(numeric)) {
    throw new Error("Invalid numeric value");
  }

  return numeric;
}

function ensureMetricDefinition(database: DatabaseSync, mapping: ImportFieldMapping): void {
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
      "csv,xlsx,xls"
    );
}

function ensureDataSource(
  database: DatabaseSync,
  userId: string,
  sourceType: string,
  sourceName: string
): string {
  const sourceId = `data-source::${sourceType}`;

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
        updated_at = CURRENT_TIMESTAMP
    `
    )
    .run(
      sourceId,
      userId,
      sourceType,
      sourceName,
      null,
      "file",
      null,
      `importer source ${sourceType}`
    );

  return sourceId;
}

function insertImportRowLog(
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

function buildTaskNotes(warnings: ImportWarning[], fatalError?: string): string {
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

function createImportTask(
  database: DatabaseSync,
  request: ImportRequest,
  spec: ImporterSpec,
  dataSourceId: string
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
      dataSourceId,
      spec.taskType,
      "running",
      spec.sourceType,
      basename(request.filePath),
      new Date().toISOString(),
      null,
      0,
      0,
      0,
      null
    );

  return importTaskId;
}

function finalizeImportTask(
  database: DatabaseSync,
  importTaskId: string,
  taskStatus: ImportTaskStatus,
  totalRecords: number,
  successRecords: number,
  failedRecords: number,
  notes: string
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
        notes = ?
      WHERE id = ?
    `
    )
    .run(
      taskStatus,
      new Date().toISOString(),
      totalRecords,
      successRecords,
      failedRecords,
      notes,
      importTaskId
    );
}

export function executeTabularImport(
  database: DatabaseSync,
  spec: ImporterSpec,
  request: ImportRequest
): ImportExecutionResult {
  const sourceFile = basename(request.filePath);
  const data = readTabularFile(request.filePath);
  const mappedHeaders = resolveMappedHeaders(data.headers, spec.fieldMappings);
  const warnings: ImportWarning[] = data.headers
    .filter(
      (header) =>
        !mappedHeaders.some((candidate) => candidate.header === header) &&
        !spec.sampleTimeAliases.some((alias) => normalizeHeader(alias) === normalizeHeader(header)) &&
        !spec.noteAliases.some((alias) => normalizeHeader(alias) === normalizeHeader(header)) &&
        !(spec.contextAliases ?? []).some(
          (alias) => normalizeHeader(alias) === normalizeHeader(header)
        )
    )
    .map((header) => ({
      code: "unmapped_header",
      header,
      message: `Unmapped header: ${header}`
    }));
  const dataSourceId = ensureDataSource(database, request.userId, spec.sourceType, spec.sourceName);
  const importTaskId = createImportTask(database, request, spec, dataSourceId);
  const logSummary: ImportRowResult[] = [];

  for (const header of mappedHeaders) {
    ensureMetricDefinition(database, header.mapping);
  }

  if (data.rows.length === 0) {
    warnings.push({
      code: "empty_file",
      message: "No data rows found in import file"
    });

    finalizeImportTask(
      database,
      importTaskId,
      "failed",
      0,
      0,
      0,
      buildTaskNotes(warnings, "fatal import error")
    );

    return {
      importTaskId,
      importerKey: request.importerKey,
      filePath: request.filePath,
      taskStatus: "failed",
      totalRecords: 0,
      successRecords: 0,
      failedRecords: 0,
      logSummary,
      warnings
    };
  }

  if (mappedHeaders.length === 0) {
    warnings.push({
      code: "no_mapped_headers",
      message: "No supported metric headers found in import file"
    });

    finalizeImportTask(
      database,
      importTaskId,
      "failed",
      0,
      0,
      0,
      buildTaskNotes(warnings, "fatal import error")
    );

    return {
      importTaskId,
      importerKey: request.importerKey,
      filePath: request.filePath,
      taskStatus: "failed",
      totalRecords: 0,
      successRecords: 0,
      failedRecords: 0,
      logSummary,
      warnings
    };
  }

  let totalRecords = 0;
  let successRecords = 0;
  let failedRecords = 0;

  database.exec("BEGIN");

  try {
    data.rows.forEach((row, index) => {
      const rowNumber = index + 2;
      const auditPayload = buildImportAuditPayload(row, spec, mappedHeaders);
      const sampleTime = resolveSampleTime(row, spec.sampleTimeAliases);
      const noteParts = [
        ...collectValues(row, spec.noteAliases),
        ...collectValues(row, spec.contextAliases ?? [])
      ];
      const noteText = noteParts.length > 0 ? noteParts.join(" | ") : null;
      const availableFields = mappedHeaders.filter((header) => row[header.header]?.trim());

      if (availableFields.length === 0) {
        const warning: ImportWarning = {
          code: "unmapped_row",
          rowNumber,
          message: `Row ${rowNumber} skipped because no mapped metric value was found`
        };
        const result: ImportRowResult = {
          rowNumber,
          status: "skipped",
          errorMessage: warning.message
        };

        warnings.push(warning);
        logSummary.push(result);
        insertImportRowLog(database, importTaskId, result, auditPayload);
        return;
      }

      if (!sampleTime) {
        for (const field of availableFields) {
          totalRecords += 1;
          failedRecords += 1;
          const result: ImportRowResult = {
            rowNumber,
            status: "failed",
            metricCode: field.mapping.metricCode,
            sourceField: field.header,
            errorMessage: "Missing or invalid sample_time"
          };

          logSummary.push(result);
          insertImportRowLog(database, importTaskId, result, auditPayload);
        }

        return;
      }

      for (const field of availableFields) {
        totalRecords += 1;

        try {
          const rawValue = parseNumericValue(row[field.header]);
          const normalized = normalizeMetricValue({
            rawValue,
            rawUnit: field.headerUnit,
            mapping: field.mapping
          });
          const abnormalFlag = computeAbnormalFlag(normalized.normalizedValue, field.mapping);

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
              request.userId,
              dataSourceId,
              importTaskId,
              field.mapping.metricCode,
              field.mapping.metricName,
              field.mapping.category,
              row[field.header].trim(),
              normalized.normalizedValue,
              normalized.normalizedUnit,
              buildReferenceRange(field.mapping),
              abnormalFlag,
              sampleTime,
              spec.sourceType,
              sourceFile,
              noteText
            );

          const result: ImportRowResult = {
            rowNumber,
            status: "imported",
            metricCode: field.mapping.metricCode,
            sourceField: field.header
          };

          successRecords += 1;
          logSummary.push(result);
          insertImportRowLog(database, importTaskId, result, auditPayload);
        } catch (error) {
          const result: ImportRowResult = {
            rowNumber,
            status: "failed",
            metricCode: field.mapping.metricCode,
            sourceField: field.header,
            errorMessage: error instanceof Error ? error.message : "Unknown import error"
          };

          failedRecords += 1;
          logSummary.push(result);
          insertImportRowLog(database, importTaskId, result, auditPayload);
        }
      }
    });

    const taskStatus: ImportTaskStatus =
      successRecords === 0 && failedRecords > 0
        ? "failed"
        : failedRecords > 0
          ? "completed_with_errors"
          : successRecords > 0
            ? "completed"
            : "failed";

    database.exec("COMMIT");
    finalizeImportTask(
      database,
      importTaskId,
      taskStatus,
      totalRecords,
      successRecords,
      failedRecords,
      buildTaskNotes(warnings, taskStatus === "failed" ? "fatal import error" : undefined)
    );

    return {
      importTaskId,
      importerKey: request.importerKey,
      filePath: request.filePath,
      taskStatus,
      totalRecords,
      successRecords,
      failedRecords,
      logSummary,
      warnings
    };
  } catch (error) {
    database.exec("ROLLBACK");
    finalizeImportTask(
      database,
      importTaskId,
      "failed",
      totalRecords,
      successRecords,
      failedRecords,
      buildTaskNotes(
        warnings,
        error instanceof Error ? "fatal import error" : "fatal import error"
      )
    );
    throw error;
  }
}
