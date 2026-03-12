import { basename } from "node:path";
import type { DatabaseSync } from "node:sqlite";

import { buildImportAuditPayload } from "./import-privacy";
import { canonicalizeUnit, extractUnitFromHeader, normalizeHeader, stripHeaderUnit } from "./header-utils";
import {
  appendTaskNotes,
  buildReferenceRange,
  buildTaskNotes,
  createImportTask,
  ensureDataSource,
  ensureMetricDefinition,
  finalizeImportTask,
  insertImportRowLog,
  upsertMetricRecord
} from "./import-task-support";
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

export function executeTabularImport(
  database: DatabaseSync,
  spec: ImporterSpec,
  request: ImportRequest
): ImportExecutionResult {
  const sourceFile = request.sourceFileName ?? basename(request.filePath);
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
  const dataSourceId =
    request.dataSourceId ??
    ensureDataSource(database, request.userId, {
      sourceType: spec.sourceType,
      sourceName: spec.sourceName,
      ingestChannel: "file",
      sourceFile,
      notes: `importer source ${spec.sourceType}`
    });
  const importTaskId =
    request.importTaskId ??
    createImportTask(database, request, {
      dataSourceId,
      taskType: spec.taskType,
      sourceType: spec.sourceType,
      sourceFile,
      notes: request.taskNotes
    });
  const logSummary: ImportRowResult[] = [];

  for (const header of mappedHeaders) {
    ensureMetricDefinition(database, header.mapping, "csv,xlsx,xls,pdf,image,ocr");
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
      appendTaskNotes(request.taskNotes, buildTaskNotes(warnings, "fatal import error"))
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
      appendTaskNotes(request.taskNotes, buildTaskNotes(warnings, "fatal import error"))
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

          upsertMetricRecord(database, {
            userId: request.userId,
            dataSourceId,
            importTaskId,
            metricCode: field.mapping.metricCode,
            metricName: field.mapping.metricName,
            category: field.mapping.category,
            rawValue: row[field.header].trim(),
            normalizedValue: normalized.normalizedValue,
            unit: normalized.normalizedUnit,
            referenceRange: buildReferenceRange(field.mapping),
            abnormalFlag,
            sampleTime,
            sourceType: spec.sourceType,
            sourceFile,
            notes: noteText
          });

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
      appendTaskNotes(
        request.taskNotes,
        buildTaskNotes(warnings, taskStatus === "failed" ? "fatal import error" : undefined)
      )
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
      appendTaskNotes(
        request.taskNotes,
        buildTaskNotes(
          warnings,
          error instanceof Error ? "fatal import error" : "fatal import error"
        )
      )
    );
    throw error;
  }
}
