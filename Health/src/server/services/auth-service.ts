import { createHmac, randomUUID, randomInt } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import { getAppEnv } from "../config/env";
import { getDatabase } from "../db/sqlite";

export class AuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AuthError";
  }
}

// ---------------------------------------------------------------------------
// JWT helpers (HMAC-SHA256, no external deps)
// ---------------------------------------------------------------------------

interface JWTPayload {
  sub: string;   // userId
  sid: string;   // sessionId
  iat: number;
  exp: number;
}

function base64url(input: string | Buffer): string {
  const buf = typeof input === "string" ? Buffer.from(input, "utf8") : input;
  return buf.toString("base64url");
}

function signJWT(payload: JWTPayload, secret: string): string {
  const header = base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = base64url(JSON.stringify(payload));
  const signature = createHmac("sha256", secret)
    .update(`${header}.${body}`)
    .digest("base64url");
  return `${header}.${body}.${signature}`;
}

function verifyJWT(token: string, secret: string): JWTPayload | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;

  const [header, body, signature] = parts;
  const expected = createHmac("sha256", secret)
    .update(`${header}.${body}`)
    .digest("base64url");

  if (expected !== signature) return null;

  try {
    const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as JWTPayload;
    if (payload.exp && Date.now() / 1000 > payload.exp) return null;
    return payload;
  } catch {
    return null;
  }
}

function getJWTSecret(): string {
  const env = getAppEnv();
  if (!env.HEALTH_JWT_SECRET) {
    throw new Error("HEALTH_JWT_SECRET is required when auth is enabled");
  }
  return env.HEALTH_JWT_SECRET;
}

// ---------------------------------------------------------------------------
// Verification code
// ---------------------------------------------------------------------------

const CODE_EXPIRY_SECONDS = 300; // 5 minutes
const MAX_ATTEMPTS = 5;
const SESSION_EXPIRY_DAYS = 30;

export function requestVerificationCode(
  phoneNumber: string,
  database: DatabaseSync = getDatabase()
): { code: string; expiresInSeconds: number } {
  const code = String(randomInt(100000, 999999));
  const now = new Date();
  const expiresAt = new Date(now.getTime() + CODE_EXPIRY_SECONDS * 1000);

  database.prepare(`
    INSERT INTO phone_verifications (id, phone_number, code, created_at, expires_at, attempts)
    VALUES (?, ?, ?, ?, ?, 0)
  `).run(randomUUID(), phoneNumber, code, now.toISOString(), expiresAt.toISOString());

  // Log code to console for development (replace with SMS in production)
  console.log(`[AUTH] Verification code for ${phoneNumber}: ${code}`);

  return { code, expiresInSeconds: CODE_EXPIRY_SECONDS };
}

