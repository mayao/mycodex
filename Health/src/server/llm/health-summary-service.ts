import { NON_DIAGNOSTIC_DISCLAIMER } from "../../data/mock/seed-data";
import { getAppEnv } from "../config/env";
import { getProviderPriority } from "../services/llm-provider-routing";
import type {
  HealthSummaryGenerationResult,
  HealthSummaryPeriod,
  HealthSummarySectionedOutput,
  HealthSummarySourceInput
} from "../domain/health-hub";
import type { StructuredInsight, StructuredInsightsResult } from "../insights/types";
import {
  toEndOfAppDayTimestamp,
  toStartOfAppDayTimestamp
} from "../utils/app-time";
import { buildHealthSummaryPrompt } from "./prompt-templates";
import {
  AnthropicHealthSummaryProvider,
  MockHealthSummaryProvider,
  OpenAICompatibleHealthSummaryProvider,
  type HealthSummaryProvider
} from "./providers";

const defaultFocusMetricCodes = [
  "lipid.ldl_c",
  "lipid.triglycerides",
  "lipid.hdl_c",
  "lipid.total_cholesterol",
  "lipid.apob",
  "body.weight",
  "body.body_fat_pct",
  "activity.exercise_minutes"
];

const severityWeight: Record<StructuredInsight["severity"], number> = {
  high: 4,
  medium: 3,
  low: 2,
  positive: 1
};

function uniqueStrings(values: string[], limit: number): string[] {
  const unique = [...new Set(values.map((value) => value.trim()).filter(Boolean))];
  return unique.slice(0, limit);
}

function periodLimit(kind: HealthSummaryPeriod["kind"]): number {
  if (kind === "day") {
    return 2;
  }

  if (kind === "week") {
    return 3;
  }

  return 4;
}

function toTimestamp(value: string): number {
  return new Date(value).getTime();
}

function selectInsightsForPeriod(
  structuredInsights: StructuredInsightsResult,
  period: HealthSummaryPeriod
): {
  primary: StructuredInsight[];
  secondary: StructuredInsight[];
} {
  const startTs = toStartOfAppDayTimestamp(period.start);
  const endTs = toEndOfAppDayTimestamp(period.end);

  const scored = structuredInsights.insights.map((insight) => {
    const latestMetricTs = Math.max(
      ...insight.evidence.metrics
        .map((metric) => toTimestamp(metric.latest_sample_time))
        .filter((value) => Number.isFinite(value)),
      0
    );
    const fallsWithinPeriod = latestMetricTs >= startTs && latestMetricTs <= endTs;
    return {
      insight,
      latestMetricTs,
      fallsWithinPeriod,
      score:
        severityWeight[insight.severity] * 100 +
        (fallsWithinPeriod ? 20 : 0) +
        Math.floor(latestMetricTs / 100000000)
    };
  });

  const primary = scored
    .filter((item) => item.fallsWithinPeriod || severityWeight[item.insight.severity] >= 3)
    .sort((left, right) => right.score - left.score)
    .map((item) => item.insight)
    .slice(0, periodLimit(period.kind));

  const primaryIds = new Set(primary.map((item) => item.id));

  const secondary = scored
    .filter((item) => !primaryIds.has(item.insight.id))
    .sort((left, right) => right.score - left.score)
    .map((item) => item.insight)
    .slice(0, periodLimit(period.kind) + 1);

  return {
    primary,
    secondary
  };
}

function isDocumentInsight(insight: StructuredInsight): boolean {
  return insight.id.startsWith("doc::");
}

