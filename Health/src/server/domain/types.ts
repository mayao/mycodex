export type MeasurementSetKind =
  | "annual_exam"
  | "lipid_panel"
  | "body_composition"
  | "activity_daily"
  | "sleep_daily"
  | "diet_daily"
  | "genetic_panel";

export type MetricCategory =
  | "body"
  | "lipid"
  | "glycemic"
  | "renal"
  | "activity"
  | "sleep"
  | "diet"
  | "genetics";

export type BetterDirection = "up" | "down" | "neutral";
export type AbnormalFlag = "low" | "normal" | "high" | "borderline" | "unknown";
export type CoverageStatus = "ready" | "demo" | "planned";
export type AttentionSeverity = "attention" | "watch" | "positive";
export type KpiTone = "attention" | "positive" | "neutral";

export interface UserSeed {
  id: string;
  displayName: string;
  sex: "male" | "female" | "other";
  birthYear: number;
  heightCm: number;
  note?: string;
}

export interface DataSourceSeed {
  id: string;
  sourceType: string;
  name: string;
  vendor?: string;
  ingestChannel: "file" | "manual" | "mock";
  note?: string;
}

export interface MetricCatalogItem {
  code: string;
  label: string;
  shortLabel: string;
  category: MetricCategory;
  defaultUnit: string;
  betterDirection: BetterDirection;
  normalLow?: number;
  normalHigh?: number;
  referenceText?: string;
  description: string;
}

export interface MeasurementSeed {
  metricCode: string;
  value: number;
  unit: string;
  normalizedValue?: number;
  normalizedUnit?: string;
  referenceLow?: number;
  referenceHigh?: number;
  abnormalFlag?: AbnormalFlag;
  note?: string;
  rawValue?: string;
}

export interface MeasurementSetSeed {
  id: string;
  sourceId: string;
  kind: MeasurementSetKind;
  title: string;
  recordedAt: string;
  reportDate?: string;
  note?: string;
  rawPayload?: Record<string, unknown>;
  measurements: MeasurementSeed[];
}

export interface GeneticFindingSeed {
  id: string;
  sourceId: string;
  geneSymbol: string;
  variantId: string;
  traitCode: string;
  riskLevel: "low" | "medium" | "high";
  evidenceLevel: "A" | "B" | "C";
  summary: string;
  suggestion: string;
  recordedAt: string;
  rawPayload?: Record<string, unknown>;
}

export interface LatestMetric {
  metricCode: string;
  label: string;
  shortLabel: string;
  value: number;
  unit: string;
  recordedAt: string;
  setKind: MeasurementSetKind;
  setTitle: string;
}

export interface CoverageItem {
  kind: MeasurementSetKind;
  label: string;
  count: number;
  latestRecordedAt: string | null;
  status: CoverageStatus;
  detail: string;
}

export interface DashboardMetricCard {
  id: string;
  label: string;
  value: string;
  detail: string;
  tone: KpiTone;
}

export interface DashboardAttentionItem {
  id: string;
  severity: AttentionSeverity;
  title: string;
  summary: string;
  source: string;
  disclaimer: string;
}

export interface TrendPoint {
  date: string;
  [key: string]: number | string | undefined;
}

export interface DashboardData {
  generatedAt: string;
  disclaimer: string;
  kpis: DashboardMetricCard[];
  attentionItems: DashboardAttentionItem[];
  coverage: CoverageItem[];
  trends: {
    bodyComposition: TrendPoint[];
    lipid: TrendPoint[];
    activity: TrendPoint[];
    sleep: TrendPoint[];
  };
}

export interface RuleInput {
  latestMetrics: Record<string, LatestMetric | undefined>;
  trends: DashboardData["trends"];
}
