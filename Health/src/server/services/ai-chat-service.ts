import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import { z } from "zod";

import { getAppEnv } from "../config/env";
import { getDatabase } from "../db/sqlite";
import { getHealthHomePageData } from "./health-home-service";
import { getKimiOpenAIHeaders, getProviderPriority } from "./llm-provider-routing";
import { getUserPreferredProvider } from "./llm-preference-service";

const chatMessageSchema = z.object({
  id: z.string().optional(),
  role: z.enum(["user", "assistant"]),
  content: z.string().trim().min(1).max(12000),
  createdAt: z.string().optional()
});

export const healthAIChatRequestSchema = z.object({
  messages: z.array(chatMessageSchema).min(1).max(20)
});

export type HealthAIChatRequest = z.infer<typeof healthAIChatRequestSchema>;

type HealthAIChatResponse = {
  reply: {
    id: string;
    role: "assistant";
    content: string;
    createdAt: string;
  };
  provider: string;
  model: string;
};

function trimList(items: Array<string | undefined>, limit = 4): string[] {
  return [...new Set(items.map((item) => item?.trim()).filter((item): item is string => Boolean(item)))]
    .slice(0, limit);
}

function buildChatContext(payload: Awaited<ReturnType<typeof getHealthHomePageData>>) {
  return {
    generatedAt: payload.generatedAt,
    overview: {
      headline: payload.overviewDigest.headline,
      summary: payload.overviewDigest.summary,
      focusAreas: payload.overviewFocusAreas
    },
    goodSignals: payload.overviewDigest.goodSignals,
    needsAttention: payload.overviewDigest.needsAttention,
    actionPlan: payload.overviewDigest.actionPlan,
    latestNarrative: payload.latestNarrative.output.headline,
    reminders: payload.keyReminders.slice(0, 4).map((item) => ({
      title: item.title,
      summary: item.summary,
      action: item.suggested_action
    })),
    geneticFindings: payload.geneticFindings.slice(0, 4).map((item) => ({
      trait: item.traitLabel,
      dimension: item.dimension,
      summary: item.plainMeaning ?? item.summary,
      action: item.practicalAdvice ?? item.suggestion
    })),
    sourceDimensions: payload.sourceDimensions.map((item) => ({
      label: item.label,
      summary: item.summary,
      highlight: item.highlight
    })),
    disclaimer: payload.disclaimer
  };
}

function buildSystemPrompt(payload: Awaited<ReturnType<typeof getHealthHomePageData>>) {
  const ctx = buildChatContext(payload);
  return [
    "# 角色",
    "你是 HealthAI App 的个人健康顾问。你拥有该用户完整的健康仪表盘数据，包括体检报告、血脂趋势、体重/体脂变化、运动/睡眠记录、基因检测结果等多维度信息。",
    "",
    "# 回答原则",
    "1. **个性化优先**：每一条建议必须引用用户的实际数据（具体数值、趋势方向、异常标记），不要给出任何人都适用的泛泛建议。",
    "2. **结构化输出**：使用清晰的分段结构回答，包括：",
    "   - 📊 **现状评估**：基于数据的客观描述",
    "   - 🎯 **核心发现**：最值得关注的 2-3 个要点",
    "   - 📋 **具体方案**：可执行的下一步行动（包含时间、频率、量化目标）",
    "   - ⚠️ **注意事项**：基于基因背景或长期趋势的风险提醒（如适用）",
    "3. **引用数据**：回答中直接引用具体数值，例如「你的 LDL-C 当前为 X mmol/L，较上次下降了 Y%」，而不是「你的血脂有所改善」。",
    "4. **非诊断声明**：不做医疗诊断、不开药物处方，但可以建议「下次复查时可以和医生讨论 XXX」。",
    "5. **适合手机阅读**：段落简洁，重点加粗，每段 2-3 句话。",
    "",
    "# 用户健康概况",
    `综合评估：${ctx.overview.headline}`,
    `核心摘要：${ctx.overview.summary}`,
    `关注领域：${ctx.overview.focusAreas.join("、")}`,
    "",
    "## 积极信号",
    ctx.goodSignals.map((s: string, i: number) => `${i + 1}. ${s}`).join("\n"),
    "",
    "## 需要关注",
    ctx.needsAttention.map((s: string, i: number) => `${i + 1}. ${s}`).join("\n"),
    "",
    "## 当前行动计划",
    ctx.actionPlan.map((s: string, i: number) => `${i + 1}. ${s}`).join("\n"),
    "",
    "## 基因检测结果",
    ctx.geneticFindings.length > 0
      ? ctx.geneticFindings.map((f: { trait: string; dimension: string; summary: string; action: string }) =>
          `- **${f.trait}**（${f.dimension}）：${f.summary}。建议：${f.action}`
        ).join("\n")
      : "暂无基因数据",
    "",
    "## 各维度数据摘要",
    ctx.sourceDimensions.map((d: { label: string; summary: string; highlight: string }) =>
      `- **${d.label}**：${d.summary}（${d.highlight}）`
    ).join("\n"),
    "",
    "## 提醒事项",
    ctx.reminders.map((r: { title: string; summary: string; action: string }) =>
      `- ${r.title}：${r.summary}。建议行动：${r.action}`
    ).join("\n"),
    "",
    `最新叙事摘要：${ctx.latestNarrative}`,
    "",
    `⚖️ ${ctx.disclaimer}`
  ].join("\n");
}

