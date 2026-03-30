import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getDatabase } from "../../../../server/db/sqlite";
import { getImportTaskRow, taskRowDisplayTitle } from "../../../../server/importers/import-task-support";
import { buildImportTaskCompletionPreview } from "../../../../server/importers/import-task-presentation";

function serializeTask(task: NonNullable<ReturnType<typeof getImportTaskRow>>) {
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

export async function GET(
  request: Request,
  context: { params: Promise<{ taskId: string }> }
) {
  try {
    const userId = getAuthenticatedUserId(request);
    const { taskId } = await context.params;
    const task = getImportTaskRow(getDatabase(), userId, taskId);

    if (!task) {
      return jsonSafeError("没有找到对应的数据任务。", 404);
    }

    return jsonOk({ task: serializeTask(task) });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/imports/[taskId]", method: "GET" } });
    }
    return jsonSafeError({ message: "获取任务详情失败", status: 500, error, context: { route: "/api/imports/[taskId]", method: "GET" } });
  }
}
