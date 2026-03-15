import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getAppEnv } from "../../../../server/config/env";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    getAuthenticatedUserId(request);
    const env = getAppEnv();
    const kimiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
    const geminiKey = process.env.HEALTH_LLM_FALLBACK_GEMINI_KEY;
    const anthropicOk = !!(env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "anthropic");
    const openaiOk = !!(env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_BASE_URL);

    const providers = [
      { name: "anthropic", label: "Claude (Anthropic)", isConfigured: anthropicOk, isPrimary: env.HEALTH_LLM_PROVIDER === "anthropic", model: anthropicOk ? (env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514") : null },
      { name: "openai_compatible", label: "OpenAI 兼容", isConfigured: openaiOk, isPrimary: env.HEALTH_LLM_PROVIDER === "openai-compatible", model: openaiOk ? (env.HEALTH_LLM_MODEL ?? null) : null },
      { name: "kimi", label: "Kimi（月之暗面）", isConfigured: !!kimiKey, isPrimary: false, model: kimiKey ? (process.env.HEALTH_LLM_FALLBACK_KIMI_MODEL ?? "kimi-for-coding") : null },
      { name: "gemini", label: "Gemini（Google）", isConfigured: !!geminiKey, isPrimary: false, model: geminiKey ? (process.env.HEALTH_LLM_FALLBACK_GEMINI_MODEL ?? "gemini-2.0-flash") : null },
    ];
    const activeProvider = providers.find(p => p.isPrimary && p.isConfigured)?.name ?? null;
    return jsonOk({ providers, activeProvider });
  } catch (error) {
    if (error instanceof AuthError) return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/ai/model-status" } });
    return jsonSafeError({ message: "获取模型状态失败", status: 500, error, context: { route: "/api/ai/model-status" } });
  }
}
