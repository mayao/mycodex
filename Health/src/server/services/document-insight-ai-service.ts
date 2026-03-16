import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import { getAppEnv } from "../config/env";
import { getDatabase } from "../db/sqlite";
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
}

export interface DocumentInsightResult {
  documentType: "medical_exam" | "genetic";
  hasData: boolean;
  summary: string;
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

  return `你是一位经验丰富的健康顾问，请基于以下体检数据给出专业洞察分析。

## 体检报告：${digest.latestTitle}
检查日期：${digest.latestRecordedAt.slice(0, 10)}
${digest.previousTitle ? `对比上次：${digest.previousTitle}（${digest.previousRecordedAt?.slice(0, 10)}）` : ""}

## 各项指标
${metricsText}

## 统计摘要
- 异常指标：${abnormal.length} 项（${abnormal.map((m) => m.shortLabel).join("、") || "无"}）
- 正常指标：${normal.length} 项
- ${digest.highlightSummary}

## 分析任务
请严格按照以下 JSON 格式返回分析结果（不要包含任何 markdown 代码块标记）：
{
  "summary": "3-4句话的总体摘要，说明整体健康状态和主要发现",
  "urgentItems": [
    {
      "title": "问题名称",
      "detail": "详细说明为什么需要关注，当前数值与正常值的差距",
      "action": "建议就医/建议复查/建议生活方式干预等具体行动",
      "severity": "high",
      "relatedMetrics": ["指标名称1", "指标名称2"]
    }
  ],
  "attentionItems": [
    {
      "title": "需关注的点",
      "detail": "说明原因和趋势",
      "action": "建议措施",
      "severity": "medium",
      "relatedMetrics": []
    }
  ],
  "positiveItems": [
    {
      "title": "好的发现",
      "detail": "说明为什么这是积极信号",
      "severity": "positive",
      "relatedMetrics": []
    }
  ],
  "recommendations": ["具体可执行的建议1", "建议2", "建议3"]
}

注意事项：
1. urgentItems 只放真正需要立即关注的项目（如明显偏高的LDL、血糖、尿酸等），若无则返回空数组
2. 对于严重异常（多项超标、肿瘤标志物异常等）必须在 action 中明确写"建议尽快就医"
3. positiveItems 放正常或改善的指标，给用户鼓励
4. recommendations 给出 3-5 条具体可操作的生活方式建议
5. 不要做医疗诊断，使用"建议"而非"确诊"等词汇`;
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

  return `你是一位基因健康顾问，请基于以下基因检测结果给出深度洞察分析。

## 基因检测结果概览
- 检测维度数：${findings.length}
- 高风险项目：${highRiskCount} 项
- 基因风险与实测指标同时异常（需特别关注）：${correlatedCount} 项

## 各基因维度详情
${findingsText}

## 分析任务
请严格按照以下 JSON 格式返回分析结果（不要包含任何 markdown 代码块标记）：
{
  "summary": "3-4句话的总体摘要，说明基因图谱的主要特点和需要关注的方向",
  "urgentItems": [
    {
      "title": "高风险基因维度名称",
      "detail": "详细说明该基因风险的含义，特别是如果同时存在实测指标异常要重点说明两者叠加的意义",
      "action": "基因咨询建议/定期监测建议/生活方式干预",
      "severity": "high",
      "relatedMetrics": ["关联指标名称"]
    }
  ],
  "attentionItems": [
    {
      "title": "中风险维度名称",
      "detail": "说明该基因的特点和预防要点",
      "action": "预防性建议",
      "severity": "medium",
      "relatedMetrics": []
    }
  ],
  "positiveItems": [
    {
      "title": "有利的基因特征",
      "detail": "说明这个低风险或有利的基因特征的意义",
      "severity": "positive",
      "relatedMetrics": []
    }
  ],
  "recommendations": ["针对基因风险的具体干预建议1", "建议2", "建议3"]
}

注意事项：
1. 重点分析"基因高风险 + 实测指标偏高"的叠加情况，这是最需要关注的
2. 基因风险不等于必然发病，请强调可干预性
3. 建议中要结合基因特点给出个性化的生活方式建议（饮食、运动、监测频率等）
4. 不要做医疗诊断，提醒用户基因检测结果仅供参考`;
}

// ─── LLM Call ─────────────────────────────────────────────────────────────────

