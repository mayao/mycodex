import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import { getAppEnv } from "../config/env";
import { getDatabase } from "../db/sqlite";
import { getKimiOpenAIHeaders, getProviderPriority } from "./llm-provider-routing";
import {
  getAnnualExamDigest,
  listGeneticFindingDigests,
  type AnnualExamDigest,
  type GeneticFindingDigest
} from "../repositories/document-insight-repository";

// ─── Response Types ────────────────────────────────────────────────────────────

export type InsightSeverity = "high" | "medium" | "low" | "positive";

export interface InsightItem {
  id: string;
  title: string;
  detail: string;
  action?: string;
  severity: InsightSeverity;
  relatedMetrics?: string[];
  categoryLabel?: string;
}

export interface DocumentInsightResult {
  documentType: "medical_exam" | "genetic";
  hasData: boolean;
  summary: string;
  summaryHeadline?: string;
  summaryHighlights?: string[];
  urgentItems: InsightItem[];
  attentionItems: InsightItem[];
  positiveItems: InsightItem[];
  recommendations: string[];
  provider: string;
  model: string;
  disclaimer: string;
  generatedAt: string;
}

// ─── Prompts ──────────────────────────────────────────────────────────────────

function buildMedicalExamPrompt(digest: AnnualExamDigest): string {
  const abnormal = digest.metrics.filter(
    (m) => m.abnormalFlag === "high" || m.abnormalFlag === "low"
  );
  const normal = digest.metrics.filter((m) => m.abnormalFlag === "normal");

  const metricsText = digest.metrics
    .map((m) => {
      const trend =
        typeof m.delta === "number"
          ? m.delta > 0
            ? `↑${Math.abs(m.delta).toFixed(2)}`
            : m.delta < 0
              ? `↓${Math.abs(m.delta).toFixed(2)}`
              : "→持平"
          : "";
      const flag = m.abnormalFlag === "normal" ? "" : `【${m.abnormalFlag === "high" ? "偏高" : "偏低"}】`;
      return `- ${m.label}(${m.shortLabel}): ${m.latestValue} ${m.unit} ${flag}${trend} 参考范围:${m.referenceRange ?? "N/A"}`;
    })
    .join("\n");

  return `你是一位具有 20 年临床经验的内科主任医师兼健康管理专家。请基于以下体检数据，像面对面问诊一样给出专业、具体、有深度的洞察分析。

## 体检报告：${digest.latestTitle}
检查日期：${digest.latestRecordedAt.slice(0, 10)}
${digest.previousTitle ? `对比上次：${digest.previousTitle}（${digest.previousRecordedAt?.slice(0, 10)}）` : ""}

## 各项指标
${metricsText}

## 统计摘要
- 异常指标：${abnormal.length} 项（${abnormal.map((m) => m.shortLabel).join("、") || "无"}）
- 正常指标：${normal.length} 项
- ${digest.highlightSummary}

## 分析要求
请严格按照以下 JSON 格式返回（不要包含 markdown 代码块标记）：
{
  "summary": "4-6句话的总体评估。必须引用具体数值说明问题，例如'LDL-C 为 4.2 mmol/L，超出上限 3.4 的 24%'。如有历史对比必须说明变化趋势和幅度。最后给出整体风险定性。",
  "urgentItems": [
    {
      "title": "具体问题名称（含指标名）",
      "detail": "必须包含：①当前数值与参考范围的对比 ②该指标偏高/偏低的临床意义 ③如有历史数据需说明变化趋势 ④可能导致的健康后果。至少3-4句话，不要笼统概括。",
      "action": "明确的下一步行动，例如'建议3个月内至心内科复查空腹血脂四项'而非笼统的'建议复查'",
      "severity": "high",
      "relatedMetrics": ["指标名称1", "指标名称2"]
    }
  ],
  "attentionItems": [
    {
      "title": "需关注的指标或模式",
      "detail": "说明为什么虽然在范围内但仍需关注（如接近上限、持续上升趋势、多指标联合提示等），引用具体数值。",
      "action": "具体的监测频率和生活方式调整建议",
      "severity": "medium",
      "relatedMetrics": []
    }
  ],
  "positiveItems": [
    {
      "title": "积极发现",
      "detail": "引用具体数值说明为什么这是好信号，如有改善趋势说明改善幅度。给用户具体的鼓励。",
      "severity": "positive",
      "relatedMetrics": []
    }
  ],
  "recommendations": [
    "每条建议必须具体可执行。不要写'注意饮食'，要写'每日钠摄入控制在 5g 以下，减少腌制食品；增加深色蔬菜摄入至每日 300g'。",
    "运动建议需包含频率、时长、强度，例如'每周 4-5 次、每次 30-40 分钟中等强度有氧运动（快走、游泳），目标心率 120-140'。",
    "如需复查，明确复查时间和项目。"
  ]
}

关键要求：
1. 每条洞察必须引用具体数值和参考范围，不要空泛概括
2. urgentItems 只放真正超标的指标，但 detail 必须深入解释临床意义
3. 多指标联合分析：如 LDL-C 偏高 + 甘油三酯偏高 + HDL-C 偏低，应联合评估心血管风险而非分别列出
4. attentionItems 要关注"虽在范围内但接近边界"和"虽然正常但趋势不利"的指标
5. recommendations 至少 4 条，每条都有具体的量化目标
6. 不要做医疗诊断，使用"建议"而非"确诊"等词汇`;
}

