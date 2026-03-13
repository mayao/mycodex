import type { DatabaseSync } from "node:sqlite";

import { NON_DIAGNOSTIC_DISCLAIMER } from "../../data/mock/seed-data";
import type {
  HealthAnalysisMetric,
  HealthDimensionAnalysis,
  AnnualExamView,
  GeneticFindingView,
  HealthHomePageData,
  HealthImportOption,
  HealthOverviewCard,
  HealthOverviewDigest,
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
import { importerSpecs } from "../importers/specs";
import {
  getAnnualExamEducationalCopy,
  getGeneticEducationalCopy,
  getInsightEducationalCopy,
  getMetricEducationalCopy
} from "./health-communication";
import { generateHolisticStructuredInsights } from "./holistic-insight-service";
import { getCurrentDailySummary, getReportsIndexData } from "./report-service";
import {
  sanitizeDimensionAnalyses,
  sanitizeHealthSummary,
  sanitizeOverviewDigest,
  sanitizeReminderItems,
  sanitizeText
} from "./user-facing-copy";

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

type MetricSummaryLite = {
  metric_code: string;
  metric_name: string;
  latest_value: number;
  unit: string;
  latest_vs_mean?: number;
  trend_direction?: string;
  month_over_month?: number;
  abnormal_flag: string;
  latest_sample_time: string;
};

function getMetricSummary(
  metricSummaries: MetricSummaryLite[],
  metricCode: string
): MetricSummaryLite | undefined {
  return metricSummaries.find((item) => item.metric_code === metricCode);
}

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

function formatHoursFromMinutes(minutes: number | undefined): string {
  if (typeof minutes !== "number") {
    return "暂无数据";
  }

  return `${(minutes / 60).toFixed(1)} 小时`;
}

function averageAliasValue(
  data: Array<Record<string, number | string | undefined>>,
  alias: string
): number | undefined {
  const values = data
    .map((item) => item[alias])
    .filter((value): value is number => typeof value === "number");

  if (values.length === 0) {
    return undefined;
  }

  return Number((values.reduce((total, current) => total + current, 0) / values.length).toFixed(1));
}

function dedupeList(items: Array<string | undefined>, limit = 4): string[] {
  return [...new Set(items.map((item) => item?.trim()).filter((item): item is string => Boolean(item)))]
    .slice(0, limit);
}

function toneFromFlag(flag: string | undefined): HealthAnalysisMetric["tone"] {
  if (flag === "high" || flag === "low" || flag === "borderline") {
    return "attention";
  }

  return "positive";
}

function riskScore(riskLevel: GeneticFindingView["riskLevel"]): number {
  if (riskLevel === "high") {
    return 3;
  }

  if (riskLevel === "medium") {
    return 2;
  }

  return 1;
}

function metricTile(
  label: string,
  value: string,
  detail: string,
  tone: HealthAnalysisMetric["tone"]
): HealthAnalysisMetric {
  return { label, value, detail, tone };
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
  appleHealthSync: {
    latestAt?: string;
    count: number;
  },
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
          ? `最新 LDL-C 为 ${formatCompactValue(ldl.latest_value, ldl.unit)}，可继续和年度体检结果一起跟踪。`
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
          ? `最新体脂率为 ${formatCompactValue(bodyFat.latest_value, bodyFat.unit)}，可持续观察近期体成分变化。`
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
          ? `最新训练分钟为 ${formatCompactValue(exercise.latest_value, exercise.unit)}，可结合体脂和代谢指标一起看。`
          : "暂无运动执行度数据。",
      highlight:
        exercise != null
          ? `${exercise.metric_name} ${formatCompactValue(exercise.latest_value, exercise.unit)}`
          : "训练节奏"
    },
    {
      key: "apple_health",
      label: "Apple 健康",
      latestAt: appleHealthSync.latestAt,
      status: appleHealthSync.count > 0 ? "ready" : "background",
      summary:
        appleHealthSync.count > 0
          ? `已从 Apple 健康同步 ${appleHealthSync.count} 条记录，最近数据已纳入睡眠、运动和身体组成分析。`
          : "尚未从 Apple 健康同步数据。",
      highlight: appleHealthSync.count > 0 ? `已同步 ${appleHealthSync.count} 条` : "等待同步"
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
    ldl && annualLdl ? "LDL-C 较年度体检已明显回落" : "近期血脂结果可继续作为干预成效参考";
  const annualText =
    annualExam?.abnormalMetricLabels.length
      ? `当前重点仍是 ${annualExam.abnormalMetricLabels.join("、")}`
      : `${annualExam?.latestTitle ?? "年度体检"} 作为长期基线`;
  const geneText = geneSummary.dimensionCount > 0 ? `并结合 ${geneSummary.dimensionCount} 个长期背景维度` : undefined;

  return [annualText, improvementText, geneText].filter(Boolean).join("，");
}

function buildOverviewNarrative(
  annualExam: AnnualExamView | undefined,
  latestNarrativeHeadline: string,
  geneticFindings: GeneticFindingView[]
): string {
  const geneSummary = summarizeGeneticFindings(geneticFindings);
  const geneText = geneSummary.count
    ? `同时纳入 ${geneSummary.topTraits.join("、")}${geneSummary.count > geneSummary.topTraits.length ? ` 等 ${geneSummary.count} 条基因背景` : ""}，覆盖 ${geneSummary.dimensionCount} 个长期维度。`
    : "当前以近期结构化指标和趋势为主。";
  const annualText = annualExam
    ? `${annualExam.latestTitle} 作为年度基线，近期复查和行为数据用于判断变化是否延续。`
    : "当前以近期结构化指标和趋势为主。";

  return [annualText, `当前摘要：${latestNarrativeHeadline}`, geneText].filter(Boolean).join(" ");
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
        "结合年度体检和近期复查一起看。"
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
          : geneticFindings[0]?.suggestion ?? "把长期背景一起纳入当前建议。"
    }
  ];
}