async function requestAnthropicReply(
  request: HealthAIChatRequest,
  payload: Awaited<ReturnType<typeof getHealthHomePageData>>,
  apiKey: string,
  model: string
) {
  const systemPrompt = buildSystemPrompt(payload);

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 45_000);
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    signal: ctrl.signal,
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01"
    },
    body: JSON.stringify({
      model,
      max_tokens: 4096,
      system: systemPrompt,
      messages: request.messages.map((message) => ({
        role: message.role,
        content: message.content
      }))
    })
  });
  clearTimeout(timer);

  if (!response.ok) {
    const errorBody = await response.text().catch(() => "");
    throw new Error(`Anthropic API failed with status ${response.status}: ${errorBody.slice(0, 200)}`);
  }

  const payloadJSON = (await response.json()) as {
    content?: Array<{
      type: string;
      text?: string;
    }>;
    model?: string;
  };

  const content = payloadJSON.content
    ?.filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("\n")
    .trim();

  if (!content) {
    throw new Error("Anthropic API returned empty content");
  }

  return {
    provider: "anthropic",
    model: payloadJSON.model ?? model,
    content
  };
}

async function requestOpenAICompatibleReply(
  request: HealthAIChatRequest,
  payload: Awaited<ReturnType<typeof getHealthHomePageData>>,
  apiKey: string,
  baseUrl: string,
  model: string,
  extraHeaders?: Record<string, string>
) {
  const systemPrompt = buildSystemPrompt(payload);

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 45_000);
  const response = await fetch(`${baseUrl.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    signal: ctrl.signal,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      ...(getKimiOpenAIHeaders(apiKey) ?? {}),
      ...(extraHeaders ?? {})
    },
    body: JSON.stringify({
      model,
      temperature: 0.3,
      max_tokens: 4096,
      messages: [
        { role: "system", content: systemPrompt },
        ...request.messages.map((message) => ({
          role: message.role,
          content: message.content
        }))
      ]
    })
  });
  clearTimeout(timer);

  if (!response.ok) {
    throw new Error(`HealthAI chat provider failed with status ${response.status}`);
  }

  const payloadJSON = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };

  const content = payloadJSON.choices?.[0]?.message?.content?.trim();

  if (!content) {
    throw new Error("HealthAI chat provider returned empty content");
  }

  return { provider: "openai-compatible", model, content };
}

async function requestProviderReply(
  request: HealthAIChatRequest,
  payload: Awaited<ReturnType<typeof getHealthHomePageData>>,
  preferredProvider?: string | null
): Promise<{ provider: string; model: string; content: string } | null> {
  const env = getAppEnv();
  const providerOrder = getProviderPriority(env, preferredProvider);

  for (const provider of providerOrder) {
    try {
      if (provider === "anthropic") {
        // Use HEALTH_LLM_API_KEY when provider is "anthropic" (or unset)
        const isAnthropicProvider = !env.HEALTH_LLM_PROVIDER || env.HEALTH_LLM_PROVIDER === "anthropic";
        const apiKey = isAnthropicProvider ? env.HEALTH_LLM_API_KEY : undefined;
        if (!apiKey) continue;
        const model = env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514";
        return await requestAnthropicReply(request, payload, apiKey, model);
      }

      if (provider === "kimi") {
        const apiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
        const model = process.env.HEALTH_LLM_FALLBACK_KIMI_MODEL ?? "kimi-latest";
        if (!apiKey) continue;
        // sk-kimi-* keys use api.kimi.com; sk-* keys use api.moonshot.cn
        const isKimiKey = apiKey.startsWith("sk-kimi-");
        const kimiBaseUrl = isKimiKey ? "https://api.kimi.com/coding/v1" : "https://api.moonshot.cn/v1";
        const kimiHeaders = isKimiKey ? { "User-Agent": "KimiCLI/1.3" } : undefined;
        return await requestOpenAICompatibleReply(
          request, payload, apiKey,
          kimiBaseUrl, model, kimiHeaders
        );
      }

      if (provider === "openai_compatible") {
        const apiKey = env.HEALTH_LLM_API_KEY;
        const baseUrl = env.HEALTH_LLM_BASE_URL;
        const model = env.HEALTH_LLM_MODEL ?? "gpt-4.1-mini";
        if (!(apiKey && baseUrl && env.HEALTH_LLM_PROVIDER === "openai-compatible")) continue;
        return await requestOpenAICompatibleReply(request, payload, apiKey, baseUrl, model);
      }

      if (provider === "gemini") {
        const apiKey = process.env.HEALTH_LLM_FALLBACK_GEMINI_KEY;
        const model = process.env.HEALTH_LLM_FALLBACK_GEMINI_MODEL ?? "gemini-2.5-flash";
        if (!apiKey) continue;
        return await requestOpenAICompatibleReply(
          request, payload, apiKey,
          "https://generativelanguage.googleapis.com/v1beta/openai", model
        );
      }
    } catch (error) {
      console.warn(`[AI Chat] Provider ${provider} failed:`, error instanceof Error ? error.message : error);
      continue;
    }
  }

  return null;
}

function buildFallbackReply(
  userMessage: string,
  payload: Awaited<ReturnType<typeof getHealthHomePageData>>
) {
  const normalized = userMessage.toLowerCase();
  const summary = payload.overviewDigest.summary;
  const defaultAttention = payload.overviewDigest.needsAttention[0] ?? "恢复节奏仍值得持续观察。";
  const defaultAction = payload.overviewDigest.actionPlan[0] ?? "继续保持连续记录。";

  if (/睡眠|恢复|入睡|早睡/.test(normalized)) {
    const recoveryAnalysis =
      payload.dimensionAnalyses.find((item) => item.key.includes("recovery")) ??
      payload.dimensionAnalyses.find((item) => item.key.includes("activity"));
    const recoveryReminder = payload.keyReminders.find((item) =>
      /睡眠|恢复/.test(item.title + item.summary)
    );

    return trimList(
      [
        recoveryAnalysis?.summary,
        recoveryReminder?.summary,
        recoveryReminder?.suggested_action ?? recoveryAnalysis?.actionPlan[0],
        `当前首页的核心结论仍然是：${summary}`
      ],
      4
    ).join(" ");
  }

  if (/血脂|ldl|apo|胆固醇|lpa|lp\(a\)/.test(normalized)) {
    const lipidAnalysis = payload.dimensionAnalyses.find((item) => item.key.includes("lipid"));
    const lipidFinding = payload.geneticFindings.find((item) =>
      /血脂|Lp\(a\)|LPA/i.test(item.dimension + item.traitLabel + item.geneSymbol)
    );

    return trimList(
      [
        lipidAnalysis?.summary ?? payload.overviewDigest.goodSignals[0],
        payload.overviewDigest.needsAttention.find((item) => /Lp\(a\)|血脂/.test(item)) ?? defaultAttention,
        lipidFinding
          ? `${lipidFinding.traitLabel}：${lipidFinding.plainMeaning ?? lipidFinding.summary}`
          : undefined,
        `下一步更适合先做：${lipidAnalysis?.actionPlan[0] ?? defaultAction}`
      ],
      4
    ).join(" ");
  }

  if (/体重|体脂|bmi|减脂/.test(normalized)) {
    const bodyAnalysis = payload.dimensionAnalyses.find((item) => item.key.includes("body"));
    return trimList(
      [
        bodyAnalysis?.summary ?? payload.overviewDigest.goodSignals.find((item) => /体脂|体重/.test(item)),
        payload.overviewDigest.goodSignals.find((item) => /体脂|体重/.test(item)),
        `下一步建议：${bodyAnalysis?.actionPlan[0] ?? defaultAction}`
      ],
      3
    ).join(" ");
  }

  if (/运动|训练|步数|活动/.test(normalized)) {
    const activityAnalysis = payload.dimensionAnalyses.find((item) => item.key.includes("activity"));
    return trimList(
      [
        activityAnalysis?.summary ?? payload.overviewDigest.goodSignals.find((item) => /训练|运动/.test(item)),
        payload.keyReminders.find((item) => /训练|运动/.test(item.title + item.summary))?.summary,
        `接下来先做：${activityAnalysis?.actionPlan[0] ?? defaultAction}`
      ],
      3
    ).join(" ");
  }

  if (/基因|遗传|咖啡因|lpa|actn3|cyp1a2/.test(normalized)) {
    const findings = payload.geneticFindings.slice(0, 2);
    if (findings.length > 0) {
      return findings
        .map((item) => `${item.traitLabel}：${item.plainMeaning ?? item.summary}。建议：${item.practicalAdvice ?? item.suggestion}`)
        .join(" ");
    }
  }

  if (/上传|导入|同步|apple 健康|数据更新/.test(normalized)) {
    return [
      "你可以在“数据”页上传体检、化验、体脂或运动文件。",
      "如果是 iPhone 真机，也可以在“Apple 健康同步”里更新最近 90 天的睡眠、运动、步数和身体组成数据。",
      "上传或同步完成后，首页结论、趋势和报告会按最新数据刷新。"
    ].join(" ");
  }

  return [
    `当前首页的核心结论是：${summary}`,
    `现在最值得优先关注的是：${defaultAttention}`,
    `建议先做：${defaultAction}`
  ].join(" ");
}

// ─── Streaming Chat ──────────────────────────────────────────────────────────

export async function streamHealthAIReply(
  request: HealthAIChatRequest,
  userId: string = "user-self",
  database: DatabaseSync = getDatabase()
): Promise<{ stream: ReadableStream<Uint8Array>; provider: string; model: string }> {
  const payload = await getHealthHomePageData(database, userId);
  const latestUserMessage = [...request.messages].reverse().find((m) => m.role === "user");
  if (!latestUserMessage) throw new Error("缺少用户输入。");

  const systemPrompt = buildSystemPrompt(payload);
  const env = getAppEnv();
  const preferredProvider = getUserPreferredProvider(database, userId);

  // Race ALL streaming providers in parallel with a tight global timeout.
  // This avoids sequential 30s waits per provider when the network is unreliable.
  const STREAM_RACE_TIMEOUT_MS = 45_000; // 45s total for all providers (opus is slow)

  type StreamResult = { stream: ReadableStream<Uint8Array>; provider: string; model: string };

  const raceCandidates: Array<Promise<StreamResult>> = [];

  for (const provider of getProviderPriority(env, preferredProvider)) {
    if (provider === "kimi") {
      const kimiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
      const kimiModel = process.env.HEALTH_LLM_FALLBACK_KIMI_MODEL ?? "kimi-latest";
      if (!kimiKey) continue;
      const isKimiKey = kimiKey.startsWith("sk-kimi-");
      const kimiBaseUrl = isKimiKey ? "https://api.kimi.com/coding/v1" : "https://api.moonshot.cn/v1";
      const kimiHeaders: Record<string, string> = {};
      if (isKimiKey) kimiHeaders["User-Agent"] = "KimiCLI/1.3";
      raceCandidates.push(
        openStreamingRequest(`${kimiBaseUrl}/chat/completions`, kimiKey, kimiModel, systemPrompt, request.messages, kimiHeaders)
          .then(stream => ({ stream, provider: "kimi", model: kimiModel }))
          .catch(e => { console.warn("[AI Chat Stream] kimi failed:", e instanceof Error ? e.message : e); throw e; })
      );
      continue;
    }

    if (provider === "anthropic") {
      const anthropicKey = env.HEALTH_LLM_PROVIDER === "anthropic" ? env.HEALTH_LLM_API_KEY : undefined;
      if (!anthropicKey) continue;
      const anthropicModel = env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514";
      raceCandidates.push(
        openAnthropicStreamingRequest(anthropicKey, anthropicModel, systemPrompt, request.messages)
          .then(stream => ({ stream, provider: "anthropic", model: anthropicModel }))
          .catch(e => { console.warn("[AI Chat Stream] anthropic failed:", e instanceof Error ? e.message : e); throw e; })
      );
      continue;
    }

    if (provider === "openai_compatible") {
      const apiKey = env.HEALTH_LLM_API_KEY;
      const baseUrl = env.HEALTH_LLM_BASE_URL;
      const model = env.HEALTH_LLM_MODEL ?? "gpt-4.1-mini";
      if (!(apiKey && baseUrl && env.HEALTH_LLM_PROVIDER === "openai-compatible")) continue;
      raceCandidates.push(
        openStreamingRequest(baseUrl, apiKey, model, systemPrompt, request.messages)
          .then(stream => ({ stream, provider: "openai_compatible", model }))
          .catch(e => { console.warn("[AI Chat Stream] openai_compatible failed:", e instanceof Error ? e.message : e); throw e; })
      );
      continue;
    }

    if (provider === "gemini") {
      const geminiKey = process.env.HEALTH_LLM_FALLBACK_GEMINI_KEY;
      if (!geminiKey) continue;
      const geminiModel = process.env.HEALTH_LLM_FALLBACK_GEMINI_MODEL ?? "gemini-2.5-flash";
      raceCandidates.push(
        openStreamingRequest("https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", geminiKey, geminiModel, systemPrompt, request.messages)
          .then(stream => ({ stream, provider: "gemini", model: geminiModel }))
          .catch(e => { console.warn("[AI Chat Stream] gemini failed:", e instanceof Error ? e.message : e); throw e; })
      );
    }
  }

  if (raceCandidates.length > 0) {
    // Race: first successful provider wins; if all fail, fall through to mock
    let raceTimer: ReturnType<typeof setTimeout> | undefined;
    const timeoutPromise = new Promise<never>((_, reject) => {
      raceTimer = setTimeout(() => reject(new Error("stream_race_timeout")), STREAM_RACE_TIMEOUT_MS);
    });
    try {
      const result = await Promise.any([
        ...raceCandidates,
        timeoutPromise.catch(() => { throw new Error("stream_race_timeout"); })
      ]);
      clearTimeout(raceTimer); // Clean up timer on success
      console.log(`[AI Chat Stream] ✅ ${result.provider} won the race`);
      return result;
    } catch (error) {
      clearTimeout(raceTimer);
      console.warn("[AI Chat Stream] All providers failed or timed out:", error instanceof Error ? error.message : error);
    }
  }

  // Fallback: return non-streaming fallback as SSE
  const fallbackContent = buildFallbackReply(latestUserMessage.content, payload);
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode(`data: ${JSON.stringify({ choices: [{ delta: { content: fallbackContent } }] })}\n\n`));
      controller.enqueue(encoder.encode("data: [DONE]\n\n"));
      controller.close();
    }
  });
  return { stream, provider: "mock", model: "healthai-chat-fallback-v1" };
}

async function openStreamingRequest(
  baseUrl: string,
  apiKey: string,
  model: string,
  systemPrompt: string,
  messages: HealthAIChatRequest["messages"],
  extraHeaders?: Record<string, string>
): Promise<ReadableStream<Uint8Array>> {
  const ctrl = new AbortController();
  const connectTimeout = setTimeout(() => ctrl.abort(), 30_000);
  const response = await fetch(`${baseUrl.replace(/\/$/, "")}${baseUrl.includes("/chat/completions") ? "" : "/chat/completions"}`, {
    method: "POST",
    signal: ctrl.signal,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      ...(getKimiOpenAIHeaders(apiKey) ?? {}),
      ...(extraHeaders ?? {})
    },
    body: JSON.stringify({
      model,
      stream: true,
      max_tokens: 4096,
      temperature: 0.3,
      messages: [
        { role: "system", content: systemPrompt },
        ...messages.map((m) => ({ role: m.role, content: m.content }))
      ]
    })
  });
  clearTimeout(connectTimeout);

  if (!response.ok) {
    const errBody = await response.text().catch(() => "");
    throw new Error(`Streaming request failed: ${response.status} ${errBody.slice(0, 200)}`);
  }

  if (!response.body) {
    throw new Error("No response body for streaming");
  }

  // Transform: normalize Kimi's reasoning_content → content, filter empty chunks
  const reader = response.body.getReader();
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  let buffer = "";

  return new ReadableStream<Uint8Array>({
    async pull(controller) {
      const { done, value } = await reader.read();
      if (done) {
        controller.enqueue(encoder.encode("data: [DONE]\n\n"));
        controller.close();
        return;
      }
      buffer += decoder.decode(value, { stream: true });
      // Process complete SSE lines
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? ""; // keep incomplete last line in buffer
      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;
        const data = line.slice(6).trim();
        if (data === "[DONE]") {
          controller.enqueue(encoder.encode("data: [DONE]\n\n"));
          continue;
        }
        try {
          const event = JSON.parse(data) as {
            choices?: Array<{
              delta?: { content?: string; reasoning_content?: string; role?: string };
              finish_reason?: string | null;
            }>;
          };
          const delta = event.choices?.[0]?.delta;
          if (!delta) continue;
          // Only forward actual content, skip Kimi's reasoning_content (internal thinking)
          const text = delta.content;
          if (text) {
            const normalized = { choices: [{ delta: { content: text } }] };
            controller.enqueue(encoder.encode(`data: ${JSON.stringify(normalized)}\n\n`));
          }
          // Forward finish_reason as [DONE]
          if (event.choices?.[0]?.finish_reason) {
            controller.enqueue(encoder.encode("data: [DONE]\n\n"));
          }
        } catch {
          // skip unparseable
        }
      }
    }
  });
}

async function openAnthropicStreamingRequest(
  apiKey: string,
  model: string,
  systemPrompt: string,
  messages: HealthAIChatRequest["messages"]
): Promise<ReadableStream<Uint8Array>> {
  const ctrl = new AbortController();
  const connectTimeout = setTimeout(() => ctrl.abort(), 30_000);
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    signal: ctrl.signal,
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01"
    },
    body: JSON.stringify({
      model,
      max_tokens: 4096,
      stream: true,
      system: systemPrompt,
      messages: messages.map((m) => ({ role: m.role, content: m.content }))
    })
  });
  clearTimeout(connectTimeout);

  if (!response.ok) {
    throw new Error(`Anthropic streaming failed: ${response.status}`);
  }

  if (!response.body) {
    throw new Error("No response body for Anthropic streaming");
  }

  // Transform Anthropic SSE format → OpenAI-compatible SSE format for uniform client parsing
  const reader = response.body.getReader();
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  let buffer = "";

  return new ReadableStream<Uint8Array>({
    async pull(controller) {
      const { done, value } = await reader.read();
      if (done) {
        controller.enqueue(encoder.encode("data: [DONE]\n\n"));
        controller.close();
        return;
      }
      buffer += decoder.decode(value, { stream: true });
      // Process complete SSE lines (buffer handles cross-chunk splits)
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? ""; // keep incomplete last line in buffer
      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;
        const data = line.slice(6).trim();
        if (data === "[DONE]") {
          controller.enqueue(encoder.encode("data: [DONE]\n\n"));
          continue;
        }
        try {
          const event = JSON.parse(data) as {
            type?: string;
            delta?: { type?: string; text?: string };
          };
          if (event.type === "content_block_delta" && event.delta?.text) {
            const openAIChunk = {
              choices: [{ delta: { content: event.delta.text } }]
            };
            controller.enqueue(encoder.encode(`data: ${JSON.stringify(openAIChunk)}\n\n`));
          } else if (event.type === "message_stop") {
            controller.enqueue(encoder.encode("data: [DONE]\n\n"));
          }
        } catch {
          // skip unparseable lines
        }
      }
    }
  });
}

export async function replyWithHealthAI(
  request: HealthAIChatRequest,
  userId: string = "user-self",
  database: DatabaseSync = getDatabase()
): Promise<HealthAIChatResponse> {
  const payload = await getHealthHomePageData(database, userId);
  const latestUserMessage = [...request.messages].reverse().find((message) => message.role === "user");

  if (!latestUserMessage) {
    throw new Error("缺少用户输入。");
  }

  try {
    const preferredProvider = getUserPreferredProvider(database, userId);
    const providerReply = await requestProviderReply(request, payload, preferredProvider);
    if (providerReply) {
      return {
        reply: {
          id: randomUUID(),
          role: "assistant",
          content: providerReply.content,
          createdAt: new Date().toISOString()
        },
        provider: providerReply.provider,
        model: providerReply.model
      };
    }
  } catch (error) {
    console.warn("[AI Chat] All providers failed, using fallback:", error instanceof Error ? error.message : error);
  }

  return {
    reply: {
      id: randomUUID(),
      role: "assistant",
      content: buildFallbackReply(latestUserMessage.content, payload),
      createdAt: new Date().toISOString()
    },
    provider: "mock",
    model: "healthai-chat-fallback-v1"
  };
}

export interface SuggestedQuestionsResponse {
  questions: string[];
  generatedAt: string;
}

export async function getSuggestedQuestions(
  userId: string,
  database: DatabaseSync = getDatabase()
): Promise<SuggestedQuestionsResponse> {
  const questions: string[] = [];
  try {
    const payload = await getHealthHomePageData(database, userId);
    const attention = (payload.overviewDigest.needsAttention ?? []) as Array<{ text?: string } | string>;

    const attentionQuestionMap: Array<{ keywords: string[]; variants: string[] }> = [
      { keywords: ["LDL", "胆固醇", "血脂"],
        variants: [
          "我的LDL胆固醇偏高，哪些食物应该避免，哪些可以多吃？",
          "我的血脂指标和上次相比有什么变化，趋势如何？",
          "LDL偏高但其他血脂正常，应该重点关注什么？",
        ] },
      { keywords: ["血压", "收缩压", "舒张压"],
        variants: [
          "我的血压趋势如何，需要就医吗？",
          "有哪些不用药物就能降血压的方法？",
        ] },
      { keywords: ["血糖", "葡萄糖", "HbA1c"],
        variants: [
          "我的血糖水平结合基因数据来看，糖尿病风险大吗？",
          "餐后血糖控制有什么实用技巧？",
        ] },
      { keywords: ["体重", "BMI", "体脂"],
        variants: [
          "根据我目前的体重和运动数据，制定一个减脂方案",
          "我的体脂率和BMI变化趋势如何？",
        ] },
      { keywords: ["尿酸"],
        variants: [
          "我的尿酸水平需要注意哪些饮食禁忌？",
          "尿酸偏高和我的其他指标有关联吗？",
        ] },
      { keywords: ["睡眠", "recovery", "恢复"],
        variants: [
          "我最近的睡眠质量数据怎么样，有改善空间吗？",
          "睡眠不好和我的哪些健康指标有关？",
        ] },
      { keywords: ["饮食", "热量", "记录覆盖"],
        variants: [
          "我的饮食热量记录和体重变化一起看，有什么问题？",
          "如果想把饮食记录得更有参考价值，接下来几天我该怎么上传？",
        ] },
    ];

    for (const item of attention.slice(0, 4)) {
      const text = typeof item === "string" ? item : (item.text ?? "");
      for (const mapping of attentionQuestionMap) {
        if (mapping.keywords.some(kw => text.includes(kw))) {
          // Pick a random variant for variety
          const variant = mapping.variants[Math.floor(Math.random() * mapping.variants.length)];
          if (!questions.includes(variant)) questions.push(variant);
          break;
        }
      }
    }

    if (payload.geneticFindings.length > 0) {
      const gf = payload.geneticFindings[0];
      questions.push(`我的${gf.traitLabel}基因检测结果对健康有什么影响？`);
      questions.push(`${gf.traitLabel}这个基因结果为什么会影响我的${gf.dimension}？`);
      if (gf.linkedMetricLabel) {
        questions.push(`${gf.traitLabel}的基因风险和我的${gf.linkedMetricLabel}结果能对应起来吗？`);
      }
    } else {
      questions.push("如果结合基因检测结果，我最适合重点关注哪些长期风险？");
    }

    const activityAnalysis = payload.dimensionAnalyses?.find((d: { key: string }) => d.key == "activity_recovery");
    if (activityAnalysis) {
      questions.push(`结合最近的运动、步数和睡眠，帮我详细分析一下${activityAnalysis.title}`);
    }
    const dietAnalysis = payload.dimensionAnalyses?.find((d: { key: string }) => d.key == "diet");
    if (dietAnalysis) {
      questions.push("饮食热量趋势和体重、体脂放在一起看，当前最需要调整什么？");
    } else {
      questions.push("如果我现在开始上传饮食图片，连续记录几天后最容易看出问题？");
    }
    questions.push("最近的体检报告里，哪几个指标最需要优先复查？");
    questions.push("综合运动、睡眠、体检、基因和饮食，帮我总结最近一个月的整体趋势");
    questions.push("给我一个覆盖训练、作息和饮食的 7 天执行计划");
  } catch { /* ignore */ }

  const generalPool = [
    "我整体的健康状况如何，有哪些需要特别关注的？",
    "如何制定适合我的运动和饮食计划？",
    "我的睡眠恢复状态会影响减脂和血脂管理吗？",
    "我的基因数据对健康管理有什么指导意义？",
    "哪些指标的趋势值得警惕，我需要提前做什么准备？",
    "我最近一个月的健康数据变化趋势是什么样的？",
    "根据我的数据，有没有需要尽快复查的项目？",
    "我的体检报告和基因数据交叉分析有什么发现？",
    "从运动和饮食两方面，给我一个本周的具体执行计划",
  ];
  const shuffled = generalPool.sort(() => Math.random() - 0.5);
  for (const q of shuffled) {
    if (!questions.includes(q) && questions.length < 10) questions.push(q);
  }
  return { questions: questions.slice(0, 10), generatedAt: new Date().toISOString() };
}