function buildGeneticPrompt(findings: GeneticFindingDigest[]): string {
  const findingsText = findings
    .map((f) => {
      const risk = f.riskLevel === "high" ? "高风险" : f.riskLevel === "medium" ? "中风险" : "低风险";
      const linkedMetricText = f.linkedMetric
        ? `关联实测指标：${f.linkedMetric.metricName} = ${f.linkedMetric.value} ${f.linkedMetric.unit}（${f.linkedMetric.abnormalFlag === "high" ? "偏高" : f.linkedMetric.abnormalFlag === "low" ? "偏低" : "正常"}）`
        : "暂无关联实测指标";
      return `### ${f.traitLabel}（${f.geneSymbol}）
- 风险等级：${risk}｜证据等级：${f.evidenceLevel}
- 所属维度：${f.dimension}
- 基因摘要：${f.summary}
- 建议：${f.suggestion}
- ${linkedMetricText}`;
    })
    .join("\n\n");

  const highRiskCount = findings.filter((f) => f.riskLevel === "high").length;
  const correlatedCount = findings.filter(
    (f) => f.linkedMetric && f.linkedMetric.abnormalFlag !== "normal" && f.riskLevel !== "low"
  ).length;

  return `你是一位精准医学与遗传咨询专家，拥有分子遗传学博士学位和 15 年临床基因组分析经验。请基于以下基因检测结果，给出深入、具体、个性化的洞察分析。

## 基因检测结果概览
- 检测维度数：${findings.length}
- 高风险项目：${highRiskCount} 项
- 基因风险与实测指标同时异常（需特别关注）：${correlatedCount} 项

## 各基因维度详情
${findingsText}

## 分析要求
请严格按照以下 JSON 格式返回（不要包含 markdown 代码块标记）：
{
  "summary": "4-6句话的综合基因图谱评估。必须点名具体基因和风险等级。如有基因风险与实测指标叠加的情况，重点阐述其临床意义。给出整体遗传风险画像。",
  "urgentItems": [
    {
      "title": "高风险维度名称 + 基因名",
      "detail": "必须包含：①该基因变异的具体含义（携带什么突变、影响什么蛋白/通路）②该风险在人群中的发生率 ③如有关联实测指标异常，详细分析基因风险+表型异常叠加的临床意义（例如：'APOE ε4 携带者 LDL-C 偏高提示脂质代谢通路双重受损'）④与其他检测维度的交互影响。至少4句话。",
      "action": "具体行动方案，例如'建议每6个月检测空腹血脂四项+载脂蛋白，同时咨询心血管专科评估是否需要他汀类药物干预'",
      "severity": "high",
      "relatedMetrics": ["关联实测指标名称"]
    }
  ],
  "attentionItems": [
    {
      "title": "中风险维度名称",
      "detail": "说明该基因变异的功能影响、在人群中的携带率、目前的证据等级（如GWAS验证/功能研究/临床级别），以及对应的预防策略。引用具体的基因名和变异位点。",
      "action": "预防性监测方案，包括检测频率和具体检查项目",
      "severity": "medium",
      "relatedMetrics": []
    }
  ],
  "positiveItems": [
    {
      "title": "有利的基因特征",
      "detail": "说明该基因型的保护性意义，例如'快速咖啡因代谢型（CYP1A2 *1A/*1A）意味着您可以安全摄入适量咖啡，且研究显示每日 2-3 杯咖啡对该基因型有心血管保护作用'。引用具体研究发现。",
      "severity": "positive",
      "relatedMetrics": []
    }
  ],
  "recommendations": [
    "每条建议必须针对具体基因风险定制。不要写'注意饮食'，要写'根据您的 MTHFR C677T 杂合突变，建议每日补充活性叶酸（5-MTHF）400-800μg，优先选择深绿色蔬菜（菠菜、西兰花）'。",
    "运动建议需结合基因型，例如'您的 ACTN3 R577X 基因型提示耐力型运动更适合，建议以有氧运动为主（游泳、跑步），每周 4-5 次，每次 40-60 分钟'。",
    "监测建议需明确频率和项目。"
  ]
}

关键要求：
1. 最重要的分析维度是"基因风险 + 实测指标叠加"——这代表遗传倾向已经在表型层面体现，需要深入解释其临床意义
2. 每个基因维度的 detail 必须引用具体基因名、变异位点、风险等级数据
3. 基因风险不等于必然发病，但要量化风险倍数（如"患病风险约为普通人群的 1.5-2 倍"）
4. recommendations 至少 4 条，每条都要关联到具体的基因发现
5. 不要做医疗诊断，但可以给出风险量化评估`;
}

