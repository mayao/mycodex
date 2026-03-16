import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getAppEnv } from "../../../../server/config/env";
import { getDatabase } from "../../../../server/db/sqlite";
import { getUserPreferredProvider, setUserPreferredProvider } from "../../../../server/services/llm-preference-service";

export const dynamic = "force-dynamic";

function buildProviders(preferredProvider: string | null) {
  const env = getAppEnv();
  const kimiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
  const geminiKey = process.env.HEALTH_LLM_FALLBACK_GEMINI_KEY;
  const anthropicOk = !!(env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "anthropic");
  const openaiOk = !!(env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_BASE_URL);

  const providers = [
    { name: "anthropic", label: "Claude (Anthropic)", isConfigured: anthropicOk, isPrimary: preferredProvider === "anthropic" || (!preferredProvider && env.HEALTH_LLM_PROVIDER === "anthropic"), model: anthropicOk ? (env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514") : null },
    { name: "openai_compatible", label: "OpenAI 兼容", isConfigured: openaiOk, isPrimary: preferredProvider === "openai_compatible" || (!preferredProvider && env.HEALTH_LLM_PROVIDER === "openai-compatible"), model: openaiOk ? (env.HEALTH_LLM_MODEL ?? null) : null },
    { name: "kimi", label: "Kimi（月之暗面）", isConfigured: !!kimiKey, isPrimary: preferredProvider === "kimi", model: kimiKey ? (process.env.HEALTH_LLM_FALLBACK_KIMI_MODEL ?? "kimi-for-coding") : null },
    { name: "gemini", label: "Gemini（Google）", isConfigured: !!geminiKey, isPrimary: preferredProvider === "gemini", model: geminiKey ? (process.env.HEALTH_LLM_FALLBACK_GEMINI_MODEL ?? "gemini-2.0-flash") : null },
  ];
  const activeProvider = providers.find(p => p.isPrimary && p.isConfigured)?.name ?? null;
  return { providers, activeProvider };
}

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const db = getDatabase();
    const preferredProvider = getUserPreferredProvider(db, userId);
    return jsonOk(buildProviders(preferredProvider));
  } catch (error) {
    if (error instanceof AuthError) return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/ai/model-status" } });
    return jsonSafeError({ message: "获取模型状态失败", status: 500, error, context: { route: "/api/ai/model-status" } });
  }
}

export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const body = (await request.json()) as { provider?: string };
    const provider = body.provider ?? null;

    const validProviders = ["anthropic", "openai_compatible", "kimi", "gemini"];
    if (provider && !validProviders.includes(provider)) {
      return jsonSafeError({ message: "无效的模型提供商", status: 400, error: new Error("invalid provider"), context: { route: "/api/ai/model-status" } });
    }

    const db = getDatabase();
    setUserPreferredProvider(db, userId, provider);

    return jsonOk(buildProviders(provider));
  } catch (error) {
    if (error instanceof AuthError) return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/ai/model-status" } });
    return jsonSafeError({ message: "设置模型偏好失败", status: 500, error, context: { route: "/api/ai/model-status" } });
  }
}
