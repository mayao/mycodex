import { randomUUID } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { extname, join } from "node:path";

import { revalidatePath } from "next/cache";

import { getAuthenticatedUserId, AuthError } from "../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../server/http/safe-response";
import { getDatabase } from "../../../server/db/sqlite";
import {
  enqueueImportJob
} from "../../../server/importers/async-import-queue";
import { buildImportTaskCompletionPreview } from "../../../server/importers/import-task-presentation";
import {
  listRecentImportTasks,
  taskRowDisplayTitle
} from "../../../server/importers/import-task-support";
import type { ImporterKey } from "../../../server/importers/types";

const supportedImporters = new Set<ImporterKey>([
  "annual_exam",
  "blood_test",
  "body_scale",
  "activity",
  "genetic",
  "diet"
]);

function toSafeFilename(filename: string): string {
  const base = filename.replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/-+/g, "-");
  return base || `upload${extname(filename) || ".bin"}`;
}

function serializeTask(task: ReturnType<typeof listRecentImportTasks>[number]) {
  const database = getDatabase();
  return {
    importTaskId: task.importTaskId,
    title: taskRowDisplayTitle(task),
    importerKey: task.notes?.includes("importer_key=") ? task.importerKey : undefined,
    taskType: task.taskType,
    taskStatus: task.taskStatus,
    sourceType: task.sourceType,
    sourceFile: task.sourceFile,
    startedAt: task.startedAt,
    finishedAt: task.finishedAt,
    totalRecords: task.totalRecords,
    successRecords: task.successRecords,
    failedRecords: task.failedRecords,
    parseMode: task.parseMode,
    completionPreview: buildImportTaskCompletionPreview(database, task)
  };
}

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const tasks = listRecentImportTasks(getDatabase(), userId);
    return jsonOk({ tasks: tasks.map((task) => serializeTask(task)) });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/imports", method: "GET" } });
    }
    return jsonSafeError({ message: "获取任务列表失败", status: 500, error, context: { route: "/api/imports", method: "GET" } });
  }
}

export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const formData = await request.formData();
    const importerKey = formData.get("importerKey");
    const file = formData.get("file");
    const extractedText = formData.get("extractedText");

    if (typeof importerKey !== "string" || !supportedImporters.has(importerKey as ImporterKey)) {
      return jsonSafeError("请选择正确的数据类型。", 400);
    }

    if (!(file instanceof File) || file.size === 0) {
      return jsonSafeError("请选择要上传的数据文件。", 400);
    }

    const uploadDir = join(process.cwd(), "data", "uploads");
    await mkdir(uploadDir, { recursive: true });

    const tempFilePath = join(uploadDir, `${Date.now()}-${randomUUID()}-${toSafeFilename(file.name)}`);
    await writeFile(tempFilePath, Buffer.from(await file.arrayBuffer()));

    const task = enqueueImportJob({
      database: getDatabase(),
      importerKey: importerKey as ImporterKey,
      userId,
      filePath: tempFilePath,
      sourceFileName: file.name,
      mimeType: file.type || undefined,
      extractedText: typeof extractedText === "string" ? extractedText : undefined
    });

    if (!task) {
      return jsonSafeError("上传任务创建失败，请稍后重试。", 500);
    }

    revalidatePath("/", "layout");
    revalidatePath("/data", "page");

    return jsonOk(
      { accepted: true, task: serializeTask(task) },
      { status: 202 }
    );
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/imports", method: "POST" } });
    }
    return jsonSafeError({
      message: "上传任务创建失败，请稍后重试。",
      status: 400,
      error
    });
  }
}