function buildImportOptions(): HealthImportOption[] {
  const formatMap: Record<HealthImportOption["key"], string[]> = {
    annual_exam: [".png", ".jpg", ".pdf", ".csv", ".xlsx", ".xls"],
    blood_test: [".png", ".jpg", ".pdf", ".csv", ".xlsx", ".xls"],
    body_scale: [".png", ".jpg", ".pdf", ".csv", ".xlsx"],
    activity: [".png", ".jpg", ".pdf", ".csv", ".xlsx"]
  };

  return (Object.entries(importerSpecs) as Array<[HealthImportOption["key"], (typeof importerSpecs)[keyof typeof importerSpecs]]>).map(
    ([key, spec]) => ({
      key,
      title: spec.sourceName,
      description: `支持图片、PDF、CSV、Excel。上传后会异步识别文本、映射指标并回流到当前健康总览。`,
      formats: formatMap[key],
      hints: [
        `常见字段：${spec.fieldMappings.slice(0, 3).map((item) => item.metricName).join("、")}`,
        `时间列支持：${spec.sampleTimeAliases.slice(0, 2).join(" / ")}；图片或 PDF 会先做 OCR/文档识别。`,
        "上传会在后台继续处理，完成后可在数据页查看状态与结果。"
      ]
    })
  );
}

function getAppleHealthSyncSummary(database: DatabaseSync, userId: string) {
  const row = database
    .prepare(
      `
      SELECT
        COUNT(*) AS count,
        MAX(sample_time) AS latestAt
      FROM metric_record
      WHERE user_id = ? AND source_type = 'apple_health'
    `
    )
    .get(userId) as { count: number; latestAt?: string } | undefined;

  return {
    count: row?.count ?? 0,
    latestAt: row?.latestAt
  };
}

