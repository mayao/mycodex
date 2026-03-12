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
import { importDocumentHealthData } from "./document-importer";
import { importHealthData } from "./import-service";
import { importerSpecs } from "./specs";
import type { ImporterKey } from "./types";

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
    if (isDocumentLike(job.sourceFileName, job.mimeType)) {
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
  } catch (error) {
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
  const dataSourceId = ensureDataSource(input.database, input.userId, {
    sourceType: spec.sourceType,
    sourceName: spec.sourceName,
    ingestChannel: isDocumentLike(input.sourceFileName, input.mimeType) ? "document" : "file",
    sourceFile: input.sourceFileName,
    notes: `importer source ${spec.sourceType}`
  });
  const taskNotes = makeTaskNoteEntries([
    ["importer_key", input.importerKey],
    ["parse_mode", isDocumentLike(input.sourceFileName, input.mimeType) ? "document" : "tabular"],
    ["mime_type", input.mimeType]
  ]);
  const importTaskId = createImportTask(
    input.database,
    { userId: input.userId },
    {
      dataSourceId,
      taskType: isDocumentLike(input.sourceFileName, input.mimeType) ? "document_import" : spec.taskType,
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
