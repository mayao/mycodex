import type { StructuredInsight, StructuredInsightSeverity, StructuredInsightsResult } from "../insights/types";
import type { TrendPoint } from "./types";

export type SummaryPeriodKind = "day" | "week" | "month";
export type NarrativeProviderKind = "mock" | "openai-compatible";
export type TrendRangeKey = "30d" | "90d" | "1y" | "all";
export type ReportKind = "weekly" | "monthly";

export interface HealthSummaryPeriod {
  kind: SummaryPeriodKind;
  label: string;
  start: string;
  end: string;
  asOf: string;
}

export interface HealthSummaryPromptBundle {
  templateId: string;
  version: string;
  systemPrompt: string;
  userPrompt: string;
}

export interface HealthSummarySectionedOutput {
  period_kind: SummaryPeriodKind;
  headline: string;
  most_important_changes: string[];
  possible_reasons: string[];
  priority_actions: string[];
  continue_observing: string[];
  disclaimer: string;
}

export interface HealthSummaryGenerationResult {
  provider: NarrativeProviderKind;
  model: string;
  prompt: HealthSummaryPromptBundle;
  output: HealthSummarySectionedOutput;
}

export interface HealthSummarySourceInput {
  generated_at: string;
  period: HealthSummaryPeriod;
  summary_focus: string[];
  structured_insights: StructuredInsight[];
  metric_summaries: StructuredInsightsResult["metric_summaries"];
}

export interface HealthOverviewCard {
  metric_code: string;
  label: string;
  value: string;
  trend: string;
  status: "improving" | "watch" | "stable";
  abnormal_flag: string;
  meaning?: string;
}

export interface HealthReminderItem {
  id: string;
  title: string;
  severity: StructuredInsightSeverity;
  summary: string;
  suggested_action: string;
  indicatorMeaning?: string;
  practicalAdvice?: string;
}

export interface HealthSourceDimensionCard {
  key: string;
  label: string;
  latestAt?: string;
  status: "ready" | "attention" | "background";
  summary: string;
  highlight: string;
}

export interface HealthOverviewSpotlight {
  label: string;
  value: string;
  tone: "positive" | "attention" | "neutral";
  detail: string;
}

export interface AnnualExamMetricView {
  metricCode: string;
  label: string;
  shortLabel: string;
  unit: string;
  latestValue: number;
  previousValue?: number;
  delta?: number;
  abnormalFlag: string;
  referenceRange?: string;
  meaning?: string;
  practicalAdvice?: string;
}

export interface AnnualExamView {
  latestTitle: string;
  latestRecordedAt: string;
  previousTitle?: string;
  metrics: AnnualExamMetricView[];
  abnormalMetricLabels: string[];
  improvedMetricLabels: string[];
  highlightSummary: string;
  actionSummary: string;
}

export interface GeneticFindingView {
  id: string;
  geneSymbol: string;
  traitLabel: string;
  dimension: string;
  riskLevel: "low" | "medium" | "high";
  evidenceLevel: "A" | "B" | "C";
  summary: string;
  suggestion: string;
  recordedAt: string;
  linkedMetricLabel?: string;
  linkedMetricValue?: string;
  linkedMetricFlag?: string;
  plainMeaning?: string;
  practicalAdvice?: string;
}

export interface HealthTrendLine {
  key: string;
  label: string;
  color: string;
  unit: string;
  yAxisId?: "left" | "right";
}

export interface HealthTrendChartModel {
  title: string;
  description: string;
  defaultRange: TrendRangeKey;
  data: TrendPoint[];
  lines: HealthTrendLine[];
}

export interface HealthReportSnapshotRecord {
  id: string;
  reportType: ReportKind;
  periodStart: string;
  periodEnd: string;
  createdAt: string;
  title: string;
  summary: HealthSummaryGenerationResult;
  structuredInsights: StructuredInsightsResult;
}

export interface HealthHomePageData {
  generatedAt: string;
  disclaimer: string;
  overviewHeadline: string;
  overviewNarrative: string;
  overviewFocusAreas: string[];
  overviewSpotlights: HealthOverviewSpotlight[];
  sourceDimensions: HealthSourceDimensionCard[];
  overviewCards: HealthOverviewCard[];
  annualExam?: AnnualExamView;
  geneticFindings: GeneticFindingView[];
  keyReminders: HealthReminderItem[];
  watchItems: HealthReminderItem[];
  latestNarrative: HealthSummaryGenerationResult;
  charts: {
    lipid: HealthTrendChartModel;
    bodyComposition: HealthTrendChartModel;
    activity: HealthTrendChartModel;
    recovery: HealthTrendChartModel;
  };
  latestReports: HealthReportSnapshotRecord[];
}

export interface ReportsIndexData {
  generatedAt: string;
  weeklyReports: HealthReportSnapshotRecord[];
  monthlyReports: HealthReportSnapshotRecord[];
}
