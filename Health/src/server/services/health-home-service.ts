import type { DatabaseSync } from "node:sqlite";

import { NON_DIAGNOSTIC_DISCLAIMER } from "../../data/mock/seed-data";
import type {
  AnnualExamView,
  GeneticFindingView,
  HealthHomePageData,
  HealthOverviewCard,
  HealthOverviewSpotlight,
  HealthReminderItem,
  HealthSourceDimensionCard
} from "../domain/health-hub";
import { getDatabase } from "../db/sqlite";
import {
  getAnnualExamDigest,
  listGeneticFindingDigests
} from "../repositories/document-insight-repository";
import { getCoverageSummary } from "../repositories/health-repository";
import { getLatestSampleTime, getUnifiedTrendSeries } from "../repositories/unified-health-repository";
import { resolveAnalysisAsOf } from "../utils/app-time";
import {
  getAnnualExamEducationalCopy,
  getGeneticEducationalCopy,
  getInsightEducationalCopy,
  getMetricEducationalCopy
} from "./health-communication";
import { generateHolisticStructuredInsights } from "./holistic-insight-service";
import { getCurrentDailySummary, getReportsIndexData } from "./report-service";

const overviewMetricCodes = [
  "lipid.ldl_c",
  "lipid.lpa",
  "lipid.triglycerides",
  "lipid.hdl_c",
  "lipid.total_cholesterol",
  "lipid.apob",
  "body.weight",
  "body.body_fat_pct",
  "body.bmi",
  "glycemic.glucose",
  "renal.creatinine",
  "activity.exercise_minutes"
];

const preferredDirection: Record<string, "up" | "down" | "neutral"> = {
  "lipid.ldl_c": "down",
  "lipid.lpa": "down",
  "lipid.triglycerides": "down",
  "lipid.hdl_c": "up",
  "lipid.total_cholesterol": "down",
  "lipid.apob": "down",
  "body.weight": "down",
  "body.body_fat_pct": "down",
  "body.bmi": "down",
  "glycemic.glucose": "down",
  "renal.creatinine": "down",
  "activity.exercise_minutes": "up"
};

function formatValue(value: number, unit: string): string {
  const digits = ["mmol/L", "g/L", "%"].includes(unit) ? 2 : unit === "kg" ? 1 : 0;
  return `${value.toFixed(digits)} ${unit}`;
}

function formatCompactValue(value: number, unit: string): string {
  const digits = unit === "kg" ? 1 : ["mmol/L", "g/L", "%"].includes(unit) ? 2 : 0;
  return `${value.toFixed(digits)}${unit}`;
}

function signed(value: number | undefined, unit: string): string {
  if (typeof value !== "number") {
    return "暂无对比";
  }

  const sign = value > 0 ? "+" : "";
  const digits = ["mmol/L", "g/L", "%"].includes(unit) ? 2 : unit === "kg" ? 1 : 0;
  return `${sign}${value.toFixed(digits)} ${unit}`;
}

function buildOverviewCard(summary: {
  metric_code: string;
  metric_name: string;
  latest_value: number;
  unit: string;
  latest_vs_mean?: number;
  trend_direction?: string;
  month_over_month?: number;
  abnormal_flag: string;
}): HealthOverviewCard {
  const direction = preferredDirection[summary.metric_code] ?? "neutral";
  const favorable =
    (direction === "down" && summary.trend_direction === "down") ||
    (direction === "up" && summary.trend_direction === "up");
  const status =
    summary.abnormal_flag === "high" || summary.abnormal_flag === "low"
      ? "watch"
      : favorable
        ? "improving"
        : "stable";
  const trend =
    summary.trend_direction && summary.trend_direction !== "stable"
      ? `近阶段${summary.trend_direction === "up" ? "上升" : "下降"}，较历史均值 ${signed(summary.latest_vs_mean, summary.unit)}`
      : `较历史均值 ${signed(summary.latest_vs_mean, summary.unit)}，环比 ${signed(summary.month_over_month, summary.unit)}`;

  return {
    metric_code: summary.metric_code,
    label: summary.metric_name,
    value: formatValue(summary.latest_value, summary.unit),
    trend,
    status,
    abnormal_flag: summary.abnormal_flag,
    meaning: getMetricEducationalCopy(summary.metric_code)?.meaning
  };
}