// ─── LLM Call ─────────────────────────────────────────────────────────────────

interface LLMInsightPayload {
  summary: string;
  summaryHeadline?: string;
  summaryHighlights?: string[];
  urgentItems: Array<{
    title: string;
    detail: string;
    action?: string;
    severity: InsightSeverity;
    relatedMetrics?: string[];
    categoryLabel?: string;
  }>;
  attentionItems: Array<{
    title: string;
    detail: string;
    action?: string;
    severity: InsightSeverity;
    relatedMetrics?: string[];
    categoryLabel?: string;
  }>;
  positiveItems: Array<{
    title: string;
    detail: string;
    action?: string;
    severity: InsightSeverity;
    relatedMetrics?: string[];
    categoryLabel?: string;
  }>;
  recommendations: string[];
}

function parseLLMResponse(text: string): LLMInsightPayload | null {
  try {
    // Strip markdown code fences if present
    let cleaned = text.replace(/^```(?:json)?\n?/gm, "").replace(/\n?```$/gm, "").trim();
    // Try to extract JSON object if there's extra text around it
    const jsonMatch = cleaned.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      cleaned = jsonMatch[0];
    }
    const parsed = JSON.parse(cleaned) as LLMInsightPayload;
    if (!parsed.summary || !Array.isArray(parsed.recommendations)) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

async function callAnthropicForInsights(
  prompt: string,
  apiKey: string,
  model: string
): Promise<{ text: string; model: string }> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01"
    },
    body: JSON.stringify({
      model,
      max_tokens: 8192,
      messages: [{ role: "user", content: prompt }]
    })
  });

  if (!response.ok) {
    throw new Error(`Anthropic API error: ${response.status}`);
  }

  const data = (await response.json()) as {
    content?: Array<{ type: string; text?: string }>;
    model?: string;
  };
  const text = data.content?.find((c) => c.type === "text")?.text ?? "";
  return { text, model: data.model ?? model };
}

async function callKimiForInsights(
  prompt: string,
  apiKey: string,
  model: string
): Promise<{ text: string; model: string }> {
  const response = await fetch("https://api.kimi.com/coding/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      "User-Agent": "KimiCLI/1.3"
    },
    body: JSON.stringify({
      model,
      max_tokens: 8192,
      messages: [{ role: "user", content: prompt }]
    })
  });

  if (!response.ok) {
    throw new Error(`Kimi API error: ${response.status}`);
  }

  const data = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
    model?: string;
  };
  const text = data.choices?.[0]?.message?.content ?? "";
  return { text, model: data.model ?? model };
}