export function verifyCodeAndLogin(
  phoneNumber: string,
  code: string,
  deviceLabel: string | undefined,
  database: DatabaseSync = getDatabase()
): { token: string; user: { id: string; display_name: string; phone_number: string } } {
  // Find the latest unexpired, unverified code for this phone
  const verification = database.prepare(`
    SELECT id, code, attempts FROM phone_verifications
    WHERE phone_number = ? AND verified_at IS NULL AND expires_at > ?
    ORDER BY created_at DESC LIMIT 1
  `).get(phoneNumber, new Date().toISOString()) as
    | { id: string; code: string; attempts: number }
    | undefined;

  if (!verification) {
    throw new Error("验证码已过期或不存在，请重新获取");
  }

  if (verification.attempts >= MAX_ATTEMPTS) {
    throw new Error("验证码尝试次数过多，请重新获取");
  }

  // Increment attempts
  database.prepare("UPDATE phone_verifications SET attempts = attempts + 1 WHERE id = ?")
    .run(verification.id);

  if (verification.code !== code) {
    throw new Error("验证码错误");
  }

  // Mark as verified
  database.prepare("UPDATE phone_verifications SET verified_at = ? WHERE id = ?")
    .run(new Date().toISOString(), verification.id);

  // Find or create user
  let user = database.prepare("SELECT id, display_name, phone_number FROM users WHERE phone_number = ?")
    .get(phoneNumber) as { id: string; display_name: string; phone_number: string } | undefined;

  if (!user) {
    const userId = `user-${randomUUID().slice(0, 8)}`;
    const displayName = `用户${phoneNumber.slice(-4)}`;
    database.prepare(`
      INSERT INTO users (id, display_name, phone_number, created_at)
      VALUES (?, ?, ?, ?)
    `).run(userId, displayName, phoneNumber, new Date().toISOString());

    user = { id: userId, display_name: displayName, phone_number: phoneNumber };
  }

  // Create session
  const sessionId = randomUUID();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + SESSION_EXPIRY_DAYS * 24 * 60 * 60 * 1000);

  const secret = getJWTSecret();
  const token = signJWT(
    {
      sub: user.id,
      sid: sessionId,
      iat: Math.floor(now.getTime() / 1000),
      exp: Math.floor(expiresAt.getTime() / 1000),
    },
    secret
  );

  const tokenHash = createHmac("sha256", secret).update(token).digest("hex");

  database.prepare(`
    INSERT INTO auth_sessions (id, user_id, token_hash, device_label, created_at, expires_at, last_active_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(sessionId, user.id, tokenHash, deviceLabel ?? null, now.toISOString(), expiresAt.toISOString(), now.toISOString());

  return {
    token,
    user: {
      id: user.id,
      display_name: user.display_name,
      phone_number: user.phone_number,
    },
  };
}

export function validateToken(
  token: string,
  database: DatabaseSync = getDatabase()
): string {
  const secret = getJWTSecret();
  const payload = verifyJWT(token, secret);
  if (!payload) {
    throw new AuthError("无效或已过期的登录凭证");
  }

  const tokenHash = createHmac("sha256", secret).update(token).digest("hex");
  const session = database.prepare(
    "SELECT id, user_id FROM auth_sessions WHERE token_hash = ? AND expires_at > ?"
  ).get(tokenHash, new Date().toISOString()) as { id: string; user_id: string } | undefined;

  if (!session) {
    throw new AuthError("会话已失效，请重新登录");
  }

  // Update last active
  database.prepare("UPDATE auth_sessions SET last_active_at = ? WHERE id = ?")
    .run(new Date().toISOString(), session.id);

  return session.user_id;
}

export function logout(
  token: string,
  database: DatabaseSync = getDatabase()
): void {
  const secret = getJWTSecret();
  const tokenHash = createHmac("sha256", secret).update(token).digest("hex");
  database.prepare("DELETE FROM auth_sessions WHERE token_hash = ?").run(tokenHash);
}

// ---------------------------------------------------------------------------
// Device-based auto-registration (no SMS needed)
// ---------------------------------------------------------------------------

export function deviceLogin(
  deviceId: string,
  deviceLabel: string | undefined,
  database: DatabaseSync = getDatabase()
): { token: string; user: { id: string; display_name: string; phone_number: string | null }; isNewUser: boolean } {
  if (!deviceId || deviceId.length < 8) {
    throw new Error("无效的设备标识");
  }

  // Find existing user by device_id
  let user = database.prepare(
    "SELECT id, display_name, phone_number FROM users WHERE device_id = ?"
  ).get(deviceId) as { id: string; display_name: string; phone_number: string | null } | undefined;

  let isNewUser = false;

  if (!user) {
    // Check if there's an unbound user we can claim (e.g. the seed user or a user who
    // previously logged in via phone on this device but has no device_id yet).
    // If there's exactly one user with no device_id, bind this device to them.
    const unboundUser = database.prepare(
      "SELECT id, display_name, phone_number FROM users WHERE device_id IS NULL"
    ).get() as { id: string; display_name: string; phone_number: string | null } | undefined;

    const unboundCount = (database.prepare(
      "SELECT COUNT(*) as cnt FROM users WHERE device_id IS NULL"
    ).get() as { cnt: number }).cnt;

    if (unboundUser && unboundCount === 1) {
      // Bind existing user to this device
      database.prepare("UPDATE users SET device_id = ? WHERE id = ?")
        .run(deviceId, unboundUser.id);
      user = unboundUser;
      console.log(`[AUTH] Bound existing user ${user.id} to device ${deviceId.slice(0, 8)}...`);
    } else {
      // Create new user bound to this device
      const userId = `user-${randomUUID().slice(0, 8)}`;
      const shortId = userId.slice(-6);
      const displayName = `用户${shortId}`;
      const now = new Date().toISOString();

      database.prepare(`
        INSERT INTO users (id, display_name, device_id, sex, birth_year, height_cm, created_at)
        VALUES (?, ?, ?, 'unknown', 1990, 170.0, ?)
      `).run(userId, displayName, deviceId, now);

      user = { id: userId, display_name: displayName, phone_number: null };
      isNewUser = true;
      console.log(`[AUTH] New device user created: ${userId} for device ${deviceId.slice(0, 8)}...`);
    }
  }

  // Create session
  const sessionId = randomUUID();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + SESSION_EXPIRY_DAYS * 24 * 60 * 60 * 1000);

  const secret = getJWTSecret();
  const token = signJWT(
    {
      sub: user.id,
      sid: sessionId,
      iat: Math.floor(now.getTime() / 1000),
      exp: Math.floor(expiresAt.getTime() / 1000),
    },
    secret
  );

  const tokenHash = createHmac("sha256", secret).update(token).digest("hex");

  database.prepare(`
    INSERT INTO auth_sessions (id, user_id, token_hash, device_label, created_at, expires_at, last_active_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(sessionId, user.id, tokenHash, deviceLabel ?? null, now.toISOString(), expiresAt.toISOString(), now.toISOString());

  console.log(`[AUTH] Device login: ${user.id} (${deviceLabel ?? "unknown device"})`);

  return {
    token,
    user: {
      id: user.id,
      display_name: user.display_name,
      phone_number: user.phone_number,
    },
    isNewUser,
  };
}

export function getUserInfo(
  userId: string,
  database: DatabaseSync = getDatabase()
): { id: string; display_name: string; phone_number: string | null } | null {
  const user = database.prepare(
    "SELECT id, display_name, phone_number FROM users WHERE id = ?"
  ).get(userId) as { id: string; display_name: string; phone_number: string | null } | undefined;

  if (!user) return null;

  return {
    id: user.id,
    display_name: user.display_name,
    phone_number: user.phone_number,
  };
}
