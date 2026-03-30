import type { DatabaseSync } from "node:sqlite";

type RiskLevel = "low" | "medium" | "high";
type EvidenceLevel = "A" | "B" | "C";
type AbnormalFlag = "low" | "normal" | "high" | "borderline" | "unknown";
type BetterDirection = "up" | "down" | "neutral";

const annualExamMetricMeta: Record<
  string,
  {
    label: string;
    shortLabel: string;
    betterDirection: BetterDirection;
  }
> = {
  "body.bmi": { label: "BMI", shortLabel: "BMI", betterDirection: "down" },
  "body.weight": { label: "体重", shortLabel: "体重", betterDirection: "down" },
  "glycemic.glucose": { label: "血糖", shortLabel: "血糖", betterDirection: "down" },
  "lipid.total_cholesterol": { label: "总胆固醇", shortLabel: "TC", betterDirection: "down" },
  "lipid.ldl_c": { label: "低密度脂蛋白胆固醇", shortLabel: "LDL-C", betterDirection: "down" },
  "lipid.hdl_c": { label: "高密度脂蛋白胆固醇", shortLabel: "HDL-C", betterDirection: "up" },
  "lipid.triglycerides": { label: "甘油三酯", shortLabel: "TG", betterDirection: "down" },
  "renal.creatinine": { label: "肌酐", shortLabel: "肌酐", betterDirection: "down" },
  "renal.uric_acid": { label: "尿酸", shortLabel: "尿酸", betterDirection: "down" }
};

const annualExamMetricOrder = [
  "body.bmi",
  "body.weight",
  "glycemic.glucose",
  "lipid.total_cholesterol",
  "lipid.ldl_c",
  "renal.creatinine",
  "renal.uric_acid"
];

const geneTraitMeta: Record<
  string,
  {
    label: string;
    dimension: string;
    linkedMetricCode?: string;
  }
> = {
  "lipid.lpa_background": {
    label: "Lp(a) 背景倾向",
    dimension: "血脂与遗传背景",
    linkedMetricCode: "lipid.lpa"
  },
  "lipid.ldl_clearance_response": {
    label: "LDL-C 清除敏感性",
    dimension: "血脂与颗粒管理",
    linkedMetricCode: "lipid.ldl_c"
  },
  "body.weight_regain_tendency": {
    label: "体脂反弹敏感性",
    dimension: "体重与代谢弹性",
    linkedMetricCode: "body.body_fat_pct"
  },
  "glycemic.postprandial_response": {
    label: "餐后血糖敏感性",
    dimension: "血糖与代谢弹性",
    linkedMetricCode: "glycemic.glucose"
  },
  "sleep.caffeine_sensitivity": {
    label: "咖啡因敏感性",
    dimension: "睡眠与恢复",
    linkedMetricCode: "sleep.asleep_minutes"
  },
  "activity.endurance_response": {
    label: "耐力训练响应",
    dimension: "运动适应与恢复",
    linkedMetricCode: "activity.exercise_minutes"
  }
};

interface AnnualExamMetricRow {
  measurementSetId: string;
  title: string;
  recordedAt: string;
  reportDate: string | null;
  metricCode: string;
  value: number;
  unit: string;
  abnormalFlag: AbnormalFlag;
  referenceLow: number | null;
  referenceHigh: number | null;
}

interface GeneticFindingRow {
  id: string;
  geneSymbol: string;
  traitCode: string;
  riskLevel: RiskLevel;
  evidenceLevel: EvidenceLevel;
  summary: string;
  suggestion: string;
  recordedAt: string;
}

interface LinkedMetricRow {
  metricCode: string;
  metricName: string;
  normalizedValue: number;
  unit: string;
  abnormalFlag: string;
  sampleTime: string;
}

export interface AnnualExamMetricDigest {
  metricCode: string;
  label: string;
  shortLabel: string;
  unit: string;
  betterDirection: BetterDirection;
  latestValue: number;
  previousValue?: number;
  delta?: number;
  abnormalFlag: AbnormalFlag;
  referenceRange?: string;
}

export interface AnnualExamDigest {
  latestMeasurementSetId: string;
  latestTitle: string;
  latestRecordedAt: string;
  previousMeasurementSetId?: string;
  previousTitle?: string;
  previousRecordedAt?: string;
  metrics: AnnualExamMetricDigest[];
  abnormalMetricLabels: string[];
  improvedMetricLabels: string[];
  highlightSummary: string;
  actionSummary: string;
}

export interface GeneticFindingDigest {
  id: string;
  geneSymbol: string;
  traitCode: string;
  traitLabel: string;
  dimension: string;
  riskLevel: RiskLevel;
  evidenceLevel: EvidenceLevel;
  summary: string;
  suggestion: string;
  recordedAt: string;
  linkedMetric?: {
    metricCode: string;
    metricName: string;
    value: number;
    unit: string;
    abnormalFlag: string;
    sampleTime: string;
  };
}

