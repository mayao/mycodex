import { extname } from "node:path";
import type { DatabaseSync } from "node:sqlite";

import { callVisionLLMWithFallbacks } from "../services/vision-llm-service";
import { formatAppDate, formatAppDateTimeIso } from "../utils/app-time";
import {
  appendTaskNotes,
  ensureMetricDefinition,
  finalizeImportTask,
  insertImportRowLog,
  upsertMetricRecord
} from "./import-task-support";
import { importerSpecs } from "./specs";
import type { ImportExecutionResult } from "./types";

interface DietImportRequest {
  userId: string;
  filePath: string;
  sourceFileName: string;
  importTaskId: string;
  dataSourceId: string;
  taskNotes?: string;
}

interface DietVisionResult {
  foods: string[];
  estimatedCaloriesKcal: number;
  provider: string;
  model: string;
}

function isImageFile(fileName: string): boolean {
  return [".png", ".jpg", ".jpeg", ".webp", ".heic", ".heif"].includes(extname(fileName).toLowerCase());
}

function normalizeFoods(rawFoods: unknown): string[] {
  if (Array.isArray(rawFoods)) {
    return rawFoods
      .map((item) => String(item).trim())
      .filter(Boolean)
      .slice(0, 12);
  }

  if (typeof rawFoods === "string") {
    return rawFoods
      .split(/[、,，/|]/)
      .map((item) => item.trim())
      .filter(Boolean)
      .slice(0, 12);
  }

  return [];
}

function firstFiniteNumber(values: unknown[]): number | null {
  for (const value of values) {
    const num = Number(value);
    if (Number.isFinite(num) && num > 0) {
      return num;
    }
  }
  return null;
}

function extractCaloriesFromText(raw: string): number | null {
  const normalized = raw.replaceAll(/\s+/g, " ");
  const explicitMatches = normalized.matchAll(
    /(?:estimated[_\s-]*calories[_\s-]*kcal|total[_\s-]*calories|calories|kcal|千卡|大卡|热量)\D{0,8}(\d{2,4})/gi
  );

  for (const match of explicitMatches) {
    const value = Number(match[1]);
    if (Number.isFinite(value) && value > 0) {
      return value;
    }
  }

  const looseMatches = normalized.matchAll(/(\d{2,4})\s*(?:kcal|千卡|大卡|卡路里)/gi);
  for (const match of looseMatches) {
    const value = Number(match[1]);
    if (Number.isFinite(value) && value > 0) {
      return value;
    }
  }

  return null;
}

const foodCalorieHints: Array<{ keywords: string[]; kcal: number }> = [
  { keywords: ["米饭", "炒饭", "盖饭", "粥"], kcal: 260 },
  { keywords: ["面", "粉", "米线", "意面", "拉面"], kcal: 320 },
  { keywords: ["鸡胸", "鸡肉", "牛肉", "猪肉", "鱼", "虾"], kcal: 220 },
  { keywords: ["鸡蛋", "蛋"], kcal: 90 },
  { keywords: ["蔬菜", "沙拉", "西兰花", "青菜"], kcal: 70 },
  { keywords: ["酸奶", "牛奶"], kcal: 120 },
  { keywords: ["水果", "苹果", "香蕉", "橙", "蓝莓"], kcal: 110 },
  { keywords: ["面包", "蛋糕", "甜点", "饼干"], kcal: 240 },
  { keywords: ["奶茶", "可乐", "果汁", "饮料"], kcal: 180 },
  { keywords: ["火锅", "烧烤", "炸鸡", "披萨", "汉堡"], kcal: 520 }
];

function estimateCaloriesFromFoods(foods: string[]): number | null {
  if (foods.length === 0) {
    return null;
  }

  let total = 0;
  for (const food of foods) {
    const lowered = food.toLowerCase();
    const matched = foodCalorieHints.find((item) =>
      item.keywords.some((keyword) => lowered.includes(keyword.toLowerCase()))
    );
    total += matched?.kcal ?? 160;
  }

  const bounded = Math.min(Math.max(total, 120), 1800);
  return Math.round(bounded);
}

function parseVisionJson(raw: string): { foods: string[]; estimatedCaloriesKcal: number } | null {
  try {
    const cleaned = raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
    const jsonMatch = cleaned.match(/\{[\s\S]*\}/);
    const payload = JSON.parse(jsonMatch?.[0] ?? cleaned) as {
      foods?: unknown;
      estimated_calories_kcal?: unknown;
      estimatedCaloriesKcal?: unknown;
      total_calories_kcal?: unknown;
      totalCaloriesKcal?: unknown;
      calories?: unknown;
      calories_kcal?: unknown;
      kcal?: unknown;
    };
    const foods = normalizeFoods(payload.foods);
    const calories =
      firstFiniteNumber([
        payload.estimated_calories_kcal,
        payload.estimatedCaloriesKcal,
        payload.total_calories_kcal,
        payload.totalCaloriesKcal,
        payload.calories_kcal,
        payload.calories,
        payload.kcal
      ]) ??
      extractCaloriesFromText(cleaned) ??
      estimateCaloriesFromFoods(foods);

    if (!calories || !Number.isFinite(calories) || calories <= 0) {
      return null;
    }

    return {
      foods,
      estimatedCaloriesKcal: Number(calories.toFixed(0))
    };
  } catch {
    return null;
  }
}

function buildDietVisionPrompt(): string {
  return [
    "请识别这张饮食/进食图片中的主要食物，并估算整张图片对应的一次进食总热量。",
    "只返回 JSON，不要包含 markdown：",
    '{"foods":["食物1","食物2"],"estimated_calories_kcal":650}',
    "要求：",
    "1. estimated_calories_kcal 必须是数字。",
    "2. foods 返回 1-8 个简短中文食物名称。",
    "3. 如果无法可靠判断，请返回空 foods，并把 estimated_calories_kcal 设为 0。"
  ].join("\n");
}