async function callGeminiForInsights(
  prompt: string,
  apiKey: string,
  model: string
): Promise<{ text: string; model: string }> {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { maxOutputTokens: 8192 }
      })
    }
  );

  if (!response.ok) {
    throw new Error(`Gemini API error: ${response.status}`);
  }

  const data = (await response.json()) as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  return { text, model };
}

type LLMProviderFn = () => Promise<{ text: string; provider: string; model: string }>;

export async function callLLMWithFallbacks(
  prompt: string,
  options?: { preferredProvider?: string | null; timeoutMs?: number }
): Promise<{ text: string; provider: string; model: string }> {
  const env = getAppEnv();
  const TIMEOUT_MS = options?.timeoutMs ?? 30_000;

  function makeSignal(): AbortSignal {
    const ctrl = new AbortController();
    setTimeout(() => ctrl.abort(), TIMEOUT_MS);
    return ctrl.signal;
  }

  const tryOpenAI: LLMProviderFn = async () => {
    if (!(env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_BASE_URL)) throw new Error("not configured");
    const model = env.HEALTH_LLM_MODEL ?? "moonshot-v1-32k";
    const baseUrl = env.HEALTH_LLM_BASE_URL.replace(/\/$/, "");
    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST", signal: makeSignal(),
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${env.HEALTH_LLM_API_KEY}`,
        ...(getKimiOpenAIHeaders(env.HEALTH_LLM_API_KEY) ?? {})
      },
      body: JSON.stringify({ model, max_tokens: 8192, messages: [{ role: "user", content: prompt }] })
    });
    if (!response.ok) throw new Error(`OpenAI-compat API ${response.status}`);
    const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }>; model?: string };
    return { text: data.choices?.[0]?.message?.content ?? "", provider: "openai_compatible", model: data.model ?? model };
  };

  const tryAnthropic: LLMProviderFn = async () => {
    if (!(env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "anthropic")) throw new Error("not configured");
    const model = env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514";
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST", signal: makeSignal(),
      headers: { "Content-Type": "application/json", "x-api-key": env.HEALTH_LLM_API_KEY, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model, max_tokens: 8192, messages: [{ role: "user", content: prompt }] })
    });
    if (!response.ok) throw new Error(`Anthropic API ${response.status}`);
    const data = (await response.json()) as { content?: Array<{ type: string; text?: string }>; model?: string };
    return { text: data.content?.find((c) => c.type === "text")?.text ?? "", model: data.model ?? model, provider: "anthropic" };
  };

  const tryKimi: LLMProviderFn = async () => {
    const kimiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
    if (!kimiKey) throw new Error("not configured");
    const model = process.env.HEALTH_LLM_FALLBACK_KIMI_MODEL ?? "kimi-latest";
    // sk-kimi-* keys use api.kimi.com; sk-* keys use api.moonshot.cn
    const baseUrl = kimiKey.startsWith("sk-kimi-") ? "https://api.kimi.com/coding/v1" : "https://api.moonshot.cn/v1";
    const headers: Record<string, string> = { "Content-Type": "application/json", Authorization: `Bearer ${kimiKey}` };
    if (kimiKey.startsWith("sk-kimi-")) headers["User-Agent"] = "KimiCLI/1.3";
    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST", signal: makeSignal(),
      headers,
      body: JSON.stringify({ model, max_tokens: 8192, messages: [{ role: "user", content: prompt }] })
    });
    if (!response.ok) throw new Error(`Kimi API ${response.status}`);
    const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }>; model?: string };
    return { text: data.choices?.[0]?.message?.content ?? "", model: data.model ?? model, provider: "kimi" };
  };

  const tryGemini: LLMProviderFn = async () => {
    const geminiKey = process.env.HEALTH_LLM_FALLBACK_GEMINI_KEY;
    if (!geminiKey) throw new Error("not configured");
    const model = process.env.HEALTH_LLM_FALLBACK_GEMINI_MODEL ?? "gemini-2.5-flash";
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiKey}`,
      {
        method: "POST", signal: makeSignal(),
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }], generationConfig: { maxOutputTokens: 8192 } })
      }
    );
    if (!response.ok) throw new Error(`Gemini API ${response.status}`);
    const data = (await response.json()) as { candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }> };
    return { text: data.candidates?.[0]?.content?.parts?.[0]?.text ?? "", model, provider: "gemini" };
  };

  const providerMap: Record<string, LLMProviderFn> = {
    anthropic: tryAnthropic,
    openai_compatible: tryOpenAI,
    kimi: tryKimi,
    gemini: tryGemini,
  };

  const order = getProviderPriority(env, options?.preferredProvider);

  // Race ALL configured providers in parallel — fastest wins (like streaming does)
  const raceCandidates: Array<Promise<{ text: string; provider: string; model: string }>> = [];
  for (const name of order) {
    const fn = providerMap[name];
    if (!fn) continue;
    raceCandidates.push(
      fn()
        .then(result => {
          console.log(`[LLM] ✅ ${name} succeeded (${result.model})`);
          return result;
        })
        .catch(error => {
          const msg = error instanceof Error ? error.message : String(error);
          console.warn(`[LLM] ❌ ${name} failed: ${msg}`);
          throw error;
        })
    );
  }

  if (raceCandidates.length === 0) {
    throw new Error("all_providers_failed");
  }

  // Global timeout
  const timeoutPromise = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error("all_providers_timeout")), TIMEOUT_MS)
  );

  try {
    return await Promise.any([...raceCandidates, timeoutPromise.catch(() => { throw new Error("all_providers_timeout"); })]);
  } catch {
    throw new Error("all_providers_failed");
  }
}

