import type { DatabaseSync } from "node:sqlite";

import type {
  StructuredInsight,
  StructuredInsightEvidenceMetric,
  StructuredInsightsResult
} from "../insights/types";
import { generateStructuredInsights } from "../insights/structured-rule-engine";
import {
  getAnnualExamDigest,
  listGeneticFindingDigests
} from "../repositories/document-insight-repository";

function buildEvidenceMetricFromAnnualDigest(metric: {
  metricCode: string;
  label: string;
  shortLabel: string;
  unit: string;
  latestValue: number;
  previousValue?: number;
  delta?: number;
  abnormalFlag: string;
  referenceRange?: string;
  latestRecordedAt: string;
}): StructuredInsightEvidenceMetric {
  return {
    metric_code: metric.metricCode,
    metric_name: metric.label,
    unit: metric.unit,
    latest_value: metric.latestValue,
    latest_sample_time: metric.latestRecordedAt,
    sample_count: typeof metric.previousValue === "number" ? 2 : 1,
    historical_mean:
      typeof metric.previousValue === "number"
        ? Number(((metric.latestValue + metric.previousValue) / 2).toFixed(3))
        : undefined,
    latest_vs_mean:
      typeof metric.previousValue === "number"
        ? Number((metric.latestValue - (metric.latestValue + metric.previousValue) / 2).toFixed(3))
        : undefined,
    trend_direction:
      typeof metric.delta !== "number" || metric.delta === 0
        ? "stable"
        : metric.delta > 0
          ? "up"
          : "down",
    month_over_month: metric.delta,
    abnormal_flag: metric.abnormalFlag,
    reference_range: metric.referenceRange,
    related_record_ids: []
  };
}

function buildAnnualExamInsights(
  digest: NonNullable<ReturnType<typeof getAnnualExamDigest>>
): StructuredInsight[] {
  const insights: StructuredInsight[] = [];
  const highlightedMetrics = digest.metrics
    .filter((metric) =>
      ["body.bmi", "lipid.total_cholesterol", "lipid.ldl_c", "renal.creatinine", "glycemic.glucose"].includes(
        metric.metricCode
      )
    )
    .map((metric) =>
      buildEvidenceMetricFromAnnualDigest({
        ...metric,
        latestRecordedAt: digest.latestRecordedAt
      })
    );
  const improvedCodes = new Set(
    digest.metrics
      .filter((metric) => digest.improvedMetricLabels.includes(metric.shortLabel))
      .map((metric) => metric.metricCode)
  );

  if (digest.abnormalMetricLabels.length > 0) {
    insights.push({
      id: `doc::annual-exam::${digest.latestMeasurementSetId}::focus`,
      kind: "anomaly",
      title: `${digest.latestTitle} 仍提示代谢与血脂维度需要持续管理`,
      severity: "high",
      evidence: {
        summary: digest.highlightSummary,
        metrics: highlightedMetrics
      },
      possible_reason: "年度体检更像年度截面视角，提示基础代谢负荷和生活方式结果仍需继续管理。",
      suggested_action: digest.actionSummary,
      disclaimer:
        "非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断。"
    });
  }

  if (digest.improvedMetricLabels.length > 0) {
    insights.push({
      id: `doc::annual-exam::${digest.latestMeasurementSetId}::improving`,
      kind: "trend",
      title: `${digest.latestTitle} 相较上一年度已有部分改善`,
      severity: "positive",
      evidence: {
        summary: `与 ${digest.previousTitle ?? "上一年度体检"} 相比，${digest.improvedMetricLabels.join("、")} 已出现改善或回落。`,
        metrics: highlightedMetrics.filter((metric) => improvedCodes.has(metric.metric_code))
      },
      possible_reason: "近期体重、体脂和血脂专项复查结果的联动变化，可能已经在年度体检层面体现出部分回落。",
      suggested_action: "继续保留当前有效的饮食、训练和复查节奏，避免只看短期一次结果。",
      disclaimer:
        "非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断。"
    });
  }

  return insights;
}

function buildGeneticInsights(
  findings: ReturnType<typeof listGeneticFindingDigests>
): StructuredInsight[] {
  return findings.map((finding) => ({
    id: `doc::genetic::${finding.id}`,
    kind: "correlation",
    title:
      finding.traitCode === "lipid.lpa_background"
        ? "基因背景支持把 Lp(a) 作为长期追踪维度"
        : finding.riskLevel === "high"
          ? `${finding.traitLabel} 适合作为长期重点背景`
          : `${finding.traitLabel} 可作为个体差异背景信息`,
    severity: finding.riskLevel === "high" ? "medium" : "low",
    evidence: {
      summary: finding.linkedMetric
        ? `${finding.summary} 当前最新 ${finding.linkedMetric.metricName} 为 ${finding.linkedMetric.value} ${finding.linkedMetric.unit}。`
        : finding.summary,
      metrics: finding.linkedMetric
        ? [
            {
              metric_code: finding.linkedMetric.metricCode,
              metric_name: finding.linkedMetric.metricName,
              unit: finding.linkedMetric.unit,
              latest_value: finding.linkedMetric.value,
              latest_sample_time: finding.linkedMetric.sampleTime,
              sample_count: 1,
              abnormal_flag: finding.linkedMetric.abnormalFlag,
              related_record_ids: []
            }
          ]
        : []
    },
    possible_reason:
      "这类基因结果更适合放在长期观察中，用来解释个体差异和长期倾向。",
    suggested_action: finding.suggestion,
    disclaimer:
      "非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断。"
  }));
}

function mergeInsights(
  base: StructuredInsightsResult,
  extraInsights: StructuredInsight[]
): StructuredInsightsResult {
  return {
    ...base,
    insights: [...extraInsights, ...base.insights]
  };
}

export function generateHolisticStructuredInsights(
  database: DatabaseSync,
  userId: string,
  options?: { asOf?: string }
): StructuredInsightsResult {
  const base = generateStructuredInsights(database, userId, options);
  const annualExam = getAnnualExamDigest(database, userId);
  const geneticFindings = listGeneticFindingDigests(database, userId);
  const extraInsights = [
    ...(annualExam ? buildAnnualExamInsights(annualExam) : []),
    ...buildGeneticInsights(geneticFindings)
  ];

  return mergeInsights(base, extraInsights);
}
