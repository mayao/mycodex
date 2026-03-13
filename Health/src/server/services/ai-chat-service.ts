import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import { z } from "zod";

import { getAppEnv } from "../config/env";
import { getDatabase } from "../db/sqlite";
import { getHealthHomePageData } from "./health-home-service";

const chatMessageSchema = z.object({
  id: z.string().optional(),
  role: z.enum(["user", "assistant"]),
  content: z.string().trim().min(1).max(4000),
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
  return [
    "你是 HealthAI App 内的健康助手。",
    "你的回答必须基于给定的健康仪表盘上下文，优先给出清晰、个性化、非医疗诊断的解释与下一步建议。",
    "不要夸大结论，不要给药物处方，不要假装看到了上下文之外的数据。",
    "回答尽量控制在 3 段以内，适合手机端阅读。",
    "如果用户提到上传、同步、Apple 健康或数据更新，也可以给出产品内操作建议。",
    `当前用户上下文:\n${JSON.stringify(buildChatContext(payload), null, 2)}`
  ].join("\n\n");
}

async function requestAnthropicReply(
  request: HealthAIChatRequest,
  payload: Awaited<ReturnType<typeof getHealthHomePageData>>,
  apiKey: string,
  model: string
) {
  const systemPrompt = buildSystemPrompt(payload);

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01"
    },
    body: JSON.stringify({
      model,
      max_tokens: 1024,
      system: systemPrompt,
      messages: request.messages.map((message) => ({
        role: message.role,
        content: message.content
      }))
    })
  });

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
  model: string
) {
  const systemPrompt = buildSystemPrompt(payload);

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
        ...request.messages.map((message) => ({
          role: message.role,
          content: message.content
        }))
      ]
    })
  });

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
  payload: Awaited<ReturnType<typeof getHealthHomePageData>>
) {
  const env = getAppEnv();

  if (!env.HEALTH_LLM_API_KEY) {
    return null;
  }

  if (env.HEALTH_LLM_PROVIDER === "anthropic") {
    const model = env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514";
    return requestAnthropicReply(request, payload, env.HEALTH_LLM_API_KEY, model);
  }

  if (env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_BASE_URL) {
    const model = env.HEALTH_LLM_MODEL ?? "gpt-4.1-mini";
    return requestOpenAICompatibleReply(
      request, payload, env.HEALTH_LLM_API_KEY, env.HEALTH_LLM_BASE_URL, model
    );
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
    const providerReply = await requestProviderReply(request, payload);
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
  } catch {
    // Fall back to the local response when the external model is unavailable.
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