function reminderWeight(severity: HealthReminderItem["severity"]): number {
  if (severity === "high") {
    return 4;
  }

  if (severity === "medium") {
    return 3;
  }

  if (severity === "low") {
    return 2;
  }

  return 1;
}

function buildReminderItem(insight: {
  id: string;
  title: string;
  severity: HealthReminderItem["severity"];
  evidence: {
    summary: string;
    metrics?: Array<{ metric_code?: string }>;
  };
  suggested_action: string;
}): HealthReminderItem {
  const primaryMetricCode = insight.evidence.metrics?.[0]?.metric_code;
  const educationalCopy = getInsightEducationalCopy({
    id: insight.id,
    title: insight.title,
    metricCode: primaryMetricCode
  });

  return {
    id: insight.id,
    title: insight.title,
    severity: insight.severity,
    summary: insight.evidence.summary,
    suggested_action: insight.suggested_action,
    indicatorMeaning: educationalCopy?.meaning,
    practicalAdvice: educationalCopy?.practicalAdvice
  };
}

function summarizeGeneticFindings(geneticFindings: GeneticFindingView[]) {
  const dimensions = [...new Set(geneticFindings.map((item) => item.dimension))];
  const topTraits = geneticFindings.slice(0, 3).map((item) => item.traitLabel);
  const highRiskTraits = geneticFindings
    .filter((item) => item.riskLevel === "high")
    .map((item) => item.traitLabel);

  return {
    count: geneticFindings.length,
    dimensionCount: dimensions.length,
    dimensions,
    topTraits,
    highRiskTraits
  };
}

function buildSourceDimensions(
  annualExam: AnnualExamView | undefined,
  geneticFindings: GeneticFindingView[],
  metricSummaries: Array<{
    metric_code: string;
    metric_name: string;
    latest_value: number;
    unit: string;
    abnormal_flag: string;
    latest_sample_time: string;
  }>
): HealthSourceDimensionCard[] {
  const ldl = metricSummaries.find((item) => item.metric_code === "lipid.ldl_c");
  const bodyFat = metricSummaries.find((item) => item.metric_code === "body.body_fat_pct");
  const exercise = metricSummaries.find((item) => item.metric_code === "activity.exercise_minutes");
  const geneSummary = summarizeGeneticFindings(geneticFindings);

  return [
    {
      key: "annual_exam",
      label: "年度体检",
      latestAt: annualExam?.latestRecordedAt,
      status: annualExam && annualExam.abnormalMetricLabels.length > 0 ? "attention" : "ready",
      summary: annualExam?.highlightSummary ?? "尚未接入年度体检摘要。",
      highlight:
        annualExam?.abnormalMetricLabels.length
          ? annualExam.abnormalMetricLabels.join("、")
          : "年度基线"
    },
    {
      key: "lipid",
      label: "近期血液专项",
      latestAt: ldl?.latest_sample_time,
      status: ldl?.abnormal_flag === "high" || ldl?.abnormal_flag === "low" ? "attention" : "ready",
      summary:
        ldl != null
          ? `最新 LDL-C 为 ${formatCompactValue(ldl.latest_value, ldl.unit)}，与年度体检基线相比更适合放在近期干预成效中观察。`
          : "暂无专项血液复查数据。",
      highlight: ldl != null ? `${ldl.metric_name} ${formatCompactValue(ldl.latest_value, ldl.unit)}` : "近期复查"
    },
    {
      key: "body",
      label: "体脂秤趋势",
      latestAt: bodyFat?.latest_sample_time,
      status:
        bodyFat?.abnormal_flag === "high" || bodyFat?.abnormal_flag === "low" ? "attention" : "ready",
      summary:
        bodyFat != null
          ? `最新体脂率为 ${formatCompactValue(bodyFat.latest_value, bodyFat.unit)}，适合作为解释年度体检与专项血脂变化的过程信号。`
          : "暂无体脂秤趋势数据。",
      highlight:
        bodyFat != null
          ? `${bodyFat.metric_name} ${formatCompactValue(bodyFat.latest_value, bodyFat.unit)}`
          : "体脂变化"
    },
    {
      key: "activity",
      label: "运动执行度",
      latestAt: exercise?.latest_sample_time,
      status: "ready",
      summary:
        exercise != null
          ? `最新训练分钟为 ${formatCompactValue(exercise.latest_value, exercise.unit)}，可用于解释体脂和代谢指标的近期联动。`
          : "暂无运动执行度数据。",
      highlight:
        exercise != null
          ? `${exercise.metric_name} ${formatCompactValue(exercise.latest_value, exercise.unit)}`
          : "训练节奏"
    },
    {
      key: "genetic",
      label: "基因背景",
      latestAt: geneticFindings[0]?.recordedAt,
      status: geneticFindings.some((item) => item.riskLevel === "high") ? "attention" : "background",
      summary:
        geneSummary.count > 0
          ? `已纳入 ${geneSummary.count} 条基因背景，覆盖 ${geneSummary.dimensionCount} 个长期解释维度。`
          : "暂无基因背景信息。",
      highlight:
        geneSummary.count > 0
          ? `${geneSummary.dimensionCount} 个维度 / ${geneSummary.count} 条背景`
          : "遗传背景"
    }
  ];
}

