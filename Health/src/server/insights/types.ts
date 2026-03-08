export type StructuredInsightSeverity = "positive" | "low" | "medium" | "high";
export type StructuredInsightKind = "trend" | "anomaly" | "correlation";
export type TrendDirection = "up" | "down" | "stable";

export interface MetricSummary {
  metric_code: string;
  metric_name: string;
  category: string;
  unit: string;
  sample_count: number;
  latest_value: number;
  latest_sample_time: string;
  historical_mean?: number;
  latest_vs_mean?: number;
  latest_vs_mean_pct?: number;
  trend_direction?: TrendDirection;
  month_over_month?: number;
  year_over_year?: number;
  abnormal_flag: string;
  reference_range?: string | null;
}

export interface StructuredInsightEvidenceMetric {
  metric_code: string;
  metric_name: string;
  unit: string;
  latest_value: number;
  latest_sample_time: string;
  sample_count: number;
  historical_mean?: number;
  latest_vs_mean?: number;
  latest_vs_mean_pct?: number;
  trend_direction?: TrendDirection;
  month_over_month?: number;
  year_over_year?: number;
  abnormal_flag?: string;
  reference_range?: string | null;
  related_record_ids: string[];
}

export interface StructuredInsightEvidence {
  summary: string;
  metrics: StructuredInsightEvidenceMetric[];
}

export interface StructuredInsight {
  id: string;
  kind: StructuredInsightKind;
  title: string;
  severity: StructuredInsightSeverity;
  evidence: StructuredInsightEvidence;
  possible_reason: string;
  suggested_action: string;
  disclaimer: string;
}

export interface StructuredInsightsResult {
  generated_at: string;
  user_id: string;
  metric_summaries: MetricSummary[];
  insights: StructuredInsight[];
}