export function buildFallbackSummary(
  input: HealthSummarySourceInput
): HealthSummarySectionedOutput {
  const limit = periodLimit(input.period.kind);
  const { primary, secondary } = selectInsightsForPeriod(
    {
      generated_at: input.generated_at,
      user_id: "summary-only",
      metric_summaries: input.metric_summaries,
      insights: input.structured_insights
    },
    input.period
  );

  if (primary.length === 0) {
    return {
      period_kind: input.period.kind,
      headline: `${input.period.label}没有出现新的高优先级变化，建议继续记录并观察趋势是否延续。`,
      most_important_changes: ["现有结构化证据未提示新的高优先级变化。"],
      possible_reasons: ["现有结构化证据不足以支持进一步判断。"],
      priority_actions: ["继续按当前节奏记录关键指标，并按计划复查。"],
      continue_observing: ["持续观察血脂、体重、体脂率和运动执行度的联动变化。"],
      disclaimer: NON_DIAGNOSTIC_DISCLAIMER
    };
  }

  const contextualInsights = [...primary, ...secondary].filter((insight) => isDocumentInsight(insight));
  const operationalInsights = primary.filter((insight) => !isDocumentInsight(insight));
  const featuredInsights = uniqueStrings(
    [
      ...operationalInsights
        .slice(0, Math.max(limit - (contextualInsights.length > 0 ? 1 : 0), 1))
        .map((insight) => `${insight.title}：${insight.evidence.summary}`),
      ...contextualInsights.slice(0, 1).map((insight) => `${insight.title}：${insight.evidence.summary}`)
    ],
    limit
  );

  const mostImportantChanges = featuredInsights;
  const possibleReasons = uniqueStrings(
    [...operationalInsights, ...contextualInsights].map((insight) => insight.possible_reason),
    limit
  );
  const priorityActions = uniqueStrings(
    [...operationalInsights, ...contextualInsights].map((insight) => insight.suggested_action),
    limit
  );
  const continueObserving = uniqueStrings(
    secondary
      .map((insight) => `${insight.title}：${insight.evidence.summary}`)
      .concat(
        input.summary_focus.length > 0
          ? [`继续围绕 ${input.summary_focus.join("、")} 保持连续观察。`]
          : []
      ),
    limit
  );
  const topInsight = operationalInsights[0] ?? primary[0];
  const contextInsight = contextualInsights[0];
  const headline =
    topInsight.severity === "positive"
      ? `${input.period.label}出现了积极变化，建议继续当前节奏并确认趋势是否稳定。${contextInsight ? ` 同时也要兼顾${contextInsight.title}。` : ""}`
      : `${input.period.label}重点关注${topInsight.title.replace(/最近一次|连续 \d+ 次/g, "").trim()}，建议继续跟踪并落实下一步行动。${contextInsight ? ` 同时也要兼顾${contextInsight.title}。` : ""}`;

  return {
    period_kind: input.period.kind,
    headline,
    most_important_changes: mostImportantChanges,
    possible_reasons: possibleReasons.length > 0 ? possibleReasons : ["现有结构化证据不足以支持进一步判断。"],
    priority_actions: priorityActions.length > 0 ? priorityActions : ["继续保持关键指标记录与定期复查。"],
    continue_observing: continueObserving.length > 0 ? continueObserving : ["继续观察当前高优先级指标是否持续改善或继续异常。"],
    disclaimer: NON_DIAGNOSTIC_DISCLAIMER
  };
}

function sortInsightsForPrompt(insights: StructuredInsight[]): StructuredInsight[] {
  return [...insights].sort((left, right) => {
    const severityGap = severityWeight[right.severity] - severityWeight[left.severity];

    if (severityGap !== 0) {
      return severityGap;
    }

    return left.title.localeCompare(right.title);
  });
}

export function buildHealthSummarySourceInput(
  structuredInsights: StructuredInsightsResult,
  period: HealthSummaryPeriod
): HealthSummarySourceInput {
  const { primary, secondary } = selectInsightsForPeriod(structuredInsights, period);
  const selectedInsights = sortInsightsForPrompt([...primary, ...secondary]).slice(0, 10);
  const referencedMetricCodes = new Set(
    selectedInsights.flatMap((insight) => insight.evidence.metrics.map((metric) => metric.metric_code))
  );

  for (const metricCode of defaultFocusMetricCodes) {
    referencedMetricCodes.add(metricCode);
  }

  const metricSummaries = structuredInsights.metric_summaries.filter((summary) =>
    referencedMetricCodes.has(summary.metric_code)
  );

  return {
    generated_at: structuredInsights.generated_at,
    period,
    summary_focus: uniqueStrings(
      selectedInsights.map((insight) => insight.title).concat(defaultFocusMetricCodes.slice(0, 3)),
      6
    ),
    structured_insights: selectedInsights,
    metric_summaries: metricSummaries
  };
}

export function resolveHealthSummaryProvider(): HealthSummaryProvider {
  const env = getAppEnv();
  const providerPriority = getProviderPriority(env);

  if (providerPriority.includes("anthropic") && env.HEALTH_LLM_API_KEY) {
    return new AnthropicHealthSummaryProvider({
      apiKey: env.HEALTH_LLM_API_KEY,
      model: env.HEALTH_LLM_MODEL ?? "claude-opus-4-6"
    });
  }

  if (
    providerPriority.includes("openai_compatible") &&
    env.HEALTH_LLM_API_KEY &&
    env.HEALTH_LLM_BASE_URL
  ) {
    return new OpenAICompatibleHealthSummaryProvider({
      apiKey: env.HEALTH_LLM_API_KEY,
      baseUrl: env.HEALTH_LLM_BASE_URL,
      model: env.HEALTH_LLM_MODEL ?? "gpt-4.1-mini"
    });
  }

  return new MockHealthSummaryProvider();
}

export async function generateHealthSummaryFromStructuredInsights(
  structuredInsights: StructuredInsightsResult,
  period: HealthSummaryPeriod,
  provider: HealthSummaryProvider = resolveHealthSummaryProvider()
): Promise<HealthSummaryGenerationResult> {
  const sourceInput = buildHealthSummarySourceInput(structuredInsights, period);
  const fallback = buildFallbackSummary(sourceInput);
  const prompt = buildHealthSummaryPrompt(sourceInput);

  return provider.generate({
    prompt,
    periodKind: period.kind,
    fallback
  });
}
