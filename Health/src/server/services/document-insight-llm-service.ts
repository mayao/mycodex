import { getAppEnv } from "../config/env";
import type { AnnualExamDigest } from "../repositories/document-insight-repository";
import type { GeneticFindingDigest } from "../repositories/document-insight-repository";

export interface AnnualExamInsightResult {
  generatedAt: string;
  examTitle: string;
  sections: {
    overview: string;
    attentionPoints: string[];
    improvements: string[];
    urgentIssues: string[];
    positiveSignals: string[];
  };
  disclaimer: string;
  provider: string;
  model: string;
}

export interface GeneticsInsightResult {
  generatedAt: string;
  sections: {
    overview: string;
    highRiskPoints: string[];
    healthCorrelations: string[];
    lifestyleAdvice: string[];
    longTermMonitoring: string[];
  };
  disclaimer: string;
  provider: string;
  model: string;
}

function buildAnnualExamPrompt(digest: AnnualExamDigest): string {
  const abnormalMetrics = digest.metrics
    .filter((m) => m.abnormalFlag === "high" || m.abnormalFlag === "low")
    .map((m) => `${m.label}: ${m.latestValue} ${m.unit} (异常: ${m.abnormalFlag === "high" ? "偏高" : "偏低"}${m.referenceRange ? ", 参考范围 " + m.referenceRange : ""}${typeof m.delta === "number" ? ", 较上次" + (m.delta > 0 ? "升" : "降") + Math.abs(m.delta).toFixed(2) + m.unit : ""})`);

  const normalMetrics = digest.metrics
    .filter((m) => m.abnormalFlag === "normal")
    .map((m) => `${m.label}: ${m.latestValue} ${m.unit}`);

  return [
    `体检报告：${digest.latestTitle}（${digest.latestRecordedAt.slice(0, 10)}）`,
    `\n异常指标（${abnormalMetrics.length} 项）：\n${abnormalMetrics.length > 0 ? abnormalMetrics.join("\n") : "无"}`,
    `\n正常指标：${normalMetrics.join(", ") || "无"}`,
    `\n上次对比：${digest.previousTitle ?? "无上次记录"}`,
    `已改善指标：${digest.improvedMetricLabels.join("、") || "无"}`,
    `\n请基于以上体检数据，提供结构化的健康洞察分析。用中文回答，结合实际数值给出具体可执行的建议。注意区分哪些问题需要立刻就医、哪些需要定期复查、哪些可通过生活方式干预改善。`
  ].join("\n");
}

function buildGeneticsPrompt(findings: GeneticFindingDigest[]): string {
  const highRisk = findings.filter((f) => f.riskLevel === "high");
  const mediumRisk = findings.filter((f) => f.riskLevel === "medium");

  const formatFinding = (f: GeneticFindingDigest) => {
    const linked = f.linkedMetric
      ? `，关联当前指标 ${f.linkedMetric.metricName}: ${f.linkedMetric.value} ${f.linkedMetric.unit}（${f.linkedMetric.abnormalFlag === "normal" ? "正常" : "异常"}）`
      : "";
    return `- ${f.traitLabel}（${f.geneSymbol}，${f.dimension}，证据级别${f.evidenceLevel}）：${f.summary}${linked}`;
  };

  return [
    `基因检测报告分析`,
    `\n高关注风险项（${highRisk.length} 条）：\n${highRisk.map(formatFinding).join("\n") || "无"}`,
    `\n中等风险项（${mediumRisk.length} 条）：\n${mediumRisk.map(formatFinding).join("\n") || "无"}`,
    `\n已关联到当前健康指标的基因项：${findings.filter((f) => f.linkedMetric).length} 条`,
    `\n请基于以上基因检测数据，提供深度洞察分析。重点说明：1）高风险基因位点的实际健康含义；2）与用户当前健康指标的关联和相互印证；3）基因背景下的个性化生活方式建议；4）哪些点需要长期监测。用中文回答，避免过度夸大遗传风险，强调基因只是背景因素，可通过干预改善。`
  ].join("\n");
}

