import { unlink } from "node:fs/promises";
import type { DatabaseSync } from "node:sqlite";

import {
  appendTaskNotes,
  createImportTask,
  ensureDataSource,
  getImportTaskRow,
  makeTaskNoteEntries,
  markImportTaskFailed
} from "./import-task-support";
import { importDietData } from "./diet-importer";
import { importDocumentHealthData } from "./document-importer";
import { importGeneticData } from "./genetic-importer";
import { importHealthData } from "./import-service";
import { importerSpecs } from "./specs";
import type { ImporterKey } from "./types";
import { invalidateInsightCache } from "../services/document-insight-ai-service";
import { deleteReportSnapshotsForUser } from "../repositories/unified-health-repository";

interface QueueImportJobInput {
  database: DatabaseSync;
  importerKey: ImporterKey;
  userId: string;
  filePath: string;
  sourceFileName: string;
  mimeType?: string;
  extractedText?: string;
}

let queueTail = Promise.resolve();

function isDocumentLike(sourceFileName: string, mimeType?: string): boolean {
  const normalized = sourceFileName.toLowerCase();

  if (normalized.endsWith(".csv") || normalized.endsWith(".xlsx") || normalized.endsWith(".xls")) {
    return false;
  }

  return true;
}

async function runQueuedImport(job: QueueImportJobInput & { importTaskId: string; dataSourceId: string; taskNotes?: string }) {
  try {
    if (job.importerKey === "genetic") {
      await importGeneticData(job.database, {
        userId: job.userId,
        filePath: job.filePath,
        importTaskId: job.importTaskId,
        dataSourceId: job.dataSourceId,
        sourceFileName: job.sourceFileName,
        taskNotes: job.taskNotes,
        extractedText: job.extractedText ?? ""
      });
    } else if (job.importerKey === "diet") {
      await importDietData(job.database, {
        userId: job.userId,
        filePath: job.filePath,
        importTaskId: job.importTaskId,
        dataSourceId: job.dataSourceId,
        sourceFileName: job.sourceFileName,
        taskNotes: job.taskNotes
      });
    } else if (isDocumentLike(job.sourceFileName, job.mimeType)) {
      await importDocumentHealthData(job.database, {
        importerKey: job.importerKey,
        userId: job.userId,
        filePath: job.filePath,
        importTaskId: job.importTaskId,
        dataSourceId: job.dataSourceId,
        sourceFileName: job.sourceFileName,
        taskNotes: job.taskNotes,
        extractedText: job.extractedText ?? ""
      });
    } else {
      importHealthData(job.database, {
        importerKey: job.importerKey,
        userId: job.userId,
        filePath: job.filePath,
        importTaskId: job.importTaskId,
        dataSourceId: job.dataSourceId,
        sourceFileName: job.sourceFileName,
        taskNotes: job.taskNotes
      });
    }
    // Invalidate insight cache after successful import
    const cacheType = job.importerKey === "annual_exam" || job.importerKey === "blood_test"
      ? "medical_exam" as const
      : job.importerKey === "genetic" ? "genetic" as const : undefined;
    invalidateInsightCache(job.userId, cacheType);
    deleteReportSnapshotsForUser(job.database, job.userId);
  } catch (error) {
    console.error(
      `[ImportQueue] ${job.importerKey} import failed for ${job.sourceFileName}:`,
      error instanceof Error ? error.stack ?? error.message : error
    );
    markImportTaskFailed(
      job.database,
      job.importTaskId,
      error instanceof Error ? error.message : "async import failed"
    );
  } finally {
    await unlink(job.filePath).catch(() => undefined);
  }
}

export function enqueueImportJob(input: QueueImportJobInput) {
  const spec = importerSpecs[input.importerKey];
  const usesSpecialTaskType = input.importerKey === "genetic" || input.importerKey === "diet";
  const parseMode = input.importerKey === "diet"
    ? "vision"
    : input.importerKey === "genetic"
      ? "genetic"
      : isDocumentLike(input.sourceFileName, input.mimeType)
        ? "document"
        : "tabular";
  const dataSourceId = ensureDataSource(input.database, input.userId, {
    sourceType: spec.sourceType,
    sourceName: spec.sourceName,
    ingestChannel: isDocumentLike(input.sourceFileName, input.mimeType) ? "document" : "file",
    sourceFile: input.sourceFileName,
    notes: `importer source ${spec.sourceType}`
  });
  const taskNotes = makeTaskNoteEntries([
    ["importer_key", input.importerKey],
    ["parse_mode", parseMode],
    ["mime_type", input.mimeType]
  ]);
  const importTaskId = createImportTask(
    input.database,
    { userId: input.userId },
    {
      dataSourceId,
      taskType: usesSpecialTaskType
        ? spec.taskType
        : isDocumentLike(input.sourceFileName, input.mimeType)
          ? "document_import"
          : spec.taskType,
      sourceType: spec.sourceType,
      sourceFile: input.sourceFileName,
      notes: taskNotes
    }
  );

  queueTail = queueTail
    .then(() =>
      runQueuedImport({
        ...input,
        importTaskId,
        dataSourceId,
        taskNotes
      })
    )
    .catch(() => undefined);

  return getImportTaskRow(input.database, input.userId, importTaskId);
}