function buildOverviewHeadline(
  annualExam: AnnualExamView | undefined,
  geneticFindings: GeneticFindingView[],
  metricSummaries: Array<{
    metric_code: string;
    latest_value: number;
    unit: string;
  }>
): string {
  const ldl = metricSummaries.find((item) => item.metric_code === "lipid.ldl_c");
  const annualLdl = annualExam?.metrics.find((item) => item.metricCode === "lipid.ldl_c");
  const geneSummary = summarizeGeneticFindings(geneticFindings);
  const improvementText =
    ldl && annualLdl ? `LDL-C 已较年度体检明显回落` : "近期专项血液结果更适合观察短期干预成效";
  const annualText =
    annualExam?.abnormalMetricLabels.length
      ? `当前主线：${annualExam.abnormalMetricLabels.join("、")} 仍需持续管理`
      : `${annualExam?.latestTitle ?? "年度体检"} 可作为长期基线`;
  const geneText = geneSummary.dimensionCount > 0 ? `并已纳入基因背景解释` : undefined;

  return [annualText, improvementText, geneText].filter(Boolean).join("，");
}

function buildOverviewNarrative(
  annualExam: AnnualExamView | undefined,
  latestNarrativeHeadline: string,
  geneticFindings: GeneticFindingView[]
): string {
  const geneSummary = summarizeGeneticFindings(geneticFindings);
  const geneText = geneSummary.count
    ? `同时把 ${geneSummary.topTraits.join("、")}${geneSummary.count > geneSummary.topTraits.length ? ` 等 ${geneSummary.count} 条背景` : ""} 纳入解释框架，覆盖 ${geneSummary.dimensionCount} 个长期维度，避免只看一次化验结果。`
    : "当前以结构化指标和趋势为主。";
  const annualText = annualExam
    ? `${annualExam.latestTitle} 被保留为年度截面基线，近期复查和行为变化则用于解释这个基线是否正在改善。`
    : "当前首页以最近结构化指标为主。";

  return `${annualText}${latestNarrativeHeadline}${geneText}`;
}