function formatReferenceRange(low: number | null, high: number | null): string | undefined {
  if (typeof low === "number" && typeof high === "number") {
    return `${low} - ${high}`;
  }

  if (typeof low === "number") {
    return `>= ${low}`;
  }

  if (typeof high === "number") {
    return `<= ${high}`;
  }

  return undefined;
}

function round(value: number | undefined, digits = 2): number | undefined {
  return typeof value === "number" ? Number(value.toFixed(digits)) : undefined;
}

function isImproved(metric: AnnualExamMetricDigest): boolean {
  if (typeof metric.delta !== "number" || metric.delta === 0) {
    return false;
  }

  if (metric.betterDirection === "down") {
    return metric.delta < 0;
  }

  if (metric.betterDirection === "up") {
    return metric.delta > 0;
  }

  return false;
}

function summarizeAnnualExam(digest: AnnualExamDigest): AnnualExamDigest {
  const abnormalPart =
    digest.abnormalMetricLabels.length > 0
      ? `${digest.latestTitle} 仍需重点关注 ${digest.abnormalMetricLabels.join("、")}。`
      : `${digest.latestTitle} 核心指标未出现新的高优先异常。`;
  const improvementPart =
    digest.improvedMetricLabels.length > 0
      ? `相较 ${digest.previousTitle ?? "上一年度"}，${digest.improvedMetricLabels.join("、")} 已出现回落或改善。`
      : "与上一年度相比，核心指标整体波动不大。";

  return {
    ...digest,
    highlightSummary: `${abnormalPart}${improvementPart}`,
    actionSummary:
      digest.abnormalMetricLabels.length > 0
        ? `建议继续把 ${digest.abnormalMetricLabels.join("、")} 作为下一轮复查和生活方式跟踪重点。`
        : "建议保持年度体检节奏，并继续把血脂、体重和代谢指标按周期复查。"
  };
}

function parseReferenceRange(range: string | null): { low: number | null; high: number | null } {
  if (!range) return { low: null, high: null };
  // Normalize: strip unit suffixes like "mmol/L", "kg/m2" etc.
  const cleaned = range.replace(/[a-zA-Z/%°·]+$/g, "").trim();
  // Pattern: "3.9 - 6.09"
  const dashMatch = cleaned.match(/^([\d.]+)\s*[-–—]\s*([\d.]+)/);
  if (dashMatch) return { low: parseFloat(dashMatch[1]), high: parseFloat(dashMatch[2]) };
  // Pattern: ">= 1.04" or "> 1.04"
  const geMatch = cleaned.match(/^>=?\s*([\d.]+)/);
  if (geMatch) return { low: parseFloat(geMatch[1]), high: null };
  // Pattern: "<= 3.4" or "< 3.4"
  const leMatch = cleaned.match(/^<=?\s*([\d.]+)/);
  if (leMatch) return { low: null, high: parseFloat(leMatch[1]) };
  return { low: null, high: null };
}

function loadAnnualExamRows(
  database: DatabaseSync,
  userId: string
): AnnualExamMetricRow[] {
  const rawRows = database
    .prepare(
      `
      SELECT
        mr.data_source_id AS dataSourceId,
        COALESCE(ds.source_name, '体检报告') AS title,
        mr.sample_time AS recordedAt,
        mr.sample_time AS reportDate,
        mr.metric_code AS metricCode,
        mr.normalized_value AS value,
        mr.unit,
        mr.abnormal_flag AS abnormalFlag,
        mr.reference_range AS referenceRange
      FROM metric_record mr
      LEFT JOIN data_source ds ON ds.id = mr.data_source_id AND ds.user_id = mr.user_id
      WHERE mr.user_id = ?
        AND mr.source_type IN ('annual_exam_tabular', 'annual_exam_pdf')
      ORDER BY mr.sample_time DESC, mr.metric_code ASC
    `
    )
    .all(userId) as unknown as Array<{
      dataSourceId: string;
      title: string;
      recordedAt: string;
      reportDate: string | null;
      metricCode: string;
      value: number;
      unit: string;
      abnormalFlag: AbnormalFlag;
      referenceRange: string | null;
    }>;

  return rawRows.map((row) => {
    const ref = parseReferenceRange(row.referenceRange);
    return {
      measurementSetId: row.dataSourceId,
      title: row.title,
      recordedAt: row.recordedAt,
      reportDate: row.reportDate,
      metricCode: row.metricCode,
      value: row.value,
      unit: row.unit,
      abnormalFlag: row.abnormalFlag,
      referenceLow: ref.low,
      referenceHigh: ref.high
    };
  });
}