function buildOverviewDigest(params: {
  annualExam: AnnualExamView | undefined;
  geneticFindings: GeneticFindingView[];
  metricSummaries: MetricSummaryLite[];
  charts: HealthHomePageData["charts"];
  narrativeHeadline: string;
  keyReminders: HealthReminderItem[];
}): HealthOverviewDigest {
  const { annualExam, geneticFindings, metricSummaries, charts, narrativeHeadline, keyReminders } = params;
  const ldl = getMetricSummary(metricSummaries, "lipid.ldl_c");
  const tc = getMetricSummary(metricSummaries, "lipid.total_cholesterol");
  const lpa = getMetricSummary(metricSummaries, "lipid.lpa");
  const weight = getMetricSummary(metricSummaries, "body.weight");
  const bodyFat = getMetricSummary(metricSummaries, "body.body_fat_pct");
  const exercise = getMetricSummary(metricSummaries, "activity.exercise_minutes");
  const annualLdl = annualExam?.metrics.find((item) => item.metricCode === "lipid.ldl_c");
  const annualTc = annualExam?.metrics.find((item) => item.metricCode === "lipid.total_cholesterol");
  const annualWeight = annualExam?.metrics.find((item) => item.metricCode === "body.weight");
  const recentSleepAvg = averageAliasValue(charts.recovery.data, "sleepMinutes");
  const recentExerciseAvg = averageAliasValue(charts.activity.data, "exerciseMinutes");
  const lpaFinding = geneticFindings.find((item) => item.traitLabel.includes("Lp(a)"));
  const caffeineFinding = geneticFindings.find((item) => item.traitLabel.includes("咖啡因"));

  const goodSignals = dedupeList([
    annualExam?.improvedMetricLabels.length
      ? `和上一年体检相比，${annualExam.improvedMetricLabels.join("、")} 已经出现回落或改善。`
      : undefined,
    ldl && annualLdl && ldl.latest_value < annualLdl.latestValue
      ? `近期医院复查里，LDL-C 已经从年度体检的 ${formatCompactValue(annualLdl.latestValue, annualLdl.unit)} 降到 ${formatCompactValue(ldl.latest_value, ldl.unit)}。`
      : undefined,
    tc && annualTc && tc.latest_value < annualTc.latestValue
      ? `总胆固醇也从年度体检的 ${formatCompactValue(annualTc.latestValue, annualTc.unit)} 回落到 ${formatCompactValue(tc.latest_value, tc.unit)}，说明血脂主线不是停滞状态。`
      : undefined,
    weight && annualWeight && weight.latest_value < annualWeight.latestValue
      ? `体重已经从年度体检的 ${formatCompactValue(annualWeight.latestValue, annualWeight.unit)} 降到 ${formatCompactValue(weight.latest_value, weight.unit)}，近期体重管理方向是对的。`
      : undefined,
    bodyFat && bodyFat.trend_direction === "down"
      ? `体脂率也在往下走，说明当前改善不只是数字波动，而是身体成分在慢慢变化。`
      : undefined,
    exercise && typeof recentExerciseAvg === "number"
      ? `最近一段时间训练分钟大致维持在日均 ${Math.round(recentExerciseAvg)} 分钟，运动执行度还在。`
      : undefined
  ]);

  const needsAttention = dedupeList([
    bodyFat?.abnormal_flag === "high"
      ? `体脂率目前仍高于参考范围，说明虽然体重和血脂在改善，但减脂这条线还没有彻底完成。`
      : undefined,
    typeof recentSleepAvg === "number" && recentSleepAvg < 420
      ? `最近两周平均睡眠大约只有 ${formatHoursFromMinutes(recentSleepAvg)}，恢复窗口偏短，容易拖慢减脂、训练恢复和代谢稳定。`
      : undefined,
    lpa?.abnormal_flag === "high"
      ? "Lp(a) 仍然偏高，更适合按长周期持续跟踪。"
      : undefined,
    keyReminders[0]?.summary
  ]);

  const longTermRisks = dedupeList([
    annualExam?.abnormalMetricLabels.length
      ? `年度体检仍把 ${annualExam.abnormalMetricLabels.join("、")} 放在主线上，说明短期改善虽然出现了，但还没到可以完全放松的时候。`
      : undefined,
    lpaFinding && lpa?.abnormal_flag === "high"
      ? `${lpaFinding.traitLabel} 和当前偏高的 Lp(a) 放在一起看，更需要放在长期风险管理里持续观察。`
      : undefined,
    caffeineFinding && typeof recentSleepAvg === "number" && recentSleepAvg < 420
      ? `${caffeineFinding.traitLabel} 这类背景如果和现在的短睡叠加，恢复质量更容易成为你后续训练和血脂管理的拖后腿因素。`
      : undefined
  ]);

  const actionPlan = dedupeList([
    `继续保留已经有效的运动和体重管理节奏，重点不是更猛，而是把当前趋势稳定住。`,
    bodyFat?.abnormal_flag === "high"
      ? "下一阶段把重点放在体脂率和睡眠恢复，而不是只盯体重数字。"
      : undefined,
    typeof recentSleepAvg === "number" && recentSleepAvg < 420
      ? "先把睡眠时长拉近 7 小时目标；目前只有睡眠时长数据，暂时不能判断是不是“睡得太晚”。"
      : undefined,
    lpaFinding?.suggestion,
    narrativeHeadline
  ]);

  return {
    headline: "体重和血脂已经朝好的方向走，但恢复和长期血脂背景还需要单独盯住。",
    summary:
      "近期体重和血脂在改善，但体脂率、睡眠恢复和 Lp(a) 仍需要持续关注。",
    goodSignals,
    needsAttention,
    longTermRisks,
    actionPlan
  };
}