function buildOverviewSpotlights(
  annualExam: AnnualExamView | undefined,
  geneticFindings: GeneticFindingView[],
  metricSummaries: Array<{
    metric_code: string;
    metric_name: string;
    latest_value: number;
    unit: string;
    abnormal_flag: string;
  }>
): HealthOverviewSpotlight[] {
  const bodyFat = metricSummaries.find((item) => item.metric_code === "body.body_fat_pct");
  const weight = metricSummaries.find((item) => item.metric_code === "body.weight");
  const lpa = metricSummaries.find((item) => item.metric_code === "lipid.lpa");
  const annualImprovementValue = annualExam?.improvedMetricLabels.length ?? 0;
  const geneSummary = summarizeGeneticFindings(geneticFindings);

  return [
    {
      label: "年度体检焦点",
      value:
        annualExam?.abnormalMetricLabels.length != null && annualExam.abnormalMetricLabels.length > 0
          ? `${annualExam.abnormalMetricLabels.length} 项需持续跟踪`
          : "年度基线稳定",
      tone:
        annualExam?.abnormalMetricLabels.length != null && annualExam.abnormalMetricLabels.length > 0
          ? "attention"
          : "neutral",
      detail:
        annualExam?.abnormalMetricLabels.join("、") ??
        "用于承接年度体检和近期复查之间的关系。"
    },
    {
      label: "近期代谢状态",
      value:
        weight && bodyFat
          ? `${formatCompactValue(weight.latest_value, weight.unit)} / ${formatCompactValue(bodyFat.latest_value, bodyFat.unit)}`
          : "趋势观察中",
      tone: bodyFat?.abnormal_flag === "high" ? "attention" : "positive",
      detail:
        annualImprovementValue > 0
          ? `相较上一年度体检，${annualExam?.improvedMetricLabels.join("、")} 已出现改善。`
          : "用体重和体脂解释近期代谢负荷变化。"
    },
    {
      label: "Lp(a) 长期维度",
      value: lpa ? formatCompactValue(lpa.latest_value, lpa.unit) : "长期背景",
      tone: lpa?.abnormal_flag === "high" ? "attention" : "neutral",
      detail:
        geneticFindings.find((item) => item.traitLabel.includes("Lp(a)"))?.summary ??
        "用于区分慢变量背景和短期行为波动。"
    },
    {
      label: "基因解释层",
      value: geneSummary.count > 0 ? `${geneSummary.count} 条 finding / ${geneSummary.dimensionCount} 维` : "未接入",
      tone: geneticFindings.some((item) => item.riskLevel === "high") ? "attention" : "neutral",
      detail:
        geneSummary.highRiskTraits.length > 0
          ? `高关注背景包括 ${geneSummary.highRiskTraits.join("、")}，适合放进长期策略主线。`
          : geneticFindings[0]?.suggestion ?? "把长期背景因素纳入当前建议，不只盯单一指标。"
    }
  ];
}

function mapAnnualExamView(
  annualExam: ReturnType<typeof getAnnualExamDigest>
): AnnualExamView | undefined {
  if (!annualExam) {
    return undefined;
  }

  const annualExamCopy = getAnnualExamEducationalCopy();

  return {
    latestTitle: annualExam.latestTitle,
    latestRecordedAt: annualExam.latestRecordedAt,
    previousTitle: annualExam.previousTitle,
    metrics: annualExam.metrics.map((metric) => ({
      metricCode: metric.metricCode,
      label: metric.label,
      shortLabel: metric.shortLabel,
      unit: metric.unit,
      latestValue: metric.latestValue,
      previousValue: metric.previousValue,
      delta: metric.delta,
      abnormalFlag: metric.abnormalFlag,
      referenceRange: metric.referenceRange,
      meaning: getMetricEducationalCopy(metric.metricCode)?.meaning ?? annualExamCopy.meaning,
      practicalAdvice:
        getMetricEducationalCopy(metric.metricCode)?.practicalAdvice ?? annualExamCopy.practicalAdvice
    })),
    abnormalMetricLabels: annualExam.abnormalMetricLabels,
    improvedMetricLabels: annualExam.improvedMetricLabels,
    highlightSummary: annualExam.highlightSummary,
    actionSummary: annualExam.actionSummary
  };
}

