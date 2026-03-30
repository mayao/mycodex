import type { DatabaseSync } from "node:sqlite";

import { NON_DIAGNOSTIC_DISCLAIMER } from "../../data/mock/seed-data";
import type {
  MetricSummary,
  StructuredInsight,
  StructuredInsightEvidenceMetric,
  StructuredInsightsResult,
  TrendDirection
} from "./types";

interface MetricHistoryRow {
  id: string;
  metric_code: string;
  metric_name: string;
  category: string;
  value: number;
  unit: string;
  abnormal_flag: string;
  sample_time: string;
  reference_range: string | null;
  better_direction: "up" | "down" | "neutral";
}

interface MetricHistoryPoint extends MetricHistoryRow {
  timestamp: number;
}

interface ReferenceBounds {
  low?: number;
  high?: number;
}

interface MetricSummaryInternal extends MetricSummary {
  better_direction: "up" | "down" | "neutral";
  related_record_ids: string[];
}

const thresholdOverrides: Record<string, number> = {
  "body.weight": 0.5,
  "body.body_fat_pct": 0.4,
  "body.skeletal_muscle_pct": 0.3,
  "lipid.total_cholesterol": 0.2,
  "lipid.triglycerides": 0.2,
  "lipid.ldl_c": 0.2,
  "lipid.hdl_c": 0.1,
  "glycemic.glucose": 0.2,
  "activity.exercise_minutes": 15,
  "activity.distance_km": 0.5,
  "activity.active_kcal": 60,
  "activity.steps": 1500,
  "diet.calories_intake_kcal": 120
};

const thresholdByUnit: Record<string, number> = {
  "%": 0.3,
  kg: 0.3,
  "mmol/L": 0.15,
  "mg/dL": 5,
  "g/L": 0.05,
  "umol/L": 5,
  min: 10,
  km: 0.5,
  kcal: 50,
  count: 1000,
  bpm: 5,
  level: 1
};