function buildDimensionAnalyses(params: {
  annualExam: AnnualExamView | undefined;
  geneticFindings: GeneticFindingView[];
  metricSummaries: MetricSummaryLite[];
  charts: HealthHomePageData["charts"];
  overviewDigest: HealthOverviewDigest;
  latestNarrative: HealthHomePageData["latestNarrative"];
}): HealthDimensionAnalysis[] {
  const { annualExam, geneticFindings, metricSummaries, charts, overviewDigest, latestNarrative } =
    params;
  const ldl = getMetricSummary(metricSummaries, "lipid.ldl_c");
  const tc = getMetricSummary(metricSummaries, "lipid.total_cholesterol");
  const lpa = getMetricSummary(metricSummaries, "lipid.lpa");
  const apob = getMetricSummary(metricSummaries, "lipid.apob");
  const weight = getMetricSummary(metricSummaries, "body.weight");
  const bodyFat = getMetricSummary(metricSummaries, "body.body_fat_pct");
  const sleep = getMetricSummary(metricSummaries, "sleep.asleep_minutes");
  const exercise = getMetricSummary(metricSummaries, "activity.exercise_minutes");
  const annualLdl = annualExam?.metrics.find((item) => item.metricCode === "lipid.ldl_c");
  const annualTc = annualExam?.metrics.find((item) => item.metricCode === "lipid.total_cholesterol");
  const recentSleepAvg = averageAliasValue(charts.recovery.data, "sleepMinutes");
  const recentExerciseAvg = averageAliasValue(charts.activity.data, "exerciseMinutes");
  const lpaFinding = geneticFindings.find((item) => item.traitLabel.includes("Lp(a)"));
  const caffeineFinding = geneticFindings.find((item) => item.traitLabel.includes("咖啡因"));
  const highRiskGenes = geneticFindings.filter((item) => item.riskLevel === "high");
  const geneticDimensionGroups = [...new Map(
    geneticFindings.map((item) => [item.dimension, geneticFindings.filter((entry) => entry.dimension === item.dimension)])
  ).entries()]
    .map(([dimension, findings]) => ({ dimension, findings }))
    .sort((left, right) => {
      const leftScore = Math.max(...left.findings.map((item) => riskScore(item.riskLevel)));
      const rightScore = Math.max(...right.findings.map((item) => riskScore(item.riskLevel)));
      return rightScore - leftScore;
    });

  return [
    {
      key: "annual_exam",
      kicker: "Annual Baseline",
      title: "年度体检基线",
      summary:
        "年度体检帮助你看长期基线，目前提示代谢和血脂仍需持续管理。",
      goodSignals: dedupeList([
        annualExam?.improvedMetricLabels.length
          ? `${annualExam.improvedMetricLabels.join("、")} 相较上一年度已经出现改善。`
          : undefined,
        annualExam?.highlightSummary
      ]),
      needsAttention: dedupeList([
        annualExam?.abnormalMetricLabels.length
          ? `当前年度基线仍重点提示 ${annualExam.abnormalMetricLabels.join("、")}。`
          : undefined
      ]),
      longTermRisks: dedupeList([
        annualExam?.abnormalMetricLabels.length
          ? "这意味着短期复查虽然在变好，但代谢和血脂这条主线还需要持续管理，不能只因为一次结果回落就放松。"
          : undefined
      ]),
      actionPlan: dedupeList([
        annualExam?.actionSummary,
        ...(
          annualExam?.metrics
            .filter((metric) => metric.abnormalFlag !== "normal")
            .slice(0, 2)
            .map((metric) => metric.practicalAdvice) ?? []
        )
      ]),
      metrics: (
        annualExam?.metrics
          .filter((metric) =>
            ["body.bmi", "lipid.total_cholesterol", "lipid.ldl_c", "glycemic.glucose"].includes(metric.metricCode)
          )
          .slice(0, 4)
          .map((metric) =>
            metricTile(
              metric.shortLabel,
              formatValue(metric.latestValue, metric.unit),
              typeof metric.delta === "number" ? `同比 ${signed(metric.delta, metric.unit)}` : "年度基线",
              toneFromFlag(metric.abnormalFlag)
            )
          ) ?? []
      )
    },
    {
      key: "clinical_labs",
      kicker: "Clinical Recheck",
      title: "医院复查与血脂专项",
      summary:
        "近期医院复查显示血脂已经开始改善，但还需要继续观察是否稳定。",
      goodSignals: dedupeList([
        ldl && annualLdl && ldl.latest_value < annualLdl.latestValue
          ? `LDL-C 从年度体检的 ${formatCompactValue(annualLdl.latestValue, annualLdl.unit)} 降到 ${formatCompactValue(ldl.latest_value, ldl.unit)}。`
          : undefined,
        tc && annualTc && tc.latest_value < annualTc.latestValue
          ? `总胆固醇也从 ${formatCompactValue(annualTc.latestValue, annualTc.unit)} 降到 ${formatCompactValue(tc.latest_value, tc.unit)}。`
          : undefined,
        ldl?.abnormal_flag === "normal" ? "当前 LDL-C 已回到参考范围内，说明近期血脂管理是有效的。" : undefined
      ]),
      needsAttention: dedupeList([
        lpa?.abnormal_flag === "high"
          ? `Lp(a) 仍高于参考范围，短期行为不一定立刻拉得下来。`
          : undefined,
        apob?.abnormal_flag === "low"
          ? `ApoB 目前偏低，建议继续和 LDL-C、甘油三酯、体脂率一起联动观察，不单看单次结果。`
          : undefined
      ]),
      longTermRisks: dedupeList([
        lpaFinding && lpa?.abnormal_flag === "high"
          ? `${lpaFinding.traitLabel} 叠加当前偏高结果，更像长期风险标签，适合放进慢变量管理。`
          : undefined
      ]),
      actionPlan: dedupeList([
        "保持当前已经有效的体重管理与运动节奏，重点观察血脂是否能继续稳定在当前区间。",
        "把下一次血脂复查与体脂、训练变化放在同一时间轴里看，避免只看单次化验。",
        lpaFinding?.suggestion
      ]),
      metrics: [
        ldl
          ? metricTile(
              "LDL-C",
              formatValue(ldl.latest_value, ldl.unit),
              annualLdl ? `较年度体检 ${signed(ldl.latest_value - annualLdl.latestValue, ldl.unit)}` : ldl.trend_direction === "down" ? "近期继续下降" : "近期继续观察",
              toneFromFlag(ldl.abnormal_flag)
            )
          : undefined,
        tc
          ? metricTile(
              "总胆固醇",
              formatValue(tc.latest_value, tc.unit),
              annualTc ? `较年度体检 ${signed(tc.latest_value - annualTc.latestValue, tc.unit)}` : tc.trend_direction === "down" ? "近期继续下降" : "近期继续观察",
              toneFromFlag(tc.abnormal_flag)
            )
          : undefined,
        lpa
          ? metricTile("Lp(a)", formatValue(lpa.latest_value, lpa.unit), "更适合按长周期复查", toneFromFlag(lpa.abnormal_flag))
          : undefined,
        apob
          ? metricTile("ApoB", formatValue(apob.latest_value, apob.unit), "配合 LDL-C 和 TG 一起看", toneFromFlag(apob.abnormal_flag))
          : undefined
      ].filter((item): item is HealthAnalysisMetric => Boolean(item))
    },
    {
      key: "activity_recovery",
      kicker: "Activity + Recovery",
      title: "运动与睡眠恢复",
      summary:
        "运动执行度仍在，但睡眠恢复偏短，可能影响减脂和代谢改善的延续性。",
      goodSignals: dedupeList([
        typeof recentExerciseAvg === "number"
          ? `最近一段时间训练分钟大致维持在日均 ${Math.round(recentExerciseAvg)} 分钟，运动执行没有掉线。`
          : undefined,
        weight && bodyFat && bodyFat.trend_direction === "down"
          ? `体重和体脂率都在往下走，说明近期运动和体重管理对身体成分是有帮助的。`
          : undefined
      ]),
      needsAttention: dedupeList([
        bodyFat?.abnormal_flag === "high"
          ? `体脂率仍高于参考范围，说明现在更像“正在改善中”，还不是“已经完成”。`
          : undefined,
        typeof recentSleepAvg === "number" && recentSleepAvg < 420
          ? `最近两周平均睡眠约 ${formatHoursFromMinutes(recentSleepAvg)}，恢复时间偏短。`
          : undefined,
        "当前只有睡眠时长，没有入睡时间数据，所以暂时不能判断是否存在明显晚睡问题。"
      ]),
      longTermRisks: dedupeList([
        typeof recentSleepAvg === "number" && recentSleepAvg < 420
          ? "恢复时间长期偏短，会影响减脂效率、训练恢复和第二天执行稳定性。"
          : undefined,
        caffeineFinding
          ? `${caffeineFinding.traitLabel} 这类背景提示你在咖啡因和恢复之间可能更敏感。`
          : undefined
      ]),
      actionPlan: dedupeList([
        "先把睡眠时长往 7 小时目标拉近，再观察体脂、恢复感和训练完成度是否同步改善。",
        "继续保留当前训练频率，但把体脂率和睡眠恢复放到同一周维度一起看。",
        caffeineFinding?.suggestion
      ]),
      metrics: [
        exercise
          ? metricTile(
              "训练分钟",
              formatValue(exercise.latest_value, exercise.unit),
              typeof recentExerciseAvg === "number" ? `近段日均 ${Math.round(recentExerciseAvg)} min` : "近期趋势观察中",
              "positive"
            )
          : undefined,
        sleep
          ? metricTile(
              "睡眠时间",
              formatHoursFromMinutes(sleep.latest_value),
              typeof recentSleepAvg === "number" ? `近段均值 ${formatHoursFromMinutes(recentSleepAvg)}` : "仅有最新值",
              typeof recentSleepAvg === "number" && recentSleepAvg < 420 ? "attention" : "positive"
            )
          : undefined,
        bodyFat
          ? metricTile("体脂率", formatValue(bodyFat.latest_value, bodyFat.unit), bodyFat.trend_direction === "down" ? "近期在下降" : "近期继续观察", toneFromFlag(bodyFat.abnormal_flag))
          : undefined,
        weight
          ? metricTile("体重", formatValue(weight.latest_value, weight.unit), weight.trend_direction === "down" ? "近期在下降" : "近期继续观察", "positive")
          : undefined
      ].filter((item): item is HealthAnalysisMetric => Boolean(item))
    },
    {
      key: "genetics",
      kicker: "Genetic Context",
      title: "基因检测与长期背景",
      summary:
        "基因结果提供长期背景，用来解释为什么某些指标需要更长时间跟踪。",
      goodSignals: dedupeList([
        geneticFindings.length > 0 ? `当前已接入 ${geneticFindings.length} 条基因背景，覆盖 ${geneticDimensionGroups.length} 个核心维度。` : undefined,
        highRiskGenes.length > 0 ? `高关注背景已经能和当前指标做对照，避免只停留在概念层。` : undefined
      ]),
      needsAttention: dedupeList([
        ...geneticDimensionGroups.map(
          (group) =>
            `${group.dimension}：${group.findings
              .map((item) => item.traitLabel)
              .join("、")}`
        )
      ], 6),
      longTermRisks: dedupeList([
        lpaFinding ? `${lpaFinding.traitLabel} 更适合纳入 6-12 个月尺度的长期跟踪。` : undefined,
        caffeineFinding ? `${caffeineFinding.traitLabel} 如果叠加短睡，会让恢复质量更容易成为瓶颈。` : undefined,
        ...geneticDimensionGroups
          .filter((group) => group.findings.some((item) => item.riskLevel !== "low"))
          .map((group) => {
            const linkedMetrics = dedupeList(group.findings.map((item) => item.linkedMetricLabel));
            return linkedMetrics.length > 0
              ? `${group.dimension} 建议和 ${linkedMetrics.join("、")} 放在同一条长期跟踪线上。`
              : `${group.dimension} 适合保留为长期背景维度，避免只看一次结果。`;
          })
      ], 6),
      actionPlan: dedupeList(
        geneticDimensionGroups
          .flatMap((group) => group.findings.map((item) => item.suggestion)),
        5
      ),
      metrics: [
        metricTile("高关注背景", `${highRiskGenes.length}`, "需要放到长期主线里", highRiskGenes.length > 0 ? "attention" : "positive"),
        metricTile("覆盖维度", `${geneticDimensionGroups.length}`, "把遗传背景映射到实际决策", "positive"),
        metricTile(
          "核心 trait",
          `${geneticFindings.length}`,
          geneticDimensionGroups.slice(0, 2).map((group) => group.dimension).join(" / "),
          "neutral"
        ),
        lpa
          ? metricTile("关联 Lp(a)", formatValue(lpa.latest_value, lpa.unit), "和长期背景一起解读", toneFromFlag(lpa.abnormal_flag))
          : undefined,
        sleep
          ? metricTile("关联睡眠", formatHoursFromMinutes(sleep.latest_value), "用来解释恢复差异", "neutral")
          : undefined
      ].filter((item): item is HealthAnalysisMetric => Boolean(item))
    },
    {
      key: "integrated",
      kicker: "AI Integrated View",
      title: "综合 AI 洞察与建议",
      summary:
        "综合来看，趋势已经开始转好，但恢复和长期血脂背景仍要继续管理。",
      goodSignals: overviewDigest.goodSignals,
      needsAttention: overviewDigest.needsAttention,
      longTermRisks: overviewDigest.longTermRisks,
      actionPlan: dedupeList([...overviewDigest.actionPlan, ...latestNarrative.output.priority_actions], 5),
      metrics: [
        metricTile("改善信号", `${overviewDigest.goodSignals.length}`, "体重、血脂、执行度", "positive"),
        metricTile("当前卡点", `${overviewDigest.needsAttention.length}`, "减脂与恢复", "attention"),
        metricTile("长期背景", `${overviewDigest.longTermRisks.length}`, "慢变量风险", "attention"),
        metricTile("优先动作", `${dedupeList(latestNarrative.output.priority_actions, 5).length}`, "先做最有把握的动作", "positive")
      ]
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
  userId: string = "user-self",
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
  const keyReminders = sanitizeReminderItems(
    sortedInsights
    .filter((insight) => insight.severity !== "positive")
    .slice(0, 5)
    .map((insight) => buildReminderItem(insight))
  );
  const watchItems = sanitizeReminderItems(
    sortedInsights
    .filter((insight) => !keyReminders.some((item) => item.id === insight.id))
    .slice(0, 6)
    .map((insight) => buildReminderItem(insight))
  );
  const appleHealthSync = getAppleHealthSyncSummary(database, userId);
  const sourceDimensions = buildSourceDimensions(
    annualExam,
    geneticFindings,
    appleHealthSync,
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
  const charts = {
    lipid: {
      title: "血脂趋势图",
      description: "把年度体检基线、近期专项血脂和 Lp(a) 长期背景放在同一视角里看。",
      defaultRange: "1y" as const,
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
        { key: "ldl", label: "LDL-C", color: "#0f766e", unit: "mmol/L", yAxisId: "left" as const },
        { key: "tg", label: "TG", color: "#d97706", unit: "mmol/L", yAxisId: "left" as const },
        { key: "hdl", label: "HDL-C", color: "#2563eb", unit: "mmol/L", yAxisId: "left" as const },
        { key: "tc", label: "TC", color: "#9f1239", unit: "mmol/L", yAxisId: "left" as const },
        { key: "lpa", label: "Lp(a)", color: "#5b21b6", unit: "mg/dL", yAxisId: "right" as const }
      ]
    },
    bodyComposition: {
      title: "体重 / 体脂趋势图",
      description: "把体重、体脂和年度体检中的 BMI 变化放在同一减脂质量视角里看。",
      defaultRange: "1y" as const,
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
        { key: "weight", label: "体重", color: "#0f766e", unit: "kg", yAxisId: "left" as const },
        { key: "bodyFat", label: "体脂率", color: "#be123c", unit: "%", yAxisId: "right" as const },
        { key: "bmi", label: "BMI", color: "#0f4c81", unit: "kg/m2", yAxisId: "right" as const }
      ]
    },
    activity: {
      title: "运动执行图",
      description: "展示步数、训练分钟和活动能量，帮助解释近期体脂与血脂变化。",
      defaultRange: "90d" as const,
      data: getUnifiedTrendSeries(
        database,
        userId,
        [
          { metricCode: "activity.steps", alias: "steps" },
          { metricCode: "activity.exercise_minutes", alias: "exerciseMinutes" },
          { metricCode: "activity.active_kcal", alias: "activeKcal" }
        ],
        latestAsOf
      ),
      lines: [
        { key: "steps", label: "步数", color: "#ea580c", unit: "count", yAxisId: "right" as const },
        { key: "exerciseMinutes", label: "训练分钟", color: "#0f766e", unit: "min", yAxisId: "left" as const },
        { key: "activeKcal", label: "活动能量", color: "#c2410c", unit: "kcal", yAxisId: "right" as const }
      ]
    },
    recovery: {
      title: "睡眠 / 恢复图",
      description: "用睡眠恢复与运动执行一起看，为咖啡因敏感性等背景 finding 提供落地观察面。",
      defaultRange: "90d" as const,
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
        { key: "sleepMinutes", label: "睡眠时间", color: "#1d4ed8", unit: "min", yAxisId: "left" as const },
        { key: "exerciseMinutes", label: "训练分钟", color: "#0f766e", unit: "min", yAxisId: "right" as const }
      ]
    }
  };
  const overviewDigest = sanitizeOverviewDigest(buildOverviewDigest({
    annualExam,
    geneticFindings,
    metricSummaries: structuredInsights.metric_summaries,
    charts,
    narrativeHeadline: narrative.output.headline,
    keyReminders
  }));
  const dimensionAnalyses = sanitizeDimensionAnalyses(buildDimensionAnalyses({
    annualExam,
    geneticFindings,
    metricSummaries: structuredInsights.metric_summaries,
    charts,
    overviewDigest,
    latestNarrative: narrative
  }));
  const coverage = getCoverageSummary(database)
    .filter((item) =>
      ["annual_exam", "lipid_panel", "body_composition", "activity_daily", "genetic_panel"].includes(
        item.kind
      )
    )
    .map((item) => `${item.label} · ${item.count} 份`);

  return {
    generatedAt: latestAsOf,
    disclaimer: NON_DIAGNOSTIC_DISCLAIMER,
    overviewHeadline: sanitizeText(overviewHeadline, overviewHeadline),
    overviewNarrative: sanitizeText(overviewNarrative, overviewNarrative),
    overviewDigest,
    overviewFocusAreas: [...coverage, ...geneticFindings.slice(0, 2).map((item) => item.traitLabel)].slice(
      0,
      6
    ),
    overviewSpotlights,
    sourceDimensions,
    dimensionAnalyses,
    importOptions: buildImportOptions(),
    overviewCards,
    annualExam,
    geneticFindings,
    keyReminders,
    watchItems,
    latestNarrative: sanitizeHealthSummary(narrative),
    charts,
    latestReports: [reportIndex.weeklyReports[0], reportIndex.monthlyReports[0]].filter(
      (item): item is NonNullable<typeof item> => Boolean(item)
    )
  };
}
