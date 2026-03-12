import { randomUUID } from "node:crypto";

import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import {
  buildAuthorizationUrl,
  getDeviceConfig,
  isDeviceConfigured,
  type DeviceProvider,
} from "../../../../server/services/device-auth-service";

export const dynamic = "force-dynamic";

const VALID_PROVIDERS = new Set(["huawei", "garmin", "coros"]);

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { provider?: string; callbackUrl?: string };
    const provider = body.provider as DeviceProvider;

    if (!provider || !VALID_PROVIDERS.has(provider)) {
      return jsonSafeError({
        message: "不支持的设备提供商",
        status: 400,
        context: { route: "/api/devices/authorize", method: "POST" },
      });
    }

    if (!isDeviceConfigured(provider)) {
      const config = getDeviceConfig(provider);
      return jsonSafeError({
        message: `${config?.label ?? provider} 的开发者密钥尚未配置，请联系管理员设置 ${config?.clientIdEnv} 和 ${config?.clientSecretEnv} 环境变量。`,
        status: 501,
        context: { route: "/api/devices/authorize", method: "POST" },
      });
    }

    const state = randomUUID();
    const callbackUrl = body.callbackUrl ?? `${request.headers.get("origin") ?? "http://localhost:3000"}/api/devices/callback`;

    const authUrl = buildAuthorizationUrl(provider, callbackUrl, state);

    if (!authUrl) {
      return jsonSafeError({
        message: "无法生成授权链接",
        status: 500,
        context: { route: "/api/devices/authorize", method: "POST" },
      });
    }

    return jsonOk({ authUrl, state, provider });
  } catch (error) {
    return jsonSafeError({
      message: "设备授权暂时不可用",
      status: 400,
      error,
      context: { route: "/api/devices/authorize", method: "POST" },
    });
  }
}