function average(values: number[]): number | undefined {
  if (values.length === 0) {
    return undefined;
  }

  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function round(value: number | undefined, digits = 3): number | undefined {
  return typeof value === "number" ? Number(value.toFixed(digits)) : undefined;
}

function getStableThreshold(metricCode: string, unit: string, latestValue: number): number {
  if (thresholdOverrides[metricCode]) {
    return thresholdOverrides[metricCode];
  }

  if (thresholdByUnit[unit]) {
    return thresholdByUnit[unit];
  }

  return Math.max(Math.abs(latestValue) * 0.03, 0.1);
}

function classifyTrendDirection(points: MetricHistoryPoint[]): TrendDirection | undefined {
  if (points.length < 2) {
    return undefined;
  }

  const latest = points.at(-1);
  const previous = points.at(-2);

  if (!latest || !previous) {
    return undefined;
  }

  const delta = latest.value - previous.value;
  const threshold = getStableThreshold(latest.metric_code, latest.unit, latest.value);

  if (Math.abs(delta) <= threshold) {
    return "stable";
  }

  return delta > 0 ? "up" : "down";
}

function findNearestPoint(
  points: MetricHistoryPoint[],
  targetTimestamp: number,
  toleranceDays: number
): MetricHistoryPoint | undefined {
  const toleranceMs = toleranceDays * 24 * 60 * 60 * 1000;
  let bestMatch: MetricHistoryPoint | undefined;
  let bestDistance = Number.POSITIVE_INFINITY;

  for (const point of points) {
    const distance = Math.abs(point.timestamp - targetTimestamp);

    if (distance <= toleranceMs && distance < bestDistance) {
      bestMatch = point;
      bestDistance = distance;
    }
  }

  return bestMatch;
}

function calculatePeriodDelta(points: MetricHistoryPoint[], days: number, toleranceDays: number) {
  const latest = points.at(-1);

  if (!latest) {
    return undefined;
  }

  const comparison = findNearestPoint(
    points.slice(0, -1),
    latest.timestamp - days * 24 * 60 * 60 * 1000,
    toleranceDays
  );

  if (!comparison) {
    return undefined;
  }

  return latest.value - comparison.value;
}

function parseReferenceRange(referenceRange: string | null | undefined): ReferenceBounds {
  if (!referenceRange) {
    return {};
  }

  const betweenMatch = referenceRange.match(/(-?\d+(?:\.\d+)?)\s*-\s*(-?\d+(?:\.\d+)?)/);

  if (betweenMatch) {
    return {
      low: Number(betweenMatch[1]),
      high: Number(betweenMatch[2])
    };
  }

  const lowerMatch = referenceRange.match(/>=\s*(-?\d+(?:\.\d+)?)/);

  if (lowerMatch) {
    return {
      low: Number(lowerMatch[1])
    };
  }

  const upperMatch = referenceRange.match(/<=\s*(-?\d+(?:\.\d+)?)/);

  if (upperMatch) {
    return {
      high: Number(upperMatch[1])
    };
  }

  return {};
}

function listConsecutiveAbnormalPoints(points: MetricHistoryPoint[]): MetricHistoryPoint[] {
  const abnormalPoints: MetricHistoryPoint[] = [];
  const latest = points.at(-1);

  if (!latest || !["high", "low"].includes(latest.abnormal_flag)) {
    return abnormalPoints;
  }

  for (let index = points.length - 1; index >= 0; index -= 1) {
    const point = points[index];

    if (point.abnormal_flag !== latest.abnormal_flag) {
      break;
    }

    abnormalPoints.unshift(point);
  }

  return abnormalPoints;
}

function buildEvidenceMetric(
  summary: MetricSummaryInternal,
  relatedRecordIds?: string[]
): StructuredInsightEvidenceMetric {
  return {
    metric_code: summary.metric_code,
    metric_name: summary.metric_name,
    unit: summary.unit,
    latest_value: summary.latest_value,
    latest_sample_time: summary.latest_sample_time,
    sample_count: summary.sample_count,
    historical_mean: summary.historical_mean,
    latest_vs_mean: summary.latest_vs_mean,
    latest_vs_mean_pct: summary.latest_vs_mean_pct,
    trend_direction: summary.trend_direction,
    month_over_month: summary.month_over_month,
    year_over_year: summary.year_over_year,
    abnormal_flag: summary.abnormal_flag,
    reference_range: summary.reference_range,
    related_record_ids: relatedRecordIds ?? summary.related_record_ids
  };
}

function loadMetricHistories(
  database: DatabaseSync,
  userId: string,
  asOf?: string
): Record<string, MetricHistoryPoint[]> {
  const rows = asOf
    ? (database
        .prepare(
          `
          SELECT
            mr.id,
            mr.metric_code,
            mr.metric_name,
            mr.category,
            mr.normalized_value AS value,
            mr.unit,
            mr.abnormal_flag,
            mr.sample_time,
            mr.reference_range,
            COALESCE(md.better_direction, 'neutral') AS better_direction
          FROM metric_record mr
          LEFT JOIN metric_definition md ON md.metric_code = mr.metric_code
          WHERE mr.user_id = ? AND mr.sample_time <= ?
          ORDER BY mr.metric_code ASC, mr.sample_time ASC
        `
        )
        .all(userId, asOf) as unknown as MetricHistoryRow[])
    : (database
        .prepare(
          `
          SELECT
            mr.id,
            mr.metric_code,
            mr.metric_name,
            mr.category,
            mr.normalized_value AS value,
            mr.unit,
            mr.abnormal_flag,
            mr.sample_time,
            mr.reference_range,
            COALESCE(md.better_direction, 'neutral') AS better_direction
          FROM metric_record mr
          LEFT JOIN metric_definition md ON md.metric_code = mr.metric_code
          WHERE mr.user_id = ?
          ORDER BY mr.metric_code ASC, mr.sample_time ASC
        `
        )
        .all(userId) as unknown as MetricHistoryRow[]);

  const grouped: Record<string, MetricHistoryPoint[]> = {};

  for (const row of rows) {
    const timestamp = new Date(row.sample_time).getTime();

    if (!Number.isFinite(timestamp)) {
      continue;
    }

    grouped[row.metric_code] ??= [];
    grouped[row.metric_code].push({
      ...row,
      timestamp
    });
  }

  return grouped;
}

function buildMetricSummary(points: MetricHistoryPoint[]): MetricSummaryInternal | undefined {
  const latest = points.at(-1);

  if (!latest) {
    return undefined;
  }

  const previousValues = points.slice(0, -1).map((point) => point.value);
  const historicalMean = average(previousValues.length > 0 ? previousValues : points.map((point) => point.value));
  const latestVsMean =
    typeof historicalMean === "number" ? latest.value - historicalMean : undefined;
  const latestVsMeanPct =
    typeof historicalMean === "number" && historicalMean !== 0
      ? (latestVsMean! / historicalMean) * 100
      : undefined;

  return {
    metric_code: latest.metric_code,
    metric_name: latest.metric_name,
    category: latest.category,
    unit: latest.unit,
    sample_count: points.length,
    latest_value: round(latest.value) ?? latest.value,
    latest_sample_time: latest.sample_time,
    historical_mean: round(historicalMean),
    latest_vs_mean: round(latestVsMean),
    latest_vs_mean_pct: round(latestVsMeanPct),
    trend_direction: classifyTrendDirection(points),
    month_over_month: round(calculatePeriodDelta(points, 30, 20)),
    year_over_year: round(calculatePeriodDelta(points, 365, 90)),
    abnormal_flag: latest.abnormal_flag,
    reference_range: latest.reference_range,
    better_direction: latest.better_direction,
    related_record_ids: points.slice(-3).map((point) => point.id)
  };
}

function pushInsight(target: StructuredInsight[], insight: StructuredInsight): void {
  if (target.some((item) => item.id === insight.id)) {
    return;
  }

  target.push(insight);
}

function buildOutOfRangeInsights(
  summaries: Record<string, MetricSummaryInternal>,
  insights: StructuredInsight[]
): void {
  for (const summary of Object.values(summaries)) {
    if (!["high", "low"].includes(summary.abnormal_flag)) {
      continue;
    }

    const bounds = parseReferenceRange(summary.reference_range);
    let severity: StructuredInsight["severity"] = "medium";

    if (
      summary.abnormal_flag === "high" &&
      typeof bounds.high === "number" &&
      summary.latest_value >= bounds.high * 1.1
    ) {
      severity = "high";
    }

    if (
      summary.abnormal_flag === "low" &&
      typeof bounds.low === "number" &&
      summary.latest_value <= bounds.low * 0.9
    ) {
      severity = "high";
    }

    pushInsight(insights, {
      id: `anomaly-range-${summary.metric_code}`,
      kind: "anomaly",
      title: `${summary.metric_name} 最近一次${summary.abnormal_flag === "high" ? "高于" : "低于"}参考范围`,
      severity,
      evidence: {
        summary: `${summary.metric_name} 最新值为 ${summary.latest_value} ${summary.unit}，参考范围为 ${summary.reference_range ?? "未提供"}。`,
        metrics: [buildEvidenceMetric(summary)]
      },
      possible_reason: "近期饮食、运动、恢复状态或检验波动都可能影响该指标，需要结合连续记录判断。",
      suggested_action: "保留当前记录频率，并把体重、体脂和运动变化与下次复查结果一起对照。",
      disclaimer: NON_DIAGNOSTIC_DISCLAIMER
    });
  }
}

function buildConsecutiveAbnormalInsights(
  histories: Record<string, MetricHistoryPoint[]>,
  summaries: Record<string, MetricSummaryInternal>,
  insights: StructuredInsight[]
): void {
  for (const [metricCode, points] of Object.entries(histories)) {
    const abnormalPoints = listConsecutiveAbnormalPoints(points);

    if (abnormalPoints.length < 2) {
      continue;
    }

    const summary = summaries[metricCode];

    if (!summary) {
      continue;
    }

    pushInsight(insights, {
      id: `anomaly-consecutive-${metricCode}`,
      kind: "anomaly",
      title: `${summary.metric_name} 连续 ${abnormalPoints.length} 次${summary.abnormal_flag === "high" ? "偏高" : "偏低"}`,
      severity: abnormalPoints.length >= 3 ? "high" : "medium",
      evidence: {
        summary: `最近 ${abnormalPoints.length} 次记录均为 ${summary.abnormal_flag}，最近一次时间为 ${summary.latest_sample_time}。`,
        metrics: [buildEvidenceMetric(summary, abnormalPoints.map((point) => point.id))]
      },
      possible_reason: "这类连续异常更像持续状态，而不是单次波动，需要结合生活方式和复查频率一起看。",
      suggested_action: "将该指标列为下一次复查重点，并回看同一时间段的饮食、训练和体重变化。",
      disclaimer: NON_DIAGNOSTIC_DISCLAIMER
    });
  }
}

function buildThresholdWarningInsights(
  summaries: Record<string, MetricSummaryInternal>,
  insights: StructuredInsight[]
): void {
  for (const summary of Object.values(summaries)) {
    if (summary.abnormal_flag !== "normal") {
      continue;
    }

    const bounds = parseReferenceRange(summary.reference_range);
    const nearUpper =
      typeof bounds.high === "number" &&
      summary.latest_value < bounds.high &&
      summary.latest_value >= bounds.high * 0.95;
    const nearLower =
      typeof bounds.low === "number" &&
      summary.latest_value > bounds.low &&
      summary.latest_value <= bounds.low * 1.05;

    if (!nearUpper && !nearLower) {
      continue;
    }

    pushInsight(insights, {
      id: `anomaly-threshold-${summary.metric_code}`,
      kind: "anomaly",
      title: `${summary.metric_name} 接近参考范围${nearUpper ? "上限" : "下限"}`,
      severity: "low",
      evidence: {
        summary: `${summary.metric_name} 当前仍在范围内，但已接近 ${nearUpper ? "上限" : "下限"} ${summary.reference_range ?? ""}。`,
        metrics: [buildEvidenceMetric(summary)]
      },
      possible_reason: "指标仍在正常范围内，但距离阈值已经较近，轻微波动就可能越界。",
      suggested_action: "提前观察未来 2-4 周的趋势，必要时安排更早的复查，而不是等到明显异常后再处理。",
      disclaimer: NON_DIAGNOSTIC_DISCLAIMER
    });
  }
}

function buildTrendInsights(
  summaries: Record<string, MetricSummaryInternal>,
  insights: StructuredInsight[]
): void {
  const interestingMetrics = [
    "body.weight",
    "body.body_fat_pct",
    "lipid.ldl_c",
    "lipid.triglycerides",
    "activity.exercise_minutes",
    "diet.calories_intake_kcal"
  ];

  for (const metricCode of interestingMetrics) {
    const summary = summaries[metricCode];

    if (!summary || summary.sample_count < 2 || !summary.trend_direction || summary.trend_direction === "stable") {
      continue;
    }

    const threshold = getStableThreshold(metricCode, summary.unit, summary.latest_value);
    const notableChange = Math.abs(summary.latest_vs_mean ?? 0) >= threshold;

    if (!notableChange) {
      continue;
    }

    const favorable =
      (summary.better_direction === "down" && summary.trend_direction === "down") ||
      (summary.better_direction === "up" && summary.trend_direction === "up");

    pushInsight(insights, {
      id: `trend-${metricCode}`,
      kind: "trend",
      title: `${summary.metric_name} 呈${summary.trend_direction === "up" ? "上升" : "下降"}趋势`,
      severity: favorable ? "positive" : summary.abnormal_flag === "normal" ? "low" : "medium",
      evidence: {
        summary: `${summary.metric_name} 最新值 ${summary.latest_value} ${summary.unit}，相对历史均值变化 ${summary.latest_vs_mean ?? 0} ${summary.unit}，环比 ${summary.month_over_month ?? 0} ${summary.unit}。`,
        metrics: [buildEvidenceMetric(summary)]
      },
      possible_reason: favorable
        ? "近期生活方式调整和记录执行度可能与该指标改善方向一致。"
        : "近期饮食、活动、恢复或检测时点变化都可能推动该指标朝不利方向移动。",
      suggested_action: favorable
        ? "继续保持当前记录频率，确认这个趋势能否在后续 1-2 个周期持续。"
        : "把该指标放入下一轮复查和行为记录的重点观察列表，确认变化是否持续。",
      disclaimer: NON_DIAGNOSTIC_DISCLAIMER
    });
  }
}

function averageInWindow(points: MetricHistoryPoint[], endTimestamp: number, days: number): number | undefined {
  const startTimestamp = endTimestamp - days * 24 * 60 * 60 * 1000;
  const values = points
    .filter((point) => point.timestamp > startTimestamp && point.timestamp <= endTimestamp)
    .map((point) => point.value);

  return average(values);
}

function countExerciseDays(points: MetricHistoryPoint[], endTimestamp: number, days: number): number {
  const startTimestamp = endTimestamp - days * 24 * 60 * 60 * 1000;

  return points.filter(
    (point) => point.timestamp > startTimestamp && point.timestamp <= endTimestamp && point.value >= 20
  ).length;
}

function buildCorrelationInsights(
  histories: Record<string, MetricHistoryPoint[]>,
  summaries: Record<string, MetricSummaryInternal>,
  insights: StructuredInsight[]
): void {
  const bodyFatPoints = histories["body.body_fat_pct"] ?? [];
  const exercisePoints = histories["activity.exercise_minutes"] ?? [];
  const weightPoints = histories["body.weight"] ?? [];
  const dietPoints = histories["diet.calories_intake_kcal"] ?? [];
  const mealUploadPoints = histories["diet.meal_upload_count"] ?? [];

  const bodyFatSummary = summaries["body.body_fat_pct"];
  const exerciseSummary = summaries["activity.exercise_minutes"];
  const weightSummary = summaries["body.weight"];
  const ldlSummary = summaries["lipid.ldl_c"];
  const tgSummary = summaries["lipid.triglycerides"];
  const dietSummary = summaries["diet.calories_intake_kcal"];
  const mealUploadSummary = summaries["diet.meal_upload_count"];

  if (bodyFatPoints.length >= 2 && exercisePoints.length >= 3 && bodyFatSummary && exerciseSummary) {
    const latestBodyFat = bodyFatPoints.at(-1)!;
    const previousBodyFat = bodyFatPoints.at(-2)!;
    const recentExerciseAverage = averageInWindow(exercisePoints, latestBodyFat.timestamp, 14);
    const previousExerciseAverage = averageInWindow(
      exercisePoints,
      latestBodyFat.timestamp - 14 * 24 * 60 * 60 * 1000,
      14
    );

    if (
      typeof recentExerciseAverage === "number" &&
      typeof previousExerciseAverage === "number"
    ) {
      const bodyFatDelta = latestBodyFat.value - previousBodyFat.value;
      const exerciseDelta = recentExerciseAverage - previousExerciseAverage;

      if (bodyFatDelta <= -0.4 && exerciseDelta >= 10) {
        pushInsight(insights, {
          id: "correlation-body-fat-vs-activity-positive",
          kind: "correlation",
          title: "体脂变化与运动量变化方向一致",
          severity: "positive",
          evidence: {
            summary: `体脂率较上次下降 ${round(Math.abs(bodyFatDelta), 2)}%，近 14 天平均训练时长较前一窗口增加 ${round(exerciseDelta, 1)} 分钟。`,
            metrics: [buildEvidenceMetric(bodyFatSummary), buildEvidenceMetric(exerciseSummary)]
          },
          possible_reason: "训练量提升与体脂下降同步出现，说明当前运动安排可能在发挥作用。",
          suggested_action: "继续按周记录训练量与体脂率，确认这种联动是否稳定持续。",
          disclaimer: NON_DIAGNOSTIC_DISCLAIMER
        });
      }

      if (bodyFatDelta >= 0.4 && exerciseDelta <= -10) {
        pushInsight(insights, {
          id: "correlation-body-fat-vs-activity-watch",
          kind: "correlation",
          title: "体脂上升与运动量下降同步出现",
          severity: "medium",
          evidence: {
            summary: `体脂率较上次上升 ${round(bodyFatDelta, 2)}%，近 14 天平均训练时长较前一窗口下降 ${round(Math.abs(exerciseDelta), 1)} 分钟。`,
            metrics: [buildEvidenceMetric(bodyFatSummary), buildEvidenceMetric(exerciseSummary)]
          },
          possible_reason: "近期运动量下降可能削弱了体脂管理效果，也可能叠加饮食和恢复因素。",
          suggested_action: "优先恢复训练频率，并结合体重和睡眠记录确认体脂变化是否延续。",
          disclaimer: NON_DIAGNOSTIC_DISCLAIMER
        });
      }
    }
  }

  if (bodyFatPoints.length >= 2 && bodyFatSummary && (ldlSummary || tgSummary)) {
    const bodyFatDelta = bodyFatPoints.at(-1)!.value - bodyFatPoints.at(-2)!.value;
    const lipidMetrics = [ldlSummary, tgSummary].filter(
      (summary): summary is MetricSummaryInternal =>
        Boolean(summary && typeof summary.month_over_month === "number")
    );

    if (lipidMetrics.length > 0) {
      const worseningLipids = lipidMetrics.filter((summary) => (summary.month_over_month ?? 0) > 0.15);
      const improvingLipids = lipidMetrics.filter((summary) => (summary.month_over_month ?? 0) < -0.15);

      if (bodyFatDelta <= -0.4 && worseningLipids.length > 0) {
        pushInsight(insights, {
          id: "correlation-body-fat-vs-lipid-divergence",
          kind: "correlation",
          title: "体脂下降，但 LDL/TG 未同步改善",
          severity: "medium",
          evidence: {
            summary: `体脂率较上次下降 ${round(Math.abs(bodyFatDelta), 2)}%，但 ${worseningLipids.map((item) => item.metric_name).join("、")} 环比仍在上升。`,
            metrics: [buildEvidenceMetric(bodyFatSummary), ...lipidMetrics.map((summary) => buildEvidenceMetric(summary))]
          },
          possible_reason: "体脂变化与血脂变化的节奏不一定同步，近期饮食结构或复查时点差异也可能影响结果。",
          suggested_action: "继续联动观察体脂率、LDL-C 和 TG，至少再看 1-2 次复查，不要只看单次好坏。",
          disclaimer: NON_DIAGNOSTIC_DISCLAIMER
        });
      }

      if (bodyFatDelta <= -0.4 && improvingLipids.length > 0 && worseningLipids.length === 0) {
        pushInsight(insights, {
          id: "correlation-body-fat-vs-lipid-positive",
          kind: "correlation",
          title: "体脂下降与 LDL/TG 改善同步出现",
          severity: "positive",
          evidence: {
            summary: `体脂率较上次下降 ${round(Math.abs(bodyFatDelta), 2)}%，且 ${improvingLipids.map((item) => item.metric_name).join("、")} 环比下降。`,
            metrics: [buildEvidenceMetric(bodyFatSummary), ...lipidMetrics.map((summary) => buildEvidenceMetric(summary))]
          },
          possible_reason: "近期身体组成改善与血脂改善方向一致，说明当前管理动作可能形成联动。",
          suggested_action: "保持相同记录方式，确认这种联动能否在下一次血脂复查中继续出现。",
          disclaimer: NON_DIAGNOSTIC_DISCLAIMER
        });
      }
    }
  }

  if (exercisePoints.length >= 4 && weightPoints.length >= 2 && exerciseSummary && weightSummary) {
    const anchorTimestamp = Math.max(
      exercisePoints.at(-1)?.timestamp ?? 0,
      weightPoints.at(-1)?.timestamp ?? 0
    );
    const recentExerciseDays = countExerciseDays(exercisePoints, anchorTimestamp, 14);
    const previousExerciseDays = countExerciseDays(
      exercisePoints,
      anchorTimestamp - 14 * 24 * 60 * 60 * 1000,
      14
    );
    const weightDelta = weightPoints.at(-1)!.value - weightPoints.at(-2)!.value;
    const frequencyDelta = recentExerciseDays - previousExerciseDays;

    if (frequencyDelta >= 2 && weightDelta <= -0.5) {
      pushInsight(insights, {
        id: "correlation-exercise-frequency-vs-weight-positive",
        kind: "correlation",
        title: "运动频率增加且体重下降",
        severity: "positive",
        evidence: {
          summary: `近 14 天训练天数比前一窗口多 ${frequencyDelta} 天，同时体重较上次下降 ${round(Math.abs(weightDelta), 2)} kg。`,
          metrics: [buildEvidenceMetric(exerciseSummary), buildEvidenceMetric(weightSummary)]
        },
        possible_reason: "训练频率提升与体重下降方向一致，当前节奏可能具备可持续性。",
        suggested_action: "继续按 2 周窗口追踪训练频率和体重，确认下降是否稳定而不过快。",
        disclaimer: NON_DIAGNOSTIC_DISCLAIMER
      });
    }

    if (frequencyDelta <= -2 && weightDelta >= 0.5) {
      pushInsight(insights, {
        id: "correlation-exercise-frequency-vs-weight-watch",
        kind: "correlation",
        title: "运动频率下降且体重回升",
        severity: "medium",
        evidence: {
          summary: `近 14 天训练天数比前一窗口少 ${Math.abs(frequencyDelta)} 天，同时体重较上次上升 ${round(weightDelta, 2)} kg。`,
          metrics: [buildEvidenceMetric(exerciseSummary), buildEvidenceMetric(weightSummary)]
        },
        possible_reason: "训练频率下降和体重回升同步出现，可能说明当前活动量难以覆盖近期摄入或恢复状态变化。",
        suggested_action: "优先恢复稳定训练频率，并结合体脂率一起确认体重回升来自脂肪还是短期波动。",
        disclaimer: NON_DIAGNOSTIC_DISCLAIMER
      });
    }
  }

  if (dietPoints.length >= 3 && dietSummary) {
    const latestDiet = dietPoints.at(-1)!;
    const recentDietAverage = averageInWindow(dietPoints, latestDiet.timestamp, 7);
    const previousDietAverage = averageInWindow(
      dietPoints,
      latestDiet.timestamp - 7 * 24 * 60 * 60 * 1000,
      7
    );

    if (
      typeof recentDietAverage === "number" &&
      typeof previousDietAverage === "number" &&
      weightPoints.length >= 2 &&
      weightSummary
    ) {
      const dietDelta = recentDietAverage - previousDietAverage;
      const weightDelta = weightPoints.at(-1)!.value - weightPoints.at(-2)!.value;

      if (dietDelta >= 150 && weightDelta >= 0.4) {
        pushInsight(insights, {
          id: "correlation-diet-up-weight-up",
          kind: "correlation",
          title: "近期热量上行且体重同步上行",
          severity: "medium",
          evidence: {
            summary: `近 7 天平均热量较前一窗口上升 ${round(dietDelta, 0)} kcal，同时体重较上次增加 ${round(weightDelta, 2)} kg。`,
            metrics: [buildEvidenceMetric(dietSummary), buildEvidenceMetric(weightSummary)]
          },
          possible_reason: "近期摄入增加与体重回升同步出现，说明这更像连续趋势而不是单日波动。",
          suggested_action: "优先确认饮食记录连续性，并把未来 1-2 周的热量趋势与体重变化放在一起看。",
          disclaimer: NON_DIAGNOSTIC_DISCLAIMER
        });
      }

      if (dietDelta <= -150 && weightDelta <= -0.4) {
        pushInsight(insights, {
          id: "correlation-diet-down-weight-down",
          kind: "correlation",
          title: "热量回落并伴随体重改善",
          severity: "positive",
          evidence: {
            summary: `近 7 天平均热量较前一窗口下降 ${round(Math.abs(dietDelta), 0)} kcal，同时体重较上次下降 ${round(Math.abs(weightDelta), 2)} kg。`,
            metrics: [buildEvidenceMetric(dietSummary), buildEvidenceMetric(weightSummary)]
          },
          possible_reason: "饮食侧与体重变化方向一致，当前记录已能支撑趋势反馈。",
          suggested_action: "继续保持当前记录方式，确认这种联动是否能稳定持续，而不是只看单周变化。",
          disclaimer: NON_DIAGNOSTIC_DISCLAIMER
        });
      }
    }
  }

  if (mealUploadPoints.length > 0 && mealUploadSummary) {
    const recentCoverage = averageInWindow(mealUploadPoints, mealUploadPoints.at(-1)!.timestamp, 7);

    if (typeof recentCoverage === "number" && recentCoverage < 1) {
      pushInsight(insights, {
        id: "correlation-diet-coverage-low",
        kind: "correlation",
        title: "热量记录覆盖不足",
        severity: "low",
        evidence: {
          summary: `近 7 天日均饮食记录次数约为 ${round(recentCoverage, 1)}，当前连续性不足以支持稳定趋势判断。`,
          metrics: [buildEvidenceMetric(mealUploadSummary)]
        },
        possible_reason: "饮食记录天数偏少时，热量趋势更容易受到单次上传影响。",
        suggested_action: "先连续上传 3-7 天饮食照片，把记录覆盖率建立起来，再解读热量变化。",
        disclaimer: NON_DIAGNOSTIC_DISCLAIMER
      });
    }
  }
}

export function generateStructuredInsights(
  database: DatabaseSync,
  userId: string = "user-self",
  options?: { asOf?: string }
): StructuredInsightsResult {
  const histories = loadMetricHistories(database, userId, options?.asOf);
  const summaries = Object.fromEntries(
    Object.entries(histories)
      .map(([metricCode, points]) => [metricCode, buildMetricSummary(points)] as const)
      .filter((entry): entry is [string, MetricSummaryInternal] => Boolean(entry[1]))
  );
  const insights: StructuredInsight[] = [];

  buildOutOfRangeInsights(summaries, insights);
  buildConsecutiveAbnormalInsights(histories, summaries, insights);
  buildThresholdWarningInsights(summaries, insights);
  buildTrendInsights(summaries, insights);
  buildCorrelationInsights(histories, summaries, insights);

  return {
    generated_at: new Date().toISOString(),
    user_id: userId,
    metric_summaries: Object.values(summaries).sort((left, right) =>
      left.metric_code.localeCompare(right.metric_code)
    ),
    insights
  };
}
