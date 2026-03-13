import type { DatabaseSync } from "node:sqlite";

import { NON_DIAGNOSTIC_DISCLAIMER } from "../../data/mock/seed-data";
import { getDatabase } from "../db/sqlite";
import type {
  DashboardData,
  DashboardMetricCard,
  KpiTone,
  TrendPoint
} from "../domain/types";
import { evaluateDashboardRules } from "../insights/rules";
import {
  getCoverageSummary,
  getLatestMetricsMap,
  getMergedSeries
} from "../repositories/health-repository";

function lastNumericValue(points: TrendPoint[], key: string): number | undefined {
  const point = [...points]
    .reverse()
    .find((item) => typeof item[key] === "number");

  return typeof point?.[key] === "number" ? (point[key] as number) : undefined;
}

function delta(points: TrendPoint[], key: string): number | undefined {
  const values = points
    .map((point) => point[key])
    .filter((value): value is number => typeof value === "number");

  if (values.length < 2) {
    return undefined;
  }

  return values.at(-1)! - values[0];
}

function averageLast(points: TrendPoint[], key: string, count: number): number | undefined {
  const values = points
    .map((point) => point[key])
    .filter((value): value is number => typeof value === "number")
    .slice(-count);

  if (values.length === 0) {
    return undefined;
  }

  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function signedDelta(value: number | undefined, unit: string): string {
  if (typeof value !== "number") {
    return "暂无对比";
  }

  const sign = value > 0 ? "+" : "";
  return `${sign}${value.toFixed(1)} ${unit}`;
}

function formatNumber(value: number | undefined, unit: string, digits = 1): string {
  if (typeof value !== "number") {
    return "--";
  }

  return `${value.toFixed(digits)} ${unit}`;
}

function formatHours(minutes: number | undefined): string {
  if (typeof minutes !== "number") {
    return "--";
  }

  const hours = Math.floor(minutes / 60);
  const remainingMinutes = Math.round(minutes % 60);
  return `${hours} 小时 ${remainingMinutes} 分钟`;
}

function toneFromDelta(
  deltaValue: number | undefined,
  preferredDirection: "up" | "down"
): KpiTone {
  if (typeof deltaValue !== "number" || deltaValue === 0) {
    return "neutral";
  }

  if (preferredDirection === "down") {
    return deltaValue < 0 ? "positive" : "attention";
  }

  return deltaValue > 0 ? "positive" : "attention";
}

function buildKpis(trends: DashboardData["trends"]): DashboardMetricCard[] {
  const weightDelta = delta(trends.bodyComposition, "weight");
  const bodyFatDelta = delta(trends.bodyComposition, "bodyFat");
  const ldlDelta = delta(trends.lipid, "ldl");
  const sleepAverage = averageLast(trends.sleep, "asleepMinutes", 7);
  const exerciseAverage = averageLast(trends.activity, "exerciseMinutes", 14);

  return [
    {
      id: "weight",
      label: "最新体重",
      value: formatNumber(lastNumericValue(trends.bodyComposition, "weight"), "kg"),
      detail: `相对首个体脂秤样本 ${signedDelta(weightDelta, "kg")}`,
      tone: toneFromDelta(weightDelta, "down")
    },
    {
      id: "body-fat",
      label: "最新体脂率",
      value: formatNumber(lastNumericValue(trends.bodyComposition, "bodyFat"), "%"),
      detail: `相对首个体脂秤样本 ${signedDelta(bodyFatDelta, "%")}`,
      tone: toneFromDelta(bodyFatDelta, "down")
    },
    {
      id: "ldl",
      label: "最近 LDL-C",
      value: formatNumber(lastNumericValue(trends.lipid, "ldl"), "mmol/L", 2),
      detail: `相对最早血脂样本 ${signedDelta(ldlDelta, "mmol/L")}`,
      tone: toneFromDelta(ldlDelta, "down")
    },
    {
      id: "sleep",
      label: "近 7 天平均睡眠",
      value: formatHours(sleepAverage),
      detail: `近 14 天平均训练 ${exerciseAverage?.toFixed(0) ?? "--"} 分钟`,
      tone: typeof sleepAverage === "number" && sleepAverage >= 420 ? "positive" : "attention"
    }
  ];
}

export function getDashboardData(database: DatabaseSync = getDatabase(), userId?: string): DashboardData {
  const trends = {
    bodyComposition: getMergedSeries(
      database,
      [
        { metricCode: "body.weight", alias: "weight" },
        { metricCode: "body.body_fat_pct", alias: "bodyFat" },
        { metricCode: "body.skeletal_muscle_pct", alias: "skeletalMuscle" }
      ],
      ["body_composition"],
      userId
    ),
    lipid: getMergedSeries(
      database,
      [
        { metricCode: "lipid.total_cholesterol", alias: "totalCholesterol" },
        { metricCode: "lipid.ldl_c", alias: "ldl" },
        { metricCode: "lipid.lpa", alias: "lpa" }
      ],
      ["annual_exam", "lipid_panel"],
      userId
    ),
    activity: getMergedSeries(
      database,
      [
        { metricCode: "activity.active_kcal", alias: "activeKcal" },
        { metricCode: "activity.exercise_minutes", alias: "exerciseMinutes" },
        { metricCode: "activity.stand_hours", alias: "standHours" }
      ],
      ["activity_daily"],
      userId
    ),
    sleep: getMergedSeries(
      database,
      [
        { metricCode: "sleep.in_bed_minutes", alias: "inBedMinutes" },
        { metricCode: "sleep.asleep_minutes", alias: "asleepMinutes" }
      ],
      ["sleep_daily"],
      userId
    )
  };

  const latestMetrics = getLatestMetricsMap(database, [
    "lipid.lpa",
    "lipid.ldl_c",
    "body.weight",
    "body.body_fat_pct",
    "sleep.asleep_minutes",
    "activity.exercise_minutes"
  ], userId);

  return {
    generatedAt: new Date().toISOString(),
    disclaimer: NON_DIAGNOSTIC_DISCLAIMER,
    kpis: buildKpis(trends),
    attentionItems: evaluateDashboardRules({
      latestMetrics,
      trends
    }),
    coverage: getCoverageSummary(database, userId),
    trends
  };
}
