import type {
  HealthDimensionAnalysis,
  HealthOverviewDigest,
  HealthReminderItem,
  HealthReportSnapshotRecord,
  HealthSummaryGenerationResult,
  HealthSummarySectionedOutput
} from "../domain/health-hub";

const hardDropPatterns = [
  /systemprompt/i,
  /userprompt/i,
  /开发提示/,
  /调试提示/,
  /输出必须是合法\s*json/i,
  /严格满足给定字段/,
  /你是健康管理产品中的总结层/,
  /不要编造新的化验值/,
  /现有结构化 insights/i,
  /不做诊断.*不制造恐慌/,
  /语气要求.*专业.*克制/,
  /生成一份.*健康总结/,
  /输出\s*JSON\s*结构/i,
  /结构化输入\s*JSON/i,
  /只使用下方\s*JSON/i
] as const;

const metaKeywords = [
  "prompt",
  "系统提示",
  "开发",
  "给用户看",
  "删除",
  "泛泛结论",
  "只给一个",
  "这套首页",
  "这份首页",
  "这个首页",
  "调试",
  "不再只给",
  "而是按",
  "编造",
  "合法 json",
  "JSON 结构"
] as const;

function normalizeWhitespace(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function isMetaClause(value: string): boolean {
  const normalized = normalizeWhitespace(value);

  if (!normalized) {
    return true;
  }

  if (hardDropPatterns.some((pattern) => pattern.test(normalized))) {
    return true;
  }

  const lowerCased = normalized.toLowerCase();

  if (metaKeywords.some((keyword) => lowerCased.includes(keyword.toLowerCase()))) {
    return true;
  }

  if (
    (normalized.includes("首页") || normalized.includes("总览") || normalized.includes("模块")) &&
    ["提示", "结论", "prompt", "系统", "开发"].some((keyword) => lowerCased.includes(keyword.toLowerCase()))
  ) {
    return true;
  }

  return false;
}

export function sanitizeText(value: string | undefined, fallback = ""): string {
  const normalized = normalizeWhitespace(value ?? "");

  if (!normalized) {
    return fallback;
  }

  const directReplacements: Array<[RegExp, string]> = [
    [/(?:这套|这份|这个)?首页现在不再只给一个泛泛结论[，,、；;:：]?/g, ""],
    [/(?:这套|这份|这个)?总览现在不再只给一个泛泛结论[，,、；;:：]?/g, ""],
    [/(?:这套|这份|这个)?首页不再只给.*?[，,、；;:：]/g, ""],
    [/(?:这套|这份|这个)?总览不再只给.*?[，,、；;:：]/g, ""],
    [/而是按.*?(?:分开看|分维度|拆开)[，,、；;:：]?/g, ""]
  ];
  const directCleaned = directReplacements.reduce(
    (result, [pattern, replacement]) => result.replace(pattern, replacement),
    normalized
  );

  const cleanedSentences = directCleaned
    .split(/[\n。！？；]/)
    .map((sentence) =>
      sentence
        .split(/[，,]/)
        .map((clause) => normalizeWhitespace(clause))
        .filter((clause) => clause.length > 0 && !isMetaClause(clause))
        .join("，")
    )
    .filter(Boolean);

  const cleaned = normalizeWhitespace(cleanedSentences.join("。")).replace(/^(而是|并且)\s*/, "");
  return cleaned || fallback;
}

function sanitizeList(items: string[], fallback?: string[]): string[] {
  const cleaned = [
    ...new Set(
      items
        .map((item) => sanitizeText(item))
        .map((item) => normalizeWhitespace(item))
        .filter(Boolean)
    )
  ];

  if (cleaned.length > 0) {
    return cleaned;
  }

  return fallback ? [...new Set(fallback.map((item) => sanitizeText(item)).filter(Boolean))] : [];
}

function sanitizeSummaryOutput(output: HealthSummarySectionedOutput): HealthSummarySectionedOutput {
  return {
    ...output,
    headline: sanitizeText(output.headline, "当前摘要已更新。"),
    most_important_changes: sanitizeList(output.most_important_changes, ["当前没有新的高优先级变化。"]),
    possible_reasons: sanitizeList(output.possible_reasons, ["现有结构化证据不足以支持进一步判断。"]),
    priority_actions: sanitizeList(output.priority_actions, ["继续记录关键指标，并按计划复查。"]),
    continue_observing: sanitizeList(output.continue_observing, ["继续观察关键趋势是否稳定延续。"]),
    disclaimer: sanitizeText(output.disclaimer, output.disclaimer)
  };
}

export function sanitizeHealthSummary(
  summary: HealthSummaryGenerationResult
): HealthSummaryGenerationResult {
  return {
    ...summary,
    output: sanitizeSummaryOutput(summary.output)
  };
}

export function sanitizeOverviewDigest(digest: HealthOverviewDigest): HealthOverviewDigest {
  return {
    ...digest,
    headline: sanitizeText(digest.headline, "当前趋势已更新，请结合重点变化继续观察。"),
    summary: sanitizeText(digest.summary, "近期趋势已更新，建议结合关注点和下一步行动继续跟踪。"),
    goodSignals: sanitizeList(digest.goodSignals),
    needsAttention: sanitizeList(digest.needsAttention),
    longTermRisks: sanitizeList(digest.longTermRisks),
    actionPlan: sanitizeList(digest.actionPlan)
  };
}

export function sanitizeDimensionAnalyses(
  analyses: HealthDimensionAnalysis[]
): HealthDimensionAnalysis[] {
  return analyses.map((analysis) => ({
    ...analysis,
    summary: sanitizeText(analysis.summary, analysis.title),
    goodSignals: sanitizeList(analysis.goodSignals),
    needsAttention: sanitizeList(analysis.needsAttention),
    longTermRisks: sanitizeList(analysis.longTermRisks),
    actionPlan: sanitizeList(analysis.actionPlan),
    metrics: analysis.metrics.map((metric) => ({
      ...metric,
      detail: sanitizeText(metric.detail, metric.label)
    }))
  }));
}

export function sanitizeReminderItems(items: HealthReminderItem[]): HealthReminderItem[] {
  return items.map((item) => ({
    ...item,
    title: sanitizeText(item.title, item.title),
    summary: sanitizeText(item.summary, item.title),
    suggested_action: sanitizeText(item.suggested_action, "继续观察并按计划处理。"),
    indicatorMeaning: item.indicatorMeaning
      ? sanitizeText(item.indicatorMeaning, item.indicatorMeaning)
      : undefined,
    practicalAdvice: item.practicalAdvice
      ? sanitizeText(item.practicalAdvice, item.practicalAdvice)
      : undefined
  }));
}

export function sanitizeReportSnapshot(
  report: HealthReportSnapshotRecord
): HealthReportSnapshotRecord {
  return {
    ...report,
    title: sanitizeText(report.title, report.title),
    summary: sanitizeHealthSummary(report.summary)
  };
}
