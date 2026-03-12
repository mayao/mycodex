import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import { getDatabase } from "../db/sqlite";

export type DeviceProvider = "huawei" | "garmin" | "coros";

interface DeviceOAuthConfig {
  provider: DeviceProvider;
  label: string;
  authUrl: string;
  tokenUrl: string;
  scope: string;
  clientIdEnv: string;
  clientSecretEnv: string;
}

const DEVICE_CONFIGS: Record<DeviceProvider, DeviceOAuthConfig> = {
  huawei: {
    provider: "huawei",
    label: "华为运动健康",
    authUrl: "https://oauth-login.cloud.huawei.com/oauth2/v3/authorize",
    tokenUrl: "https://oauth-login.cloud.huawei.com/oauth2/v3/token",
    scope: "https://www.huawei.com/healthkit/activity.read https://www.huawei.com/healthkit/heartrate.read https://www.huawei.com/healthkit/sleep.read https://www.huawei.com/healthkit/bodyweight.read",
    clientIdEnv: "HUAWEI_HEALTH_CLIENT_ID",
    clientSecretEnv: "HUAWEI_HEALTH_CLIENT_SECRET",
  },
  garmin: {
    provider: "garmin",
    label: "Garmin 佳明",
    authUrl: "https://connect.garmin.com/oauthConfirm",
    tokenUrl: "https://connectapi.garmin.com/oauth-service/oauth/access_token",
    scope: "",
    clientIdEnv: "GARMIN_CLIENT_ID",
    clientSecretEnv: "GARMIN_CLIENT_SECRET",
  },
  coros: {
    provider: "coros",
    label: "COROS 高驰",
    authUrl: "https://open.coros.com/oauth2/authorize",
    tokenUrl: "https://open.coros.com/oauth2/accesstoken",
    scope: "read_activity read_sleep read_heart_rate",
    clientIdEnv: "COROS_CLIENT_ID",
    clientSecretEnv: "COROS_CLIENT_SECRET",
  },
};

function ensureDeviceTokensTable(db: DatabaseSync) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS device_tokens (
      id TEXT PRIMARY KEY,
      provider TEXT NOT NULL UNIQUE,
      access_token TEXT NOT NULL,
      refresh_token TEXT,
      expires_at TEXT,
      connected_at TEXT NOT NULL,
      last_sync_at TEXT
    )
  `);
}

export function getDeviceConfig(provider: DeviceProvider): DeviceOAuthConfig | null {
  return DEVICE_CONFIGS[provider] ?? null;
}

export function isDeviceConfigured(provider: DeviceProvider): boolean {
  const config = DEVICE_CONFIGS[provider];
  if (!config) return false;
  const clientId = process.env[config.clientIdEnv];
  const clientSecret = process.env[config.clientSecretEnv];
  return Boolean(clientId && clientSecret);
}

export function buildAuthorizationUrl(
  provider: DeviceProvider,
  callbackUrl: string,
  state: string
): string | null {
  const config = DEVICE_CONFIGS[provider];
  if (!config) return null;

  const clientId = process.env[config.clientIdEnv];
  if (!clientId) return null;

  const params = new URLSearchParams({
    response_type: "code",
    client_id: clientId,
    redirect_uri: callbackUrl,
    state,
    scope: config.scope,
  });

  return `${config.authUrl}?${params.toString()}`;
}

export async function exchangeCodeForTokens(
  provider: DeviceProvider,
  code: string,
  callbackUrl: string,
  database: DatabaseSync = getDatabase()
): Promise<{ success: boolean; error?: string }> {
  const config = DEVICE_CONFIGS[provider];
  if (!config) return { success: false, error: "Unknown provider" };

  const clientId = process.env[config.clientIdEnv];
  const clientSecret = process.env[config.clientSecretEnv];

  if (!clientId || !clientSecret) {
    return { success: false, error: "Provider not configured" };
  }

  try {
    const response = await fetch(config.tokenUrl, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: callbackUrl,
      }),
    });

    if (!response.ok) {
      const text = await response.text().catch(() => "");
      return { success: false, error: `Token exchange failed: ${response.status} ${text.slice(0, 200)}` };
    }

    const tokenData = (await response.json()) as {
      access_token?: string;
      refresh_token?: string;
      expires_in?: number;
    };

    if (!tokenData.access_token) {
      return { success: false, error: "No access token received" };
    }

    ensureDeviceTokensTable(database);

    const expiresAt = tokenData.expires_in
      ? new Date(Date.now() + tokenData.expires_in * 1000).toISOString()
      : null;

    const stmt = database.prepare(`
      INSERT INTO device_tokens (id, provider, access_token, refresh_token, expires_at, connected_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(provider) DO UPDATE SET
        access_token = excluded.access_token,
        refresh_token = excluded.refresh_token,
        expires_at = excluded.expires_at,
        connected_at = excluded.connected_at
    `);

    stmt.run(
      randomUUID(),
      provider,
      tokenData.access_token,
      tokenData.refresh_token ?? null,
      expiresAt,
      new Date().toISOString()
    );

    return { success: true };
  } catch (error) {
    return { success: false, error: String(error) };
  }
}

export function getDeviceConnectionStatus(
  database: DatabaseSync = getDatabase()
): Array<{
  provider: string;
  label: string;
  isConnected: boolean;
  isConfigured: boolean;
  connectedAt: string | null;
  lastSyncAt: string | null;
}> {
  ensureDeviceTokensTable(database);

  const rows = database.prepare("SELECT provider, connected_at, last_sync_at FROM device_tokens").all() as Array<{
    provider: string;
    connected_at: string;
    last_sync_at: string | null;
  }>;

  const connectedMap = new Map(rows.map((r) => [r.provider, r]));

  return (Object.keys(DEVICE_CONFIGS) as DeviceProvider[]).map((provider) => {
    const config = DEVICE_CONFIGS[provider];
    const connection = connectedMap.get(provider);

    return {
      provider,
      label: config.label,
      isConnected: Boolean(connection),
      isConfigured: isDeviceConfigured(provider),
      connectedAt: connection?.connected_at ?? null,
      lastSyncAt: connection?.last_sync_at ?? null,
    };
  });
}

export function disconnectDevice(
  provider: DeviceProvider,
  database: DatabaseSync = getDatabase()
): boolean {
  ensureDeviceTokensTable(database);
  const stmt = database.prepare("DELETE FROM device_tokens WHERE provider = ?");
  stmt.run(provider);
  return true;
}