async function callAnthropicForInsight(
  systemPrompt: string,
  userPrompt: string,
  apiKey: string,
  model: string
): Promise<{ content: string; model: string }> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01"
    },
    body: JSON.stringify({
      model,
      max_tokens: 2048,
      system: systemPrompt,
      messages: [{ role: "user", content: userPrompt }]
    })
  });

  if (!response.ok) {
    const errorBody = await response.text().catch(() => "");
    throw new Error(`Anthropic API failed with status ${response.status}: ${errorBody.slice(0, 200)}`);
  }

  const payload = (await response.json()) as {
    content?: Array<{ type: string; text?: string }>;
    model?: string;
  };

  const content = payload.content
    ?.filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("\n")
    .trim();

  if (!content) {
    throw new Error("Anthropic API returned empty content");
  }

  return { content, model: payload.model ?? model };
}

async function callOpenAICompatibleForInsight(
  systemPrompt: string,
  userPrompt: string,
  apiKey: string,
  baseUrl: string,
  model: string
): Promise<{ content: string; model: string }> {
  const response = await fetch(`${baseUrl.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model,
      temperature: 0.3,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt }
      ]
    })
  });

  if (!response.ok) {
    throw new Error(`LLM provider failed with status ${response.status}`);
  }

  const payload = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };

  const content = payload.choices?.[0]?.message?.content?.trim();

  if (!content) {
    throw new Error("LLM provider returned empty content");
  }

  return { content, model };
}

function parseSectionsFromText(text: string): string[] {
  return text
    .split(/\n+/)
    .map((line) => line.replace(/^[-•*]\s*/, "").replace(/^\d+[.、)]\s*/, "").trim())
    .filter((line) => line.length > 10);
}

function buildAnnualExamFallback(digest: AnnualExamDigest): AnnualExamInsightResult {
  const abnormalMetrics = digest.metrics.filter(
    (m) => m.abnormalFlag === "high" || m.abnormalFlag === "low"
  );
  const criticalMetrics = abnormalMetrics.filter(
    (m) => ["lipid.ldl_c", "lipid.lpa", "glycemic.glucose"].includes(m.metricCode)
  );

  return {
    generatedAt: new Date().toISOString(),
    examTitle: digest.latestTitle,
    sections: {
      overview: digest.highlightSummary,
      attentionPoints: abnormalMetrics.map(
        (m) => `${m.label} ${m.latestValue} ${m.unit}，${m.abnormalFlag === "high" ? "偏高" : "偏低"}${m.referenceRange ? `（参考范围 ${m.referenceRange}）` : ""}，建议重点跟踪。`
      ),
      improvements: digest.improvedMetricLabels.map(
        (label) => `${label} 相较上次已有改善，继续保持当前干预节奏。`
      ).concat(abnormalMetrics.length === 0 ? ["各项核心指标均在正常范围内，请继续保持当前生活方式。"] : []),
      urgentIssues: criticalMetrics.map(
        (m) => `${m.label}（${m.latestValue} ${m.unit}）出现异常，建议就医咨询并在 3 个月内安排复查，评估是否需要药物干预。`
      ),
      positiveSignals: digest.improvedMetricLabels.length > 0
        ? [`相较上次，${digest.improvedMetricLabels.join("、")} 均有改善。`]
        : ["体检整体指标平稳，未见新增高优先异常。"]
    },
    disclaimer: "以上分析基于体检数据自动生成，仅供参考，不构成医疗诊断。如有健康顾虑，请咨询专业医生。",
    provider: "fallback",
    model: "health-insight-fallback-v1"
  };
}

function buildGeneticsFallback(findings: GeneticFindingDigest[]): GeneticsInsightResult {
  const highRisk = findings.filter((f) => f.riskLevel === "high");
  const withLinkedAbnormal = findings.filter(
    (f) => f.linkedMetric && f.linkedMetric.abnormalFlag !== "normal"
  );

  return {
    generatedAt: new Date().toISOString(),
    sections: {
      overview: `共 ${findings.length} 条基因 finding，覆盖 ${new Set(findings.map((f) => f.dimension)).size} 个维度，其中高关注背景 ${highRisk.length} 条，已关联当前异常指标 ${withLinkedAbnormal.length} 条。`,
      highRiskPoints: highRisk.map(
        (f) => `${f.traitLabel}（${f.geneSymbol}）：${f.summary}。${f.suggestion}`
      ),
      healthCorrelations: withLinkedAbnormal.map(
        (f) => `${f.traitLabel} 与当前指标 ${f.linkedMetric!.metricName}（${f.linkedMetric!.value} ${f.linkedMetric!.unit}，${f.linkedMetric!.abnormalFlag !== "normal" ? "异常" : "正常"}）存在关联，两者需结合长期跟踪。`
      ).concat(withLinkedAbnormal.length === 0 ? ["当前基因项关联的健康指标均在正常范围内，遗传风险处于较低表达状态。"] : []),
      lifestyleAdvice: findings.slice(0, 4).map(
        (f) => f.suggestion
      ),
      longTermMonitoring: highRisk.map(
        (f) => `${f.dimension}维度（${f.traitLabel}）需每年结合体检结果评估趋势。`
      ).concat(["建议每年上传最新体检和化验数据，持续更新基因与健康指标的关联分析。"])
    },
    disclaimer: "基因报告反映遗传背景倾向，不代表疾病确诊。遗传因素只是健康风险的一部分，环境和生活方式同样重要。如有疑问请咨询遗传咨询师或专科医生。",
    provider: "fallback",
    model: "health-insight-fallback-v1"
  };
}

const ANNUAL_EXAM_SYSTEM_PROMPT = [
  "你是一位专业的健康数据分析助手，帮助用户理解年度体检报告。",
  "请用中文回答，语言清晰、有依据、非诊断性。",
  "回答时请按以下格式输出 JSON（不要有 markdown 代码块标记）：",
  `{
  "overview": "综合评估（1-2句话）",
  "attentionPoints": ["需要注意的具体点1", "需要注意的具体点2"],
  "improvements": ["改善建议1", "改善建议2"],
  "urgentIssues": ["需要就医/复查的问题1"],
  "positiveSignals": ["积极信号1"]
}`,
  "如果没有紧急问题，urgentIssues 为空数组。每条内容控制在 50 字以内，适合手机阅读。"
].join("\n");

const GENETICS_SYSTEM_PROMPT = [
  "你是一位专业的基因健康分析助手，帮助用户理解基因检测报告与当前健康状况的关联。",
  "请用中文回答，语言科学严谨但易于理解，强调基因是背景因素而非决定因素。",
  "回答时请按以下格式输出 JSON（不要有 markdown 代码块标记）：",
  `{
  "overview": "基因组合综合解读（2-3句话）",
  "highRiskPoints": ["高风险点1的详细说明", "高风险点2的详细说明"],
  "healthCorrelations": ["与现有健康指标的关联分析1", "关联分析2"],
  "lifestyleAdvice": ["针对基因背景的生活方式建议1", "建议2"],
  "longTermMonitoring": ["需要长期监测的项目1", "项目2"]
}`,
  "每条内容控制在 60 字以内，避免过度夸大风险，注重可操作性。"
].join("\n");

async function callLLMProvider(
  systemPrompt: string,
  userPrompt: string
): Promise<{ content: string; provider: string; model: string } | null> {
  const env = getAppEnv();

  if (!env.HEALTH_LLM_API_KEY) {
    return null;
  }

  if (env.HEALTH_LLM_PROVIDER === "anthropic") {
    const model = env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-6";
    const result = await callAnthropicForInsight(systemPrompt, userPrompt, env.HEALTH_LLM_API_KEY, model);
    return { content: result.content, provider: "anthropic", model: result.model };
  }

  if (env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_BASE_URL) {
    const model = env.HEALTH_LLM_MODEL ?? "gpt-4.1-mini";
    const result = await callOpenAICompatibleForInsight(
      systemPrompt, userPrompt, env.HEALTH_LLM_API_KEY, env.HEALTH_LLM_BASE_URL, model
    );
    return { content: result.content, provider: "openai-compatible", model: result.model };
  }

  return null;
}

export async function generateAnnualExamInsight(
  digest: AnnualExamDigest
): Promise<AnnualExamInsightResult> {
  const userPrompt = buildAnnualExamPrompt(digest);

  try {
    const llmResult = await callLLMProvider(ANNUAL_EXAM_SYSTEM_PROMPT, userPrompt);

    if (llmResult) {
      const cleaned = llmResult.content
        .replace(/^```(?:json)?\s*/i, "")
        .replace(/\s*```\s*$/, "")
        .trim();
      const parsed = JSON.parse(cleaned) as {
        overview?: string;
        attentionPoints?: unknown;
        improvements?: unknown;
        urgentIssues?: unknown;
        positiveSignals?: unknown;
      };

      const toStringArray = (value: unknown): string[] => {
        if (!Array.isArray(value)) return [];
        return value.filter((item): item is string => typeof item === "string");
      };

      return {
        generatedAt: new Date().toISOString(),
        examTitle: digest.latestTitle,
        sections: {
          overview: typeof parsed.overview === "string" ? parsed.overview : digest.highlightSummary,
          attentionPoints: toStringArray(parsed.attentionPoints),
          improvements: toStringArray(parsed.improvements),
          urgentIssues: toStringArray(parsed.urgentIssues),
          positiveSignals: toStringArray(parsed.positiveSignals)
        },
        disclaimer: "以上分析由 AI 基于体检数据生成，仅供参考，不构成医疗诊断。如有健康顾虑，请咨询专业医生。",
        provider: llmResult.provider,
        model: llmResult.model
      };
    }
  } catch {
    // Fall through to fallback
  }

  return buildAnnualExamFallback(digest);
}

export async function generateGeneticsInsight(
  findings: GeneticFindingDigest[]
): Promise<GeneticsInsightResult> {
  const userPrompt = buildGeneticsPrompt(findings);

  try {
    const llmResult = await callLLMProvider(GENETICS_SYSTEM_PROMPT, userPrompt);

    if (llmResult) {
      const cleaned = llmResult.content
        .replace(/^```(?:json)?\s*/i, "")
        .replace(/\s*```\s*$/, "")
        .trim();
      const parsed = JSON.parse(cleaned) as {
        overview?: string;
        highRiskPoints?: unknown;
        healthCorrelations?: unknown;
        lifestyleAdvice?: unknown;
        longTermMonitoring?: unknown;
      };

      const toStringArray = (value: unknown): string[] => {
        if (!Array.isArray(value)) return [];
        return value.filter((item): item is string => typeof item === "string");
      };

      return {
        generatedAt: new Date().toISOString(),
        sections: {
          overview: typeof parsed.overview === "string" ? parsed.overview : `共分析 ${findings.length} 条基因 finding。`,
          highRiskPoints: toStringArray(parsed.highRiskPoints),
          healthCorrelations: toStringArray(parsed.healthCorrelations),
          lifestyleAdvice: toStringArray(parsed.lifestyleAdvice),
          longTermMonitoring: toStringArray(parsed.longTermMonitoring)
        },
        disclaimer: "基因报告反映遗传背景倾向，不代表疾病确诊。遗传因素只是健康风险的一部分，环境和生活方式同样重要。如有疑问请咨询遗传咨询师或专科医生。",
        provider: llmResult.provider,
        model: llmResult.model
      };
    }
  } catch {
    // Fall through to fallback
  }

  return buildGeneticsFallback(findings);
}

export { parseSectionsFromText };