interface LLMInsightPayload {
  summary: string;
  urgentItems: Array<{
    title: string;
    detail: string;
    action?: string;
    severity: InsightSeverity;
    relatedMetrics?: string[];
  }>;
  attentionItems: Array<{
    title: string;
    detail: string;
    action?: string;
    severity: InsightSeverity;
    relatedMetrics?: string[];
  }>;
  positiveItems: Array<{
    title: string;
    detail: string;
    action?: string;
    severity: InsightSeverity;
    relatedMetrics?: string[];
  }>;
  recommendations: string[];
}

function parseLLMResponse(text: string): LLMInsightPayload | null {
  try {
    // Strip markdown code fences if present
    const cleaned = text.replace(/^```(?:json)?\n?/m, "").replace(/\n?```$/m, "").trim();
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
      max_tokens: 2048,
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
      max_tokens: 2048,
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
        generationConfig: { maxOutputTokens: 2048 }
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

export async function callLLMWithFallbacks(
  prompt: string
): Promise<{ text: string; provider: string; model: string }> {
  const env = getAppEnv();
  const TIMEOUT_MS = 18_000;

  function makeSignal(): AbortSignal {
    const ctrl = new AbortController();
    setTimeout(() => ctrl.abort(), TIMEOUT_MS);
    return ctrl.signal;
  }

  // Primary: openai-compatible (Kimi / any OpenAI-compat proxy)
  if (env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_BASE_URL) {
    try {
      const model = env.HEALTH_LLM_MODEL ?? "moonshot-v1-32k";
      const baseUrl = env.HEALTH_LLM_BASE_URL.replace(/\/$/, "");
      const response = await fetch(`${baseUrl}/chat/completions`, {
        method: "POST",
        signal: makeSignal(),
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${env.HEALTH_LLM_API_KEY}`
        },
        body: JSON.stringify({
          model,
          max_tokens: 2048,
          messages: [{ role: "user", content: prompt }]
        })
      });
      if (!response.ok) throw new Error(`OpenAI-compat API ${response.status}`);
      const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }>; model?: string };
      const text = data.choices?.[0]?.message?.content ?? "";
      return { text, provider: "openai-compatible", model: data.model ?? model };
    } catch {
      // fall through
    }
  }

  // Primary: Anthropic
  if (env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "anthropic") {
    try {
      const model = env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514";
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        signal: makeSignal(),
        headers: {
          "Content-Type": "application/json",
          "x-api-key": env.HEALTH_LLM_API_KEY,
          "anthropic-version": "2023-06-01"
        },
        body: JSON.stringify({
          model,
          max_tokens: 2048,
          messages: [{ role: "user", content: prompt }]
        })
      });
      if (!response.ok) throw new Error(`Anthropic API ${response.status}`);
      const data = (await response.json()) as { content?: Array<{ type: string; text?: string }>; model?: string };
      const text = data.content?.find((c) => c.type === "text")?.text ?? "";
      return { text, model: data.model ?? model, provider: "anthropic" };
    } catch {
      // fall through
    }
  }

  // Fallback 1: Kimi (via HEALTH_LLM_FALLBACK_KIMI_KEY)
  const kimiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
  if (kimiKey) {
    try {
      const model = process.env.HEALTH_LLM_FALLBACK_KIMI_MODEL ?? "kimi-for-coding";
      const response = await fetch("https://api.kimi.com/coding/v1/chat/completions", {
        method: "POST",
        signal: makeSignal(),
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${kimiKey}`,
          "User-Agent": "KimiCLI/1.3"
        },
        body: JSON.stringify({
          model,
          max_tokens: 2048,
          messages: [{ role: "user", content: prompt }]
        })
      });
      if (!response.ok) throw new Error(`Kimi API ${response.status}`);
      const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }>; model?: string };
      const text = data.choices?.[0]?.message?.content ?? "";
      return { text, model: data.model ?? model, provider: "kimi" };
    } catch {
      // fall through
    }
  }

  // Fallback 2: Gemini
  const geminiKey = process.env.HEALTH_LLM_FALLBACK_GEMINI_KEY;
  if (geminiKey) {
    try {
      const model = process.env.HEALTH_LLM_FALLBACK_GEMINI_MODEL ?? "gemini-2.0-flash";
      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiKey}`,
        {
          method: "POST",
          signal: makeSignal(),
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { maxOutputTokens: 2048 }
          })
        }
      );
      if (!response.ok) throw new Error(`Gemini API ${response.status}`);
      const data = (await response.json()) as { candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }> };
      const text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
      return { text, model, provider: "gemini" };
    } catch {
      // fall through
    }
  }

  throw new Error("all_providers_failed");
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
    relatedMetrics: item.relatedMetrics ?? []
  }));
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
    relatedMetrics: [m.shortLabel]
  }));

  const positiveItems: InsightItem[] = normal.slice(0, 3).map((m) => ({
    id: randomUUID(),
    title: `${m.label} 正常`,
    detail: `当前值 ${m.latestValue} ${m.unit}，在参考范围内。`,
    severity: "positive" as InsightSeverity,
    relatedMetrics: [m.shortLabel]
  }));

  const recommendations: string[] = [
    urgent.length > 0 ? `请重点关注 ${urgent.map((m) => m.label).slice(0, 3).join("、")} 等指标，建议咨询医生` : "各项指标整体正常，继续保持良好生活习惯",
    "建议每天保持 30 分钟中等强度有氧运动",
    "保持均衡饮食，减少高脂高糖食物摄入",
    "保证充足睡眠，维持规律作息"
  ].filter(Boolean);

  return {
    documentType: "medical_exam",
    hasData: true,
    summary: urgent.length > 0
      ? `本次体检发现 ${urgent.length} 项异常指标（${urgent.map((m) => m.shortLabel).join("、")}），${normal.length} 项正常。建议重点关注异常项目并咨询医生。`
      : `本次体检各项主要指标均在正常范围内（共 ${normal.length} 项正常），健康状态良好，请继续保持。`,
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
    relatedMetrics: f.linkedMetric ? [f.linkedMetric.metricName] : []
  }));

  const attentionItems: InsightItem[] = medRisk.map((f) => ({
    id: randomUUID(),
    title: `${f.traitLabel}（${f.geneSymbol}）— 中风险`,
    detail: f.summary,
    action: f.suggestion,
    severity: "medium" as InsightSeverity,
    relatedMetrics: []
  }));

  const positiveItems: InsightItem[] = lowRisk.slice(0, 3).map((f) => ({
    id: randomUUID(),
    title: `${f.traitLabel} — 低风险`,
    detail: f.summary,
    severity: "positive" as InsightSeverity,
    relatedMetrics: []
  }));

  const allSuggestions = [...highRisk, ...medRisk].map((f) => f.suggestion).filter(Boolean).slice(0, 4);

  return {
    documentType: "genetic",
    hasData: true,
    summary: `共检测 ${findings.length} 个基因维度：高风险 ${highRisk.length} 项、中风险 ${medRisk.length} 项、低风险 ${lowRisk.length} 项。${highRisk.length > 0 ? `请重点关注 ${highRisk.map((f) => f.traitLabel).join("、")}。` : ""}`,
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

  const prompt = buildMedicalExamPrompt(digest);
  try {
    const llmResult = await callLLMWithFallbacks(prompt);
    const parsed = parseLLMResponse(llmResult.text);
    if (!parsed) throw new Error("unparseable");
    return {
      documentType: "medical_exam",
      hasData: true,
      summary: parsed.summary,
      urgentItems: buildInsightItems(parsed.urgentItems),
      attentionItems: buildInsightItems(parsed.attentionItems),
      positiveItems: buildInsightItems(parsed.positiveItems),
      recommendations: parsed.recommendations ?? [],
      provider: llmResult.provider,
      model: llmResult.model,
      disclaimer: "本分析仅供健康参考，不构成医疗诊断。如有异常指标，请咨询专业医疗人员。",
      generatedAt: new Date().toISOString()
    };
  } catch {
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

  const prompt = buildGeneticPrompt(findings);
  try {
    const llmResult = await callLLMWithFallbacks(prompt);
    const parsed = parseLLMResponse(llmResult.text);
    if (!parsed) throw new Error("unparseable");
    return {
      documentType: "genetic",
      hasData: true,
      summary: parsed.summary,
      urgentItems: buildInsightItems(parsed.urgentItems),
      attentionItems: buildInsightItems(parsed.attentionItems),
      positiveItems: buildInsightItems(parsed.positiveItems),
      recommendations: parsed.recommendations ?? [],
      provider: llmResult.provider,
      model: llmResult.model,
      disclaimer: "基因检测结果仅反映遗传倾向，不等于疾病诊断。环境、生活方式等因素同样重要。如有疑问，请咨询遗传咨询师或医疗专业人员。",
      generatedAt: new Date().toISOString()
    };
  } catch {
    return buildRuleBasedGeneticResult(findings);
  }
}