export function getAnnualExamDigest(
  database: DatabaseSync,
  userId: string
): AnnualExamDigest | undefined {
  const rows = loadAnnualExamRows(database, userId);

  if (rows.length === 0) {
    return undefined;
  }

  const bySet = new Map<string, AnnualExamMetricRow[]>();

  for (const row of rows) {
    const current = bySet.get(row.measurementSetId) ?? [];
    current.push(row);
    bySet.set(row.measurementSetId, current);
  }

  const sets = [...bySet.values()]
    .map((setRows) => ({
      measurementSetId: setRows[0].measurementSetId,
      title: setRows[0].title,
      recordedAt: setRows[0].recordedAt,
      metrics: Object.fromEntries(setRows.map((row) => [row.metricCode, row]))
    }))
    .sort((left, right) => right.recordedAt.localeCompare(left.recordedAt));

  const latest = sets[0];
  const previous = sets[1];
  const metrics: AnnualExamMetricDigest[] = [];

  for (const metricCode of annualExamMetricOrder) {
    const latestMetric = latest.metrics[metricCode];

    if (!latestMetric) {
      continue;
    }

    const previousMetric = previous?.metrics[metricCode];
    const meta = annualExamMetricMeta[metricCode];

    metrics.push({
      metricCode,
      label: meta?.label ?? metricCode,
      shortLabel: meta?.shortLabel ?? metricCode,
      unit: latestMetric.unit,
      betterDirection: meta?.betterDirection ?? "neutral",
      latestValue: latestMetric.value,
      previousValue: previousMetric?.value,
      delta:
        typeof previousMetric?.value === "number"
          ? round(latestMetric.value - previousMetric.value)
          : undefined,
      abnormalFlag: latestMetric.abnormalFlag,
      referenceRange: formatReferenceRange(
        latestMetric.referenceLow,
        latestMetric.referenceHigh
      )
    });
  }
  const abnormalMetricLabels = metrics
    .filter((metric) => metric.abnormalFlag === "high" || metric.abnormalFlag === "low")
    .map((metric) => metric.shortLabel);
  const improvedMetricLabels = metrics
    .filter((metric) => isImproved(metric))
    .map((metric) => metric.shortLabel);

  return summarizeAnnualExam({
    latestMeasurementSetId: latest.measurementSetId,
    latestTitle: latest.title,
    latestRecordedAt: latest.recordedAt,
    previousMeasurementSetId: previous?.measurementSetId,
    previousTitle: previous?.title,
    previousRecordedAt: previous?.recordedAt,
    metrics,
    abnormalMetricLabels,
    improvedMetricLabels,
    highlightSummary: "",
    actionSummary: ""
  });
}

function loadLinkedMetric(
  database: DatabaseSync,
  userId: string,
  metricCode: string
): LinkedMetricRow | undefined {
  return database
    .prepare(
      `
      SELECT
        metric_code AS metricCode,
        metric_name AS metricName,
        normalized_value AS normalizedValue,
        unit,
        abnormal_flag AS abnormalFlag,
        sample_time AS sampleTime
      FROM metric_record
      WHERE user_id = ? AND metric_code = ?
      ORDER BY sample_time DESC
      LIMIT 1
    `
    )
    .get(userId, metricCode) as LinkedMetricRow | undefined;
}

export function listGeneticFindingDigests(
  database: DatabaseSync,
  userId: string
): GeneticFindingDigest[] {
  const rows = database
    .prepare(
      `
      SELECT
        id,
        gene_symbol AS geneSymbol,
        trait_code AS traitCode,
        risk_level AS riskLevel,
        evidence_level AS evidenceLevel,
        summary,
        suggestion,
        recorded_at AS recordedAt
      FROM genetic_findings
      WHERE user_id = ?
      ORDER BY
        CASE risk_level
          WHEN 'high' THEN 3
          WHEN 'medium' THEN 2
          ELSE 1
        END DESC,
        recorded_at DESC
    `
    )
    .all(userId) as unknown as GeneticFindingRow[];

  return rows.map((row) => {
    const meta = geneTraitMeta[row.traitCode];
    const linkedMetric = meta?.linkedMetricCode
      ? loadLinkedMetric(database, userId, meta.linkedMetricCode)
      : undefined;

    return {
      id: row.id,
      geneSymbol: row.geneSymbol,
      traitCode: row.traitCode,
      traitLabel: meta?.label ?? row.traitCode,
      dimension: meta?.dimension ?? "遗传背景",
      riskLevel: row.riskLevel,
      evidenceLevel: row.evidenceLevel,
      summary: row.summary,
      suggestion: row.suggestion,
      recordedAt: row.recordedAt,
      linkedMetric: linkedMetric
        ? {
            metricCode: linkedMetric.metricCode,
            metricName: linkedMetric.metricName,
            value: linkedMetric.normalizedValue,
            unit: linkedMetric.unit,
            abnormalFlag: linkedMetric.abnormalFlag,
            sampleTime: linkedMetric.sampleTime
          }
        : undefined
    };
  });
}
