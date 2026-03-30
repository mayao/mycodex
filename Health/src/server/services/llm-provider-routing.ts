import type { AppEnv } from "../config/env";

export type LLMProviderName = "anthropic" | "openai_compatible" | "kimi" | "gemini";

export const BASE_PROVIDER_ORDER: LLMProviderName[] = ["kimi", "openai_compatible", "gemini"];

export function isKimiCodingKey(apiKey?: string | null): boolean {
  return !!apiKey?.startsWith("sk-kimi-");
}

export function getKimiOpenAIHeaders(apiKey?: string | null): Record<string, string> | undefined {
  if (!isKimiCodingKey(apiKey)) return undefined;
  return { "User-Agent": "KimiCLI/1.3" };
}

export function isProviderConfigured(provider: LLMProviderName, env: AppEnv): boolean {
  switch (provider) {
    case "kimi":
      return !!process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
    case "anthropic":
      return !!(env.HEALTH_LLM_API_KEY && (!env.HEALTH_LLM_PROVIDER || env.HEALTH_LLM_PROVIDER === "anthropic"));
    case "openai_compatible":
      return !!(env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_BASE_URL);
    case "gemini":
      return !!process.env.HEALTH_LLM_FALLBACK_GEMINI_KEY;
  }
}

export function getDefaultPrimaryProvider(env: AppEnv): LLMProviderName | null {
  return BASE_PROVIDER_ORDER.find((provider) => isProviderConfigured(provider, env)) ?? null;
}

export function getProviderPriority(
  env: AppEnv,
  preferredProvider?: string | null
): LLMProviderName[] {
  const preferred = BASE_PROVIDER_ORDER.find(
    (provider) => provider === preferredProvider && isProviderConfigured(provider, env)
  );

  const ordered = preferred
    ? [preferred, ...BASE_PROVIDER_ORDER.filter((provider) => provider !== preferred)]
    : BASE_PROVIDER_ORDER;

  return ordered.filter((provider) => isProviderConfigured(provider, env));
}

export async function sortProvidersByConnectivity(
  providers: LLMProviderName[],
  env: AppEnv
): Promise<LLMProviderName[]> {
  const probeResults = await Promise.all(
    providers.map(async (provider) => ({
      provider,
      ...(await probeProvider(provider, env))
    }))
  );

  return probeResults
    .sort((left, right) => {
      if (left.reachable !== right.reachable) return left.reachable ? -1 : 1;
      return left.latencyMs - right.latencyMs;
    })
    .map((item) => item.provider);
}

async function probeProvider(
  provider: LLMProviderName,
  env: AppEnv
): Promise<{ reachable: boolean; latencyMs: number }> {
  const target = probeTargetFor(provider, env);
  if (!target) return { reachable: false, latencyMs: Number.POSITIVE_INFINITY };

  const startedAt = Date.now();
  try {
    await fetch(target, {
      method: "GET",
      signal: AbortSignal.timeout(2_500)
    });
    return { reachable: true, latencyMs: Date.now() - startedAt };
  } catch {
    return { reachable: false, latencyMs: Number.POSITIVE_INFINITY };
  }
}

function probeTargetFor(provider: LLMProviderName, env: AppEnv): string | null {
  switch (provider) {
    case "kimi": {
      const kimiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
      if (!kimiKey) return null;
      return kimiKey.startsWith("sk-kimi-") ? "https://api.kimi.com" : "https://api.moonshot.cn";
    }
    case "anthropic":
      return isProviderConfigured("anthropic", env) ? "https://api.anthropic.com/v1/messages" : null;
    case "openai_compatible":
      return env.HEALTH_LLM_BASE_URL ?? null;
    case "gemini":
      return isProviderConfigured("gemini", env)
        ? "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        : null;
  }
}