function mapGeneticFindingView(
  findings: ReturnType<typeof listGeneticFindingDigests>
): GeneticFindingView[] {
  return findings.map((finding) => ({
    id: finding.id,
    geneSymbol: finding.geneSymbol,
    traitLabel: finding.traitLabel,
    dimension: finding.dimension,
    riskLevel: finding.riskLevel,
    evidenceLevel: finding.evidenceLevel,
    summary: finding.summary,
    suggestion: finding.suggestion,
    recordedAt: finding.recordedAt,
    linkedMetricLabel: finding.linkedMetric?.metricName,
    linkedMetricValue: finding.linkedMetric
      ? formatCompactValue(finding.linkedMetric.value, finding.linkedMetric.unit)
      : undefined,
    linkedMetricFlag: finding.linkedMetric?.abnormalFlag,
    plainMeaning: getGeneticEducationalCopy(finding.traitLabel)?.meaning,
    practicalAdvice: getGeneticEducationalCopy(finding.traitLabel)?.practicalAdvice
  }));
}

interface HealthHomeServiceOptions {
  now?: Date;
}

export async function getHealthHomePageData(
  database: DatabaseSync = getDatabase(),
  userId = "user-self",
  options: HealthHomeServiceOptions = {}
): Promise<HealthHomePageData> {
  const latestAsOf = resolveAnalysisAsOf(getLatestSampleTime(database, userId), options.now);
  const structuredInsights = generateHolisticStructuredInsights(database, userId, {
    asOf: latestAsOf
  });
  const narrative = await getCurrentDailySummary(database, userId, options);
  const reportIndex = await getReportsIndexData(database, userId, options);
  const annualExam = mapAnnualExamView(getAnnualExamDigest(database, userId));
  const geneticFindings = mapGeneticFindingView(listGeneticFindingDigests(database, userId));
  const overviewCards = overviewMetricCodes
    .map((metricCode) =>
      structuredInsights.metric_summaries.find((summary) => summary.metric_code === metricCode)
    )
    .filter((summary): summary is NonNullable<typeof summary> => Boolean(summary))
    .map((summary) => buildOverviewCard(summary));
  const sortedInsights = [...structuredInsights.insights].sort(
    (left, right) => reminderWeight(right.severity) - reminderWeight(left.severity)
  );
  const keyReminders = sortedInsights
    .filter((insight) => insight.severity !== "positive")
    .slice(0, 5)
    .map((insight) => buildReminderItem(insight));
  const watchItems = sortedInsights
    .filter((insight) => !keyReminders.some((item) => item.id === insight.id))
    .slice(0, 6)
    .map((insight) => buildReminderItem(insight));
  const sourceDimensions = buildSourceDimensions(
    annualExam,
    geneticFindings,
    structuredInsights.metric_summaries
  );
  const overviewHeadline = buildOverviewHeadline(
    annualExam,
    geneticFindings,
    structuredInsights.metric_summaries
  );
  const overviewNarrative = buildOverviewNarrative(
    annualExam,
    narrative.output.headline,
    geneticFindings
  );
  const overviewSpotlights = buildOverviewSpotlights(
    annualExam,
    geneticFindings,
    structuredInsights.metric_summaries
  );
  const coverage = getCoverageSummary(database)
    .filter((item) =>
      ["annual_exam", "lipid_panel", "body_composition", "activity_daily", "genetic_panel"].includes(
        item.kind
      )
    )
    .map((item) => `${item.label} · ${item.count} 份`);

  return {
    generatedAt: new Date().toISOString(),
    disclaimer: NON_DIAGNOSTIC_DISCLAIMER,
    overviewHeadline,
    overviewNarrative,
    overviewFocusAreas: [...coverage, ...geneticFindings.slice(0, 2).map((item) => item.traitLabel)].slice(
      0,
      6
    ),
    overviewSpotlights,
    sourceDimensions,
    overviewCards,
    annualExam,
    geneticFindings,
    keyReminders,
    watchItems,
    latestNarrative: narrative,
    charts: {
      lipid: {
        title: "血脂趋势图",
        description: "把年度体检基线、近期专项血脂和 Lp(a) 长期背景放在同一视角里看。",
        defaultRange: "1y",
        data: getUnifiedTrendSeries(
          database,
          userId,
          [
            { metricCode: "lipid.ldl_c", alias: "ldl" },
            { metricCode: "lipid.triglycerides", alias: "tg" },
            { metricCode: "lipid.hdl_c", alias: "hdl" },
            { metricCode: "lipid.total_cholesterol", alias: "tc" },
            { metricCode: "lipid.lpa", alias: "lpa" }
          ],
          latestAsOf
        ),
        lines: [
          { key: "ldl", label: "LDL-C", color: "#0f766e", unit: "mmol/L", yAxisId: "left" },
          { key: "tg", label: "TG", color: "#d97706", unit: "mmol/L", yAxisId: "left" },
          { key: "hdl", label: "HDL-C", color: "#2563eb", unit: "mmol/L", yAxisId: "left" },
          { key: "tc", label: "TC", color: "#9f1239", unit: "mmol/L", yAxisId: "left" },
          { key: "lpa", label: "Lp(a)", color: "#5b21b6", unit: "mg/dL", yAxisId: "right" }
        ]
      },
      bodyComposition: {
        title: "体重 / 体脂趋势图",
        description: "把体重、体脂和年度体检中的 BMI 变化放在同一减脂质量视角里看。",
        defaultRange: "1y",
        data: getUnifiedTrendSeries(
          database,
          userId,
          [
            { metricCode: "body.weight", alias: "weight" },
            { metricCode: "body.body_fat_pct", alias: "bodyFat" },
            { metricCode: "body.bmi", alias: "bmi" }
          ],
          latestAsOf
        ),
        lines: [
          { key: "weight", label: "体重", color: "#0f766e", unit: "kg", yAxisId: "left" },
          { key: "bodyFat", label: "体脂率", color: "#be123c", unit: "%", yAxisId: "right" },
          { key: "bmi", label: "BMI", color: "#0f4c81", unit: "kg/m2", yAxisId: "right" }
        ]
      },
      activity: {
        title: "运动执行图",
        description: "重点展示训练分钟和活动能量，帮助解释近期体脂与血脂变化。",
        defaultRange: "90d",
        data: getUnifiedTrendSeries(
          database,
          userId,
          [
            { metricCode: "activity.exercise_minutes", alias: "exerciseMinutes" },
            { metricCode: "activity.active_kcal", alias: "activeKcal" }
          ],
          latestAsOf
        ),
        lines: [
          { key: "exerciseMinutes", label: "训练分钟", color: "#0f766e", unit: "min", yAxisId: "left" },
          { key: "activeKcal", label: "活动能量", color: "#c2410c", unit: "kcal", yAxisId: "right" }
        ]
      },
      recovery: {
        title: "睡眠 / 恢复图",
        description: "用睡眠恢复与运动执行一起看，为咖啡因敏感性等背景 finding 提供落地观察面。",
        defaultRange: "90d",
        data: getUnifiedTrendSeries(
          database,
          userId,
          [
            { metricCode: "sleep.asleep_minutes", alias: "sleepMinutes" },
            { metricCode: "activity.exercise_minutes", alias: "exerciseMinutes" }
          ],
          latestAsOf
        ),
        lines: [
          { key: "sleepMinutes", label: "睡眠时间", color: "#1d4ed8", unit: "min", yAxisId: "left" },
          { key: "exerciseMinutes", label: "训练分钟", color: "#0f766e", unit: "min", yAxisId: "right" }
        ]
      }
    },
    latestReports: [reportIndex.weeklyReports[0], reportIndex.monthlyReports[0]].filter(
      (item): item is NonNullable<typeof item> => Boolean(item)
    )
  };
}