// ─── Build result from parsed LLM payload ────────────────────────────────────

function buildInsightItems(
  items: LLMInsightPayload["urgentItems"]
): InsightItem[] {
  return (items ?? []).map((item) => ({
    id: randomUUID(),
    title: item.title,
    detail: item.detail,
    action: item.action,
    severity: item.severity,
    relatedMetrics: item.relatedMetrics ?? [],
    categoryLabel: item.categoryLabel
  }));
}

function deriveSummaryHeadline(summary: string, documentType: DocumentInsightResult["documentType"]): string {
  const firstSentence = summary.split(/[。.!?]/).map((item) => item.trim()).find(Boolean);
  if (firstSentence) return firstSentence;
  return documentType === "genetic" ? "基因背景已形成结构化洞察" : "体检结果已形成结构化洞察";
}

function deriveSummaryHighlights(
  summary: string,
  urgentItems: InsightItem[],
  attentionItems: InsightItem[],
  positiveItems: InsightItem[]
): string[] {
  const items = [
    ...urgentItems.slice(0, 2).map((item) => item.title),
    ...attentionItems.slice(0, 1).map((item) => item.title),
    ...positiveItems.slice(0, 1).map((item) => item.title)
  ];

  if (items.length > 0) {
    return items.slice(0, 3);
  }

  return summary
    .split(/[。.!?]/)
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 3);
}

// ─── Rule-based Fallbacks (when LLM is unavailable) ──────────────────────────