async function callDietVision(filePath: string): Promise<DietVisionResult> {
  const result = await callVisionLLMWithFallbacks({
    filePath,
    prompt: buildDietVisionPrompt(),
    timeoutMs: 75_000
  });
  const parsed = parseVisionJson(result.text);

  if (!parsed || parsed.estimatedCaloriesKcal <= 0) {
    throw new Error("饮食图片识别失败：视觉模型没有返回可用的热量估算结果。");
  }

  return {
    ...parsed,
    provider: result.provider,
    model: result.model
  };
}

function existingAggregate(
  database: DatabaseSync,
  userId: string,
  metricCode: string,
  appDate: string
): number {
  const row = database
    .prepare(
      `
      SELECT normalized_value AS value
      FROM metric_record
      WHERE user_id = ? AND metric_code = ? AND sample_time LIKE ?
      ORDER BY sample_time DESC
      LIMIT 1
    `
    )
    .get(userId, metricCode, `${appDate}%`) as { value?: number } | undefined;

  return row?.value ?? 0;
}

function replaceDayAggregate(
  database: DatabaseSync,
  userId: string,
  metricCode: string,
  appDate: string
): void {
  database
    .prepare(
      `
      DELETE FROM metric_record
      WHERE user_id = ? AND metric_code = ? AND sample_time LIKE ?
    `
    )
    .run(userId, metricCode, `${appDate}%`);
}

export async function importDietData(
  database: DatabaseSync,
  request: DietImportRequest
): Promise<ImportExecutionResult> {
  if (!isImageFile(request.sourceFileName)) {
    throw new Error("饮食健康当前只支持图片上传（jpg/png/webp/heic）。");
  }

  const recognized = await callDietVision(request.filePath);
  const nowIso = formatAppDateTimeIso(new Date());
  const appDate = formatAppDate(nowIso);
  const caloriesMetric = importerSpecs.diet.fieldMappings[0];
  const countMetric = importerSpecs.diet.fieldMappings[1];

  ensureMetricDefinition(database, caloriesMetric, "image");
  ensureMetricDefinition(database, countMetric, "image");

  const previousCalories = existingAggregate(database, request.userId, caloriesMetric.metricCode, appDate);
  const previousCount = existingAggregate(database, request.userId, countMetric.metricCode, appDate);
  const nextCalories = previousCalories + recognized.estimatedCaloriesKcal;
  const nextCount = previousCount + 1;

  database.exec("BEGIN");

  try {
    replaceDayAggregate(database, request.userId, caloriesMetric.metricCode, appDate);
    replaceDayAggregate(database, request.userId, countMetric.metricCode, appDate);

    upsertMetricRecord(database, {
      userId: request.userId,
      dataSourceId: request.dataSourceId,
      importTaskId: request.importTaskId,
      metricCode: caloriesMetric.metricCode,
      metricName: caloriesMetric.metricName,
      category: caloriesMetric.category,
      rawValue: String(nextCalories),
      normalizedValue: nextCalories,
      unit: caloriesMetric.canonicalUnit,
      abnormalFlag: "unknown",
      sampleTime: `${appDate}T12:00:00+08:00`,
      sourceType: "diet_image",
      sourceFile: request.sourceFileName,
      notes: `vision_provider=${recognized.provider} | foods=${recognized.foods.join(",") || "unknown"}`
    });

    upsertMetricRecord(database, {
      userId: request.userId,
      dataSourceId: request.dataSourceId,
      importTaskId: request.importTaskId,
      metricCode: countMetric.metricCode,
      metricName: countMetric.metricName,
      category: countMetric.category,
      rawValue: String(nextCount),
      normalizedValue: nextCount,
      unit: countMetric.canonicalUnit,
      abnormalFlag: "normal",
      sampleTime: `${appDate}T12:01:00+08:00`,
      sourceType: "diet_image",
      sourceFile: request.sourceFileName,
      notes: `vision_provider=${recognized.provider} | foods=${recognized.foods.join(",") || "unknown"}`
    });

    insertImportRowLog(
      database,
      request.importTaskId,
      {
        rowNumber: 1,
        status: "imported",
        metricCode: caloriesMetric.metricCode,
        sourceField: "diet_image"
      },
      {
        foods: recognized.foods.join(","),
        estimated_calories_kcal: String(recognized.estimatedCaloriesKcal),
        aggregate_date: appDate
      }
    );

    insertImportRowLog(
      database,
      request.importTaskId,
      {
        rowNumber: 2,
        status: "imported",
        metricCode: countMetric.metricCode,
        sourceField: "diet_image"
      },
      {
        meal_upload_count: String(nextCount),
        aggregate_date: appDate
      }
    );

    database.exec("COMMIT");
  } catch (error) {
    database.exec("ROLLBACK");
    throw error;
  }

  finalizeImportTask(
    database,
    request.importTaskId,
    "completed",
    2,
    2,
    0,
    appendTaskNotes(
      request.taskNotes,
      `vision_provider=${recognized.provider} | vision_model=${recognized.model} | aggregate_date=${appDate} | recognized_foods=${recognized.foods.join(",") || "unknown"}`
    )
  );

  return {
    importTaskId: request.importTaskId,
    importerKey: "diet",
    filePath: request.filePath,
    taskStatus: "completed",
    totalRecords: 2,
    successRecords: 2,
    failedRecords: 0,
    logSummary: [],
    warnings: []
  };
}
