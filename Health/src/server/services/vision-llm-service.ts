import { readFile } from "node:fs/promises";
import { extname } from "node:path";

import { getAppEnv } from "../config/env";
import {
  getKimiOpenAIHeaders,
  getProviderPriority,
  type LLMProviderName
} from "./llm-provider-routing";

export interface VisionLLMResult {
  text: string;
  provider: LLMProviderName;
  model: string;
}

interface VisionPayload {
  imageBase64: string;
  mediaType: string;
}

type ProviderResult = VisionLLMResult;

const IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".webp", ".heic", ".heif"]);

export function isVisionImageFile(fileName: string): boolean {
  return IMAGE_EXTENSIONS.has(extname(fileName).toLowerCase());
}

function inferMediaType(filePath: string): string {
  const extension = extname(filePath).toLowerCase();

  switch (extension) {
    case ".png":
      return "image/png";
    case ".webp":
      return "image/webp";
    case ".heic":
    case ".heif":
      return "image/heic";
    default:
      return "image/jpeg";
  }
}

async function loadVisionPayload(filePath: string): Promise<VisionPayload> {
  return {
    imageBase64: (await readFile(filePath)).toString("base64"),
    mediaType: inferMediaType(filePath)
  };
}

async function callOpenAIStyleVision(params: {
  baseUrl: string;
  apiKey: string;
  model: string;
  prompt: string;
  provider: LLMProviderName;
  imageBase64: string;
  mediaType: string;
  extraHeaders?: Record<string, string>;
  timeoutMs: number;
}): Promise<ProviderResult> {
  const response = await fetch(`${params.baseUrl.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    signal: AbortSignal.timeout(params.timeoutMs),
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${params.apiKey}`,
      ...(getKimiOpenAIHeaders(params.apiKey) ?? {}),
      ...params.extraHeaders
    },
    body: JSON.stringify({
      model: params.model,
      temperature: 0,
      max_tokens: 4096,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: params.prompt },
            {
              type: "image_url",
              image_url: {
                url: `data:${params.mediaType};base64,${params.imageBase64}`
              }
            }
          ]
        }
      ]
    })
  });

  if (!response.ok) {
    throw new Error(`${params.provider}_vision_${response.status}`);
  }

  const payload = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
    model?: string;
  };

  return {
    text: payload.choices?.[0]?.message?.content ?? "",
    provider: params.provider,
    model: payload.model ?? params.model
  };
}

async function callAnthropicVision(params: {
  apiKey: string;
  model: string;
  prompt: string;
  imageBase64: string;
  mediaType: string;
  timeoutMs: number;
}): Promise<ProviderResult> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    signal: AbortSignal.timeout(params.timeoutMs),
    headers: {
      "Content-Type": "application/json",
      "x-api-key": params.apiKey,
      "anthropic-version": "2023-06-01"
    },
    body: JSON.stringify({
      model: params.model,
      max_tokens: 4096,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: params.mediaType,
                data: params.imageBase64
              }
            },
            {
              type: "text",
              text: params.prompt
            }
          ]
        }
      ]
    })
  });

  if (!response.ok) {
    throw new Error(`anthropic_vision_${response.status}`);
  }

  const payload = (await response.json()) as {
    content?: Array<{ type: string; text?: string }>;
    model?: string;
  };

  return {
    text:
      payload.content
        ?.filter((item) => item.type === "text")
        .map((item) => item.text ?? "")
        .join("\n") ?? "",
    provider: "anthropic",
    model: payload.model ?? params.model
  };
}

async function callProviderVision(
  provider: LLMProviderName,
  payload: VisionPayload,
  prompt: string,
  timeoutMs: number
): Promise<ProviderResult> {
  const env = getAppEnv();

  switch (provider) {
    case "openai_compatible":
      if (!(env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_BASE_URL)) {
        throw new Error("openai_compatible_not_configured");
      }
      return callOpenAIStyleVision({
        baseUrl: env.HEALTH_LLM_BASE_URL,
        apiKey: env.HEALTH_LLM_API_KEY,
        model: env.HEALTH_LLM_MODEL ?? "gpt-4.1-mini",
        prompt,
        provider,
        imageBase64: payload.imageBase64,
        mediaType: payload.mediaType,
        timeoutMs
      });

    case "anthropic":
      if (!(env.HEALTH_LLM_PROVIDER === "anthropic" && env.HEALTH_LLM_API_KEY)) {
        throw new Error("anthropic_not_configured");
      }
      return callAnthropicVision({
        apiKey: env.HEALTH_LLM_API_KEY,
        model: env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514",
        prompt,
        imageBase64: payload.imageBase64,
        mediaType: payload.mediaType,
        timeoutMs
      });

    case "kimi": {
      const kimiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
      if (!kimiKey) {
        throw new Error("kimi_not_configured");
      }
      const baseUrl = kimiKey.startsWith("sk-kimi-") ? "https://api.kimi.com/coding/v1" : "https://api.moonshot.cn/v1";
      const model =
        process.env.HEALTH_LLM_FALLBACK_KIMI_VISION_MODEL ??
        process.env.HEALTH_LLM_FALLBACK_KIMI_MODEL ??
        "moonshot-v1-8k-vision-preview";
      return callOpenAIStyleVision({
        baseUrl,
        apiKey: kimiKey,
        model,
        prompt,
        provider,
        imageBase64: payload.imageBase64,
        mediaType: payload.mediaType,
        extraHeaders: kimiKey.startsWith("sk-kimi-") ? { "User-Agent": "KimiCLI/1.3" } : undefined,
        timeoutMs
      });
    }

    case "gemini": {
      const geminiKey = process.env.HEALTH_LLM_FALLBACK_GEMINI_KEY;
      if (!geminiKey) {
        throw new Error("gemini_not_configured");
      }
      const model =
        process.env.HEALTH_LLM_FALLBACK_GEMINI_VISION_MODEL ??
        process.env.HEALTH_LLM_FALLBACK_GEMINI_MODEL ??
        "gemini-2.5-flash";
      return callOpenAIStyleVision({
        baseUrl: "https://generativelanguage.googleapis.com/v1beta/openai",
        apiKey: geminiKey,
        model,
        prompt,
        provider,
        imageBase64: payload.imageBase64,
        mediaType: payload.mediaType,
        timeoutMs
      });
    }
  }
}

export async function callVisionLLMWithFallbacks(params: {
  prompt: string;
  filePath: string;
  preferredProvider?: string | null;
  timeoutMs?: number;
}): Promise<VisionLLMResult> {
  const env = getAppEnv();
  const providers = getProviderPriority(env, params.preferredProvider);

  if (providers.length === 0) {
    throw new Error("当前环境没有可用的图像分析模型。");
  }

  const payload = await loadVisionPayload(params.filePath);
  const timeoutMs = params.timeoutMs ?? 30_000;
  let lastError: unknown;

  for (const provider of providers) {
    try {
      const result = await callProviderVision(provider, payload, params.prompt, timeoutMs);
      if (result.text.trim().length === 0) {
        throw new Error(`${provider}_vision_empty_response`);
      }
      return result;
    } catch (error) {
      lastError = error;
      const message = error instanceof Error ? error.message : String(error);
      console.warn(`[VisionLLM] ${provider} failed: ${message}`);
    }
  }

  throw new Error(
    lastError instanceof Error
      ? `图像分析失败：${lastError.message}`
      : "图像分析失败：没有从视觉模型获得可用结果。"
  );
}
