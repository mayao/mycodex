import type { DatabaseSync } from "node:sqlite";

import { getImportRowLogs } from "./import-log";
import type { ImportTaskRow } from "./import-task-support";

export interface ImportTaskCompletionPreview {
  headline: string;
  detail: string;
  actionTitle?: string;
  actionTarget?: string;
  aggregateDate?: string;
  recognizedFoods?: string[];
  estimatedCaloriesKcal?: number;
  mealUploadCount?: number;
}

function parseTaskNotes(notes: string | undefined): Record<string, string> {
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

function splitFoods(raw: string | undefined): string[] {
  return [...new Set(
    (raw ?? "")
      .split(/[、,，/|]/)
      .map((item) => item.trim())
      .filter(Boolean)
  )].slice(0, 8);
}

function firstPositiveInteger(values: Array<string | number | undefined>): number | undefined {
  for (const value of values) {
    const numeric = typeof value === "number" ? value : Number(value);
    if (Number.isFinite(numeric) && numeric > 0) {
      return Math.round(numeric);
    }
  }
  return undefined;
}

function buildDietPreview(database: DatabaseSync, task: ImportTaskRow): ImportTaskCompletionPreview {
  const logs = getImportRowLogs(database, task.importTaskId);
  const taskNotes = parseTaskNotes(task.notes);
  const foods = splitFoods(
    logs.find((item) => item.rawPayload.foods)?.rawPayload.foods ?? taskNotes.recognized_foods
  );
  const aggregateDate =
    logs.find((item) => item.rawPayload.aggregate_date)?.rawPayload.aggregate_date ??
    taskNotes.aggregate_date;
  const estimatedCaloriesKcal = firstPositiveInteger(
    logs.map((item) => item.rawPayload.estimated_calories_kcal)
  );
  const mealUploadCount = firstPositiveInteger(
    logs.map((item) => item.rawPayload.meal_upload_count)
  );

  const foodText = foods.length === 0 ? "已完成饮食识别" : `识别到 ${foods.join("、")}`;
  const calorieText = estimatedCaloriesKcal ? `约 ${estimatedCaloriesKcal} kcal` : "热量已计入汇总";
  const aggregateText = aggregateDate ? `已累计到 ${aggregateDate} 的饮食概览` : "已累计到今日饮食概览";
  const countText = mealUploadCount ? `，当前共记录 ${mealUploadCount} 次` : "";

  return {
    headline: "饮食图片解析完成",
    detail: `${foodText}，${calorieText}，${aggregateText}${countText}。`,
    actionTitle: "去看饮食洞察",
    actionTarget: "home_diet_insight",
    aggregateDate,
    recognizedFoods: foods,
    estimatedCaloriesKcal,
    mealUploadCount
  };
}

export function buildImportTaskCompletionPreview(
  database: DatabaseSync,
  task: ImportTaskRow
): ImportTaskCompletionPreview | undefined {
  if (task.finishedAt == null) {
    return undefined;
  }

  if (task.taskStatus === "failed") {
    return undefined;
  }

  switch (task.importerKey) {
    case "diet":
      return buildDietPreview(database, task);
    case "genetic":
      return {
        headline: "基因报告解析完成",
        detail: `已完成基因报告结构化解析，可前往首页查看“基因健康AI洞察”。`,
        actionTitle: "查看基因洞察",
        actionTarget: "home_genetic_insight"
      };
    case "annual_exam":
    case "blood_test":
      return {
        headline: "体检报告解析完成",
        detail: `已成功写入 ${task.successRecords} 条指标，可前往首页查看“体检报告AI洞察”和趋势变化。`,
        actionTitle: "查看体检洞察",
        actionTarget: "home_medical_insight"
      };
    case "body_scale":
      return {
        headline: "身体成分数据已更新",
        detail: `已成功写入 ${task.successRecords} 条身体组成数据，可前往首页查看核心指标和趋势板。`,
        actionTitle: "查看首页概览",
        actionTarget: "home"
      };
    case "activity":
      return {
        headline: "运动健康数据已更新",
        detail: `已成功写入 ${task.successRecords} 条运动或活动记录，可前往首页查看运动与睡眠分析。`,
        actionTitle: "查看首页概览",
        actionTarget: "home"
      };
    default:
      return undefined;
  }
}
