import { createPublicKey, verify as verifySignature, type JsonWebKey } from "node:crypto";

import { getAppEnv } from "../config/env";

interface AppleTokenHeader {
  alg?: string;
  kid?: string;
}

interface AppleTokenPayload {
  iss?: string;
  aud?: string | string[];
  exp?: number;
  iat?: number;
  sub?: string;
  email?: string;
  email_verified?: boolean | string;
  nonce_supported?: boolean;
  is_private_email?: boolean | string;
}

interface AppleJWKSKey {
  kty: "RSA";
  kid: string;
  use?: string;
  alg?: string;
  n: string;
  e: string;
}

interface AppleJWKSResponse {
  keys: AppleJWKSKey[];
}

export interface VerifiedAppleIdentity {
  subject: string;
  email: string | null;
  emailVerified: boolean;
  rawClaims: AppleTokenPayload;
}

export interface AppleTokenVerificationOptions {
  acceptedAudiences?: string[];
  fetcher?: typeof fetch;
}

const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEY_CACHE_TTL_MS = 10 * 60 * 1000;

let cachedKeys:
  | {
      fetchedAt: number;
      keys: AppleJWKSKey[];
    }
  | undefined;

function decodeJWTPart<T>(part: string): T {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as T;
}

function resolveAcceptedAudiences(explicit?: string[]): string[] {
  if (explicit && explicit.length > 0) {
    return explicit;
  }

  const env = getAppEnv();
  return [env.HEALTH_APPLE_CLIENT_ID ?? "com.xihe.healthai"];
}

async function fetchAppleKeys(fetcher: typeof fetch = fetch): Promise<AppleJWKSKey[]> {
  if (cachedKeys && Date.now() - cachedKeys.fetchedAt < APPLE_KEY_CACHE_TTL_MS) {
    return cachedKeys.keys;
  }

  const response = await fetcher(APPLE_KEYS_URL, {
    headers: {
      Accept: "application/json"
    }
  });

  if (!response.ok) {
    throw new Error(`无法获取 Apple 公钥（${response.status}）`);
  }

  const payload = (await response.json()) as AppleJWKSResponse;
  if (!payload.keys?.length) {
    throw new Error("Apple 公钥列表为空");
  }

  cachedKeys = {
    fetchedAt: Date.now(),
    keys: payload.keys
  };

  return payload.keys;
}

function isTruthyClaim(value: boolean | string | undefined): boolean {
  return value === true || value === "true";
}

export function clearAppleKeyCacheForTests(): void {
  cachedKeys = undefined;
}

export async function verifyAppleIdentityToken(
  identityToken: string,
  options: AppleTokenVerificationOptions = {}
): Promise<VerifiedAppleIdentity> {
  const parts = identityToken.split(".");
  if (parts.length !== 3) {
    throw new Error("Apple 身份令牌格式无效");
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = decodeJWTPart<AppleTokenHeader>(encodedHeader);
  const payload = decodeJWTPart<AppleTokenPayload>(encodedPayload);

  if (header.alg !== "RS256" || !header.kid) {
    throw new Error("Apple 身份令牌算法无效");
  }

  if (payload.iss !== APPLE_ISSUER) {
    throw new Error("Apple 身份令牌签发方无效");
  }

  const acceptedAudiences = resolveAcceptedAudiences(options.acceptedAudiences);
  const tokenAudiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!tokenAudiences.some((audience) => audience && acceptedAudiences.includes(audience))) {
    throw new Error("Apple 身份令牌 audience 不匹配");
  }

  if (!payload.sub) {
    throw new Error("Apple 身份令牌缺少用户标识");
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (!payload.exp || payload.exp <= nowSeconds) {
    throw new Error("Apple 身份令牌已过期");
  }

  const keys = await fetchAppleKeys(options.fetcher);
  const matchingKey = keys.find((key) => key.kid === header.kid);
  if (!matchingKey) {
    throw new Error("未找到匹配的 Apple 公钥");
  }

  const publicKey = createPublicKey({
    key: {
      kty: matchingKey.kty,
      kid: matchingKey.kid,
      use: matchingKey.use,
      alg: matchingKey.alg ?? "RS256",
      n: matchingKey.n,
      e: matchingKey.e,
      ext: true
    } as JsonWebKey,
    format: "jwk"
  });

  const signatureValid = verifySignature(
    "RSA-SHA256",
    Buffer.from(`${encodedHeader}.${encodedPayload}`, "utf8"),
    publicKey,
    Buffer.from(encodedSignature, "base64url")
  );

  if (!signatureValid) {
    throw new Error("Apple 身份令牌签名校验失败");
  }

  return {
    subject: payload.sub,
    email: payload.email ?? null,
    emailVerified: isTruthyClaim(payload.email_verified),
    rawClaims: payload
  };
}
