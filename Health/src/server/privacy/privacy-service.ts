import type { DatabaseSync } from "node:sqlite";

import { z } from "zod";

import { getAppEnv } from "../config/env";
import { getDatabase } from "../db/sqlite";
import { sensitiveFieldCatalog } from "./sensitive-fields";

export const privacyExportRequestSchema = z.object({
  scope: z.enum(["metrics", "reports", "imports", "all"]).default("all"),
  format: z.enum(["json", "zip"]).default("json"),
  includeAuditLogs: z.boolean().default(false)
});

export const privacyDeleteRequestSchema = z.object({
  scope: z.enum(["metrics", "reports", "imports", "all"]).default("all"),
  importTaskId: z.string().min(1).optional(),
  confirm: z.boolean().default(false)
});

interface PrivacyFootprint {
  metricRecords: number;
  reportSnapshots: number;
  importTasks: number;
  importRowLogs: number;
}

function queryCount(database: DatabaseSync, sql: string, ...args: Array<string | number>) {
  const row = database.prepare(sql).get(...args) as { count: number };
  return row.count;
}

function getPrivacyFootprint(database: DatabaseSync, userId: string): PrivacyFootprint {
  return {
    metricRecords: queryCount(
      database,
      "SELECT COUNT(*) AS count FROM metric_record WHERE user_id = ?",
      userId
    ),
    reportSnapshots: queryCount(
      database,
      "SELECT COUNT(*) AS count FROM report_snapshot WHERE user_id = ?",
      userId
    ),
    importTasks: queryCount(
      database,
      "SELECT COUNT(*) AS count FROM import_task WHERE user_id = ?",
      userId
    ),
    importRowLogs: queryCount(
      database,
      `
      SELECT COUNT(*) AS count
      FROM import_row_log AS log
      INNER JOIN import_task AS task
        ON task.id = log.import_task_id
      WHERE task.user_id = ?
      `,
      userId
    )
  };
}

function describeImportStoragePolicy() {
  return {
    fileContent: "不在 SQLite 中保存完整导入文件内容。",
    structuredMetrics: "标准化后的指标写入 metric_record，供趋势分析与报告生成使用。",
    taskMetadata: "import_task 与 data_source 仅保留最小必要的来源元数据，如 source_type 与文件名基线信息。",
    auditLogs:
      "import_row_log 沿用 raw_payload_json 列名，但保存的是脱敏后的字段标签或关闭审计后的占位摘要，不再保存原始行明文。",
    legacyData:
      "阶段 8 迁移会清理旧版行日志中的原始 payload，避免历史敏感数据继续留存在本地审计表中。"
  };
}

function getScopeImpact(scope: "metrics" | "reports" | "imports" | "all", footprint: PrivacyFootprint) {
  if (scope === "metrics") {
    return {
      metricRecords: footprint.metricRecords
    };
  }

  if (scope === "reports") {
    return {
      reportSnapshots: footprint.reportSnapshots
    };
  }

  if (scope === "imports") {
    return {
      importTasks: footprint.importTasks,
      importRowLogs: footprint.importRowLogs
    };
  }

  return footprint;
}

export function buildPrivacyExportPlaceholder(
  input: unknown,
  database: DatabaseSync = getDatabase(),
  userId: string = "user-self"
) {
  const request = privacyExportRequestSchema.parse(input ?? {});
  const env = getAppEnv();
  const footprint = getPrivacyFootprint(database, userId);

  return {
    status: "placeholder",
    action: "export",
    enabled: env.HEALTH_ALLOW_LOCAL_EXPORTS,
    request,
    sensitiveFields: sensitiveFieldCatalog,
    storagePolicy: describeImportStoragePolicy(),
    availableData: getScopeImpact(request.scope, footprint),
    nextStep: "后续将在本地导出结构化指标、报告快照以及按需脱敏后的导入审计摘要。"
  };
}

export function buildPrivacyDeletePlaceholder(
  input: unknown,
  database: DatabaseSync = getDatabase(),
  userId: string = "user-self"
) {
  const request = privacyDeleteRequestSchema.parse(input ?? {});
  const env = getAppEnv();
  const footprint = getPrivacyFootprint(database, userId);

  return {
    status: "placeholder",
    action: "delete",
    enabled: env.HEALTH_ALLOW_LOCAL_DELETE,
    request,
    requiresExplicitConfirmation: true,
    sensitiveFields: sensitiveFieldCatalog,
    availableData: getScopeImpact(request.scope, footprint),
    nextStep: "后续将支持 dry-run、作用域校验、二次确认和按 importTaskId / scope 的分层删除。"
  };
}