function buildRuleBasedMedicalExamResult(digest: AnnualExamDigest): DocumentInsightResult {
  const urgent = digest.metrics.filter(
    (m) => (m.abnormalFlag === "high" || m.abnormalFlag === "low") && m.latestValue !== null
  );
  const normal = digest.metrics.filter((m) => m.abnormalFlag === "normal");

  const urgentItems: InsightItem[] = urgent.map((m) => ({
    id: randomUUID(),
    title: `${m.label} ${m.abnormalFlag === "high" ? "偏高" : "偏低"}`,
    detail: `当前值 ${m.latestValue} ${m.unit}，参考范围 ${m.referenceRange ?? "—"}。${m.delta != null ? `较上次${m.delta > 0 ? "上升" : "下降"} ${Math.abs(m.delta).toFixed(2)} ${m.unit}。` : ""}`,
    action: "建议复查并咨询医生",
    severity: "high" as InsightSeverity,
    relatedMetrics: [m.shortLabel],
    categoryLabel: "异常指标"
  }));

  const positiveItems: InsightItem[] = normal.slice(0, 3).map((m) => ({
    id: randomUUID(),
    title: `${m.label} 正常`,
    detail: `当前值 ${m.latestValue} ${m.unit}，在参考范围内。`,
    severity: "positive" as InsightSeverity,
    relatedMetrics: [m.shortLabel],
    categoryLabel: "稳定项"
  }));

  const summary = urgent.length > 0
    ? `本次体检发现 ${urgent.length} 项异常指标（${urgent.map((m) => m.shortLabel).join("、")}），${normal.length} 项正常。建议重点关注异常项目并咨询医生。`
    : `本次体检各项主要指标均在正常范围内（共 ${normal.length} 项正常），健康状态良好，请继续保持。`;

  const recommendations: string[] = [
    urgent.length > 0 ? `请重点关注 ${urgent.map((m) => m.label).slice(0, 3).join("、")} 等指标，建议咨询医生` : "各项指标整体正常，继续保持良好生活习惯",
    "建议每天保持 30 分钟中等强度有氧运动",
    "保持均衡饮食，减少高脂高糖食物摄入",
    "保证充足睡眠，维持规律作息"
  ].filter(Boolean);

  return {
    documentType: "medical_exam",
    hasData: true,
    summary,
    summaryHeadline: deriveSummaryHeadline(summary, "medical_exam"),
    summaryHighlights: deriveSummaryHighlights(summary, urgentItems, [], positiveItems),
    urgentItems,
    attentionItems: [],
    positiveItems,
    recommendations,
    provider: "rule-based",
    model: "local",
    disclaimer: "本分析为基于参考范围的规则判断，仅供参考，不构成医疗诊断。AI 分析服务暂时不可用，请稍后重试以获取更详细的个性化分析。",
    generatedAt: new Date().toISOString()
  };
}

function buildRuleBasedGeneticResult(findings: GeneticFindingDigest[]): DocumentInsightResult {
  const highRisk = findings.filter((f) => f.riskLevel === "high");
  const medRisk = findings.filter((f) => f.riskLevel === "medium");
  const lowRisk = findings.filter((f) => f.riskLevel === "low");

  const urgentItems: InsightItem[] = highRisk.map((f) => ({
    id: randomUUID(),
    title: `${f.traitLabel}（${f.geneSymbol}）— 高风险`,
    detail: `${f.summary}${f.linkedMetric && f.linkedMetric.abnormalFlag !== "normal" ? ` 实测 ${f.linkedMetric.metricName} 同时${f.linkedMetric.abnormalFlag === "high" ? "偏高" : "偏低"}（${f.linkedMetric.value} ${f.linkedMetric.unit}），基因风险与实测异常双重叠加，需重点关注。` : ""}`,
    action: f.suggestion,
    severity: "high" as InsightSeverity,
    relatedMetrics: f.linkedMetric ? [f.linkedMetric.metricName] : [],
    categoryLabel: f.dimension
  }));

  const attentionItems: InsightItem[] = medRisk.map((f) => ({
    id: randomUUID(),
    title: `${f.traitLabel}（${f.geneSymbol}）— 中风险`,
    detail: f.summary,
    action: f.suggestion,
    severity: "medium" as InsightSeverity,
    relatedMetrics: [],
    categoryLabel: f.dimension
  }));

  const positiveItems: InsightItem[] = lowRisk.slice(0, 3).map((f) => ({
    id: randomUUID(),
    title: `${f.traitLabel} — 低风险`,
    detail: f.summary,
    severity: "positive" as InsightSeverity,
    relatedMetrics: [],
    categoryLabel: f.dimension
  }));

  const allSuggestions = [...highRisk, ...medRisk].map((f) => f.suggestion).filter(Boolean).slice(0, 4);
  const summary = `共检测 ${findings.length} 个基因维度：高风险 ${highRisk.length} 项、中风险 ${medRisk.length} 项、低风险 ${lowRisk.length} 项。${highRisk.length > 0 ? `请重点关注 ${highRisk.map((f) => f.traitLabel).join("、")}。` : ""}`;

  return {
    documentType: "genetic",
    hasData: true,
    summary,
    summaryHeadline: deriveSummaryHeadline(summary, "genetic"),
    summaryHighlights: deriveSummaryHighlights(summary, urgentItems, attentionItems, positiveItems),
    urgentItems,
    attentionItems,
    positiveItems,
    recommendations: allSuggestions.length > 0 ? allSuggestions : ["结合基因特点调整生活方式", "定期监测相关健康指标", "如有疑问请咨询遗传咨询师"],
    provider: "rule-based",
    model: "local",
    disclaimer: "本分析基于基因风险等级直接呈现，AI 深度分析服务暂时不可用，请稍后重试以获取更个性化的关联分析。基因检测结果仅反映遗传倾向，不等于疾病诊断。",
    generatedAt: new Date().toISOString()
  };
}

// ─── Main exported functions ──────────────────────────────────────────────────

// ─── Insight Cache (persistent until new upload invalidates) ─────────────────
const insightCache = new Map<string, { result: DocumentInsightResult }>();

function getCachedInsight(key: string): DocumentInsightResult | null {
  const entry = insightCache.get(key);
  return entry?.result ?? null;
}

function setCachedInsight(key: string, result: DocumentInsightResult): void {
  insightCache.set(key, { result });
}

/**
 * Invalidate insight cache for a user when new data is uploaded.
 * Call this from the import pipeline after a successful import.
 */
export function invalidateInsightCache(userId: string, type?: "medical_exam" | "genetic"): void {
  if (type) {
    insightCache.delete(`${type}:${userId}`);
  } else {
    insightCache.delete(`medical_exam:${userId}`);
    insightCache.delete(`genetic:${userId}`);
  }
  console.log(`[Insight Cache] Invalidated cache for user=${userId} type=${type ?? "all"}`);
}

/**
 * Returns a short AI insight summary for a given type if it exists in cache.
 * Used by health-home-service to enrich source dimension cards without calling LLM.
 */
export function getCachedInsightSummary(userId: string, type: "medical_exam" | "genetic"): string | null {
  const key = `${type}:${userId}`;
  const cached = getCachedInsight(key);
  if (!cached || !cached.hasData) return null;
  // Build a compact summary from urgent/attention items
  const parts: string[] = [];
  if (cached.urgentItems.length > 0) {
    parts.push(`⚠️ ${cached.urgentItems.map(i => i.title).join("、")}`);
  }
  if (cached.attentionItems.length > 0) {
    parts.push(`📋 ${cached.attentionItems.map(i => i.title).join("、")}`);
  }
  if (cached.recommendations.length > 0) {
    parts.push(`💡 ${cached.recommendations[0]}`);
  }
  return parts.length > 0 ? parts.join(" | ") : cached.summary.slice(0, 100);
}

export async function getMedicalExamInsights(
  userId: string,
  database: DatabaseSync = getDatabase()
): Promise<DocumentInsightResult> {
  const digest = getAnnualExamDigest(database, userId);

  if (!digest) {
    return {
      documentType: "medical_exam",
      hasData: false,
      summary: "尚未上传体检报告，无法生成洞察分析。请在数据页上传您的年度体检报告。",
      summaryHeadline: "尚未上传体检报告",
      summaryHighlights: ["上传体检报告后可生成结构化洞察", "支持 PDF 和图片", "上传后会自动解析并回流首页"],
      urgentItems: [],
      attentionItems: [],
      positiveItems: [],
      recommendations: ["前往「数据」页上传体检报告（PDF 或图片）", "上传后 AI 将自动解析并生成个性化洞察"],
      provider: "none",
      model: "none",
      disclaimer: "",
      generatedAt: new Date().toISOString()
    };
  }

  // Check cache
  const cacheKey = `medical_exam:${userId}`;
  const cached = getCachedInsight(cacheKey);
  if (cached) return cached;

  const prompt = buildMedicalExamPrompt(digest);
  try {
    console.log(`[Insight] Starting LLM call for medical_exam (user=${userId})`);
    const startTime = Date.now();
    const llmResult = await callLLMWithFallbacks(prompt, { timeoutMs: 45_000 });
    console.log(`[Insight] LLM responded in ${Date.now() - startTime}ms via ${llmResult.provider}/${llmResult.model}, text length=${llmResult.text.length}`);
    const parsed = parseLLMResponse(llmResult.text);
    if (!parsed) {
      console.error(`[Insight] Failed to parse LLM response. First 500 chars: ${llmResult.text.slice(0, 500)}`);
      throw new Error("unparseable");
    }
    const result: DocumentInsightResult = {
      documentType: "medical_exam",
      hasData: true,
      summary: parsed.summary,
      summaryHeadline: parsed.summaryHeadline ?? deriveSummaryHeadline(parsed.summary, "medical_exam"),
      urgentItems: buildInsightItems(parsed.urgentItems),
      attentionItems: buildInsightItems(parsed.attentionItems),
      positiveItems: buildInsightItems(parsed.positiveItems),
      recommendations: parsed.recommendations ?? [],
      provider: llmResult.provider,
      model: llmResult.model,
      disclaimer: "本分析仅供健康参考，不构成医疗诊断。如有异常指标，请咨询专业医疗人员。",
      generatedAt: new Date().toISOString()
    };
    result.summaryHighlights = parsed.summaryHighlights ?? deriveSummaryHighlights(
      result.summary,
      result.urgentItems,
      result.attentionItems,
      result.positiveItems
    );
    setCachedInsight(cacheKey, result);
    return result;
  } catch (error) {
    console.error(`[Insight] medical_exam analysis failed:`, error instanceof Error ? error.message : error);
    return buildRuleBasedMedicalExamResult(digest);
  }
}

export async function getGeneticInsights(
  userId: string,
  database: DatabaseSync = getDatabase()
): Promise<DocumentInsightResult> {
  const findings = listGeneticFindingDigests(database, userId);

  if (findings.length === 0) {
    return {
      documentType: "genetic",
      hasData: false,
      summary: "尚未上传基因检测报告，无法生成洞察分析。",
      summaryHeadline: "尚未上传基因检测报告",
      summaryHighlights: ["支持图片、PDF 与结构化文件", "上传后会生成长期背景洞察", "未知 trait 也会保留，不会直接丢弃"],
      urgentItems: [],
      attentionItems: [],
      positiveItems: [],
      recommendations: ["前往「数据」页上传基因检测报告", "支持常见基因检测平台的原始数据文件"],
      provider: "none",
      model: "none",
      disclaimer: "",
      generatedAt: new Date().toISOString()
    };
  }

  // Check cache
  const cacheKey = `genetic:${userId}`;
  const cached = getCachedInsight(cacheKey);
  if (cached) return cached;

  const prompt = buildGeneticPrompt(findings);
  try {
    console.log(`[Insight] Starting LLM call for genetic (user=${userId})`);
    const startTime = Date.now();
    const llmResult = await callLLMWithFallbacks(prompt, { timeoutMs: 45_000 });
    console.log(`[Insight] LLM responded in ${Date.now() - startTime}ms via ${llmResult.provider}/${llmResult.model}, text length=${llmResult.text.length}`);
    const parsed = parseLLMResponse(llmResult.text);
    if (!parsed) {
      console.error(`[Insight] Failed to parse genetic LLM response. First 500 chars: ${llmResult.text.slice(0, 500)}`);
      throw new Error("unparseable");
    }
    const result: DocumentInsightResult = {
      documentType: "genetic",
      hasData: true,
      summary: parsed.summary,
      summaryHeadline: parsed.summaryHeadline ?? deriveSummaryHeadline(parsed.summary, "genetic"),
      urgentItems: buildInsightItems(parsed.urgentItems),
      attentionItems: buildInsightItems(parsed.attentionItems),
      positiveItems: buildInsightItems(parsed.positiveItems),
      recommendations: parsed.recommendations ?? [],
      provider: llmResult.provider,
      model: llmResult.model,
      disclaimer: "基因检测结果仅反映遗传倾向，不等于疾病诊断。环境、生活方式等因素同样重要。如有疑问，请咨询遗传咨询师或医疗专业人员。",
      generatedAt: new Date().toISOString()
    };
    result.summaryHighlights = parsed.summaryHighlights ?? deriveSummaryHighlights(
      result.summary,
      result.urgentItems,
      result.attentionItems,
      result.positiveItems
    );
    setCachedInsight(cacheKey, result);
    return result;
  } catch {
    return buildRuleBasedGeneticResult(findings);
  }
}
