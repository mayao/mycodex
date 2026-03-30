import { createHash, createHmac, randomInt, randomUUID, timingSafeEqual } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import { getAppEnv } from "../config/env";
import { getDatabase } from "../db/sqlite";
import { verifyAppleIdentityToken, type VerifiedAppleIdentity } from "./apple-auth-service";

export class AuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AuthError";
  }
}

type IdentityProvider = "device" | "phone" | "apple";

interface JWTPayload {
  sub: string;
  sid: string;
  iat: number;
  exp: number;
}

interface UserRow {
  id: string;
  display_name: string;
  phone_number: string | null;
  device_id: string | null;
  created_at: string | null;
  updated_at: string | null;
  merged_into_user_id: string | null;
  is_disabled: number | null;
  origin_server_id: string | null;
}

interface UserIdentityRow {
  id: string;
  user_id: string;
  provider: IdentityProvider;
  provider_subject: string;
  email: string | null;
  claims_json: string | null;
  created_at: string;
  updated_at: string;
  origin_server_id: string | null;
}

interface UserInfoPayload {
  id: string;
  display_name: string;
  phone_number: string | null;
  email: string | null;
  auth_providers: Array<{
    provider: IdentityProvider;
    linked_at: string | null;
    email: string | null;
  }>;
  has_apple_linked: boolean;
}

interface AuthResponsePayload {
  token: string;
  user: UserInfoPayload;
}

interface AppleAuthRequest {
  identityToken: string;
  authorizationCode?: string;
  email?: string;
  displayName?: string;
}

interface AppleIdentityVerifier {
  (identityToken: string): Promise<VerifiedAppleIdentity>;
}

const CODE_EXPIRY_SECONDS = 300;
const MAX_ATTEMPTS = 5;
const SESSION_EXPIRY_DAYS = 30;
const LAST_ACTIVE_UPDATE_INTERVAL_MS = 5 * 60 * 1000;
const lastActiveCache = new Map<string, number>();

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

  const expectedBuf = Buffer.from(expected, "utf8");
  const signatureBuf = Buffer.from(signature, "utf8");
  if (expectedBuf.length !== signatureBuf.length || !timingSafeEqual(expectedBuf, signatureBuf)) {
    return null;
  }

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

function normalizeIdentitySubject(provider: IdentityProvider, subject: string): string {
  const trimmed = subject.trim();
  if (provider === "device") {
    return trimmed.toLowerCase();
  }
  if (provider === "phone") {
    return trimmed.replace(/\D/g, "");
  }
  return trimmed;
}

function makeIdentityId(provider: IdentityProvider, subject: string): string {
  return `identity::${provider}::${normalizeIdentitySubject(provider, subject)}`;
}

function makeStableUserId(provider: IdentityProvider, subject: string): string {
  const digest = createHash("sha256")
    .update(`${provider}:${normalizeIdentitySubject(provider, subject)}`)
    .digest("hex")
    .slice(0, 12);
  return `user-${provider}-${digest}`;
}

function defaultDisplayNameForIdentity(
  provider: IdentityProvider,
  subject: string,
  options: {
    deviceLabel?: string;
    email?: string | null;
    displayName?: string | null;
  } = {}
): string {
  const preferred = options.displayName?.trim();
  if (preferred) {
    return preferred;
  }

  if (provider === "phone") {
    return `用户${subject.slice(-4)}`;
  }

  if (provider === "device") {
    const label = options.deviceLabel?.trim();
    if (label) {
      return label;
    }
  }

  if (provider === "apple") {
    const email = options.email?.trim();
    if (email) {
      const localPart = email.split("@")[0]?.trim();
      if (localPart) {
        return localPart;
      }
    }
    return `Apple用户${createHash("sha256").update(subject).digest("hex").slice(0, 6)}`;
  }

  return `用户${createHash("sha256").update(subject).digest("hex").slice(0, 6)}`;
}

function isGenericDisplayName(displayName: string | null | undefined): boolean {
  const value = displayName?.trim();
  if (!value) return true;
  return /^用户[0-9a-f]+$/i.test(value) || value === "测试账号";
}

function getCurrentServerId(database: DatabaseSync): string | null {
  const row = database.prepare("SELECT value FROM app_meta WHERE key = ?").get("server_id") as { value: string } | undefined;
  return row?.value ?? null;
}

function getUserRow(userId: string, database: DatabaseSync = getDatabase()): UserRow | null {
  const row = database.prepare(`
    SELECT
      id,
      display_name,
      phone_number,
      device_id,
      created_at,
      updated_at,
      merged_into_user_id,
      is_disabled,
      origin_server_id
    FROM users
    WHERE id = ?
  `).get(userId) as UserRow | undefined;

  return row ?? null;
}

export function resolveCanonicalUserId(
  userId: string,
  database: DatabaseSync = getDatabase()
): string {
  let current = userId;
  const visited = new Set<string>();

  while (true) {
    if (visited.has(current)) {
      throw new AuthError("账号合并链路异常，请联系开发者处理");
    }
    visited.add(current);

    const row = database.prepare(`
      SELECT merged_into_user_id
      FROM users
      WHERE id = ?
    `).get(current) as { merged_into_user_id: string | null } | undefined;

    if (!row?.merged_into_user_id) {
      return current;
    }

    current = row.merged_into_user_id;
  }
}

function listUserIdentityRows(
  userId: string,
  database: DatabaseSync = getDatabase()
): UserIdentityRow[] {
  const canonicalUserId = resolveCanonicalUserId(userId, database);
  return database.prepare(`
    SELECT
      id,
      user_id,
      provider,
      provider_subject,
      email,
      claims_json,
      created_at,
      updated_at,
      origin_server_id
    FROM user_identity
    WHERE user_id = ?
    ORDER BY created_at ASC
  `).all(canonicalUserId) as unknown as UserIdentityRow[];
}

function maybePromoteDisplayName(
  userId: string,
  displayName: string | null | undefined,
  database: DatabaseSync = getDatabase()
): void {
  const normalized = displayName?.trim();
  if (!normalized) {
    return;
  }

  const user = getUserRow(userId, database);
  if (!user) {
    return;
  }

  if (!isGenericDisplayName(user.display_name)) {
    return;
  }

  database.prepare(`
    UPDATE users
    SET display_name = ?, updated_at = ?
    WHERE id = ?
  `).run(normalized, new Date().toISOString(), userId);
}

function syncLegacyUserColumns(
  userId: string,
  database: DatabaseSync = getDatabase()
): void {
  const canonicalUserId = resolveCanonicalUserId(userId, database);
  const identities = listUserIdentityRows(canonicalUserId, database);
  const phoneIdentity = identities.find((identity) => identity.provider === "phone");
  const deviceIdentity = identities.find((identity) => identity.provider === "device");

  database.prepare(`
    UPDATE users
    SET
      phone_number = ?,
      device_id = ?,
      updated_at = ?
    WHERE id = ?
  `).run(
    phoneIdentity?.provider_subject ?? null,
    deviceIdentity?.provider_subject ?? null,
    new Date().toISOString(),
    canonicalUserId
  );
}

function getIdentityOwner(
  provider: IdentityProvider,
  subject: string,
  database: DatabaseSync = getDatabase()
): string | null {
  const normalizedSubject = normalizeIdentitySubject(provider, subject);
  const row = database.prepare(`
    SELECT user_id
    FROM user_identity
    WHERE provider = ? AND provider_subject = ?
  `).get(provider, normalizedSubject) as { user_id: string } | undefined;

  if (row?.user_id) {
    return resolveCanonicalUserId(row.user_id, database);
  }

  if (provider === "phone") {
    const legacy = database.prepare(`
      SELECT id
      FROM users
      WHERE phone_number = ?
    `).get(normalizedSubject) as { id: string } | undefined;
    if (legacy?.id) {
      return resolveCanonicalUserId(legacy.id, database);
    }
  }

  if (provider === "device") {
    const legacy = database.prepare(`
      SELECT id
      FROM users
      WHERE lower(device_id) = ?
    `).get(normalizedSubject) as { id: string } | undefined;
    if (legacy?.id) {
      return resolveCanonicalUserId(legacy.id, database);
    }
  }

  return null;
}

function ensureUserRecord(
  provider: IdentityProvider,
  subject: string,
  options: {
    displayName?: string | null;
    deviceLabel?: string;
    email?: string | null;
  } = {},
  database: DatabaseSync = getDatabase()
): { userId: string; isNewUser: boolean } {
  const normalizedSubject = normalizeIdentitySubject(provider, subject);
  const userId = makeStableUserId(provider, normalizedSubject);
  const existing = getUserRow(userId, database);

  if (existing) {
    maybePromoteDisplayName(userId, options.displayName, database);
    return {
      userId,
      isNewUser: false
    };
  }

  const now = new Date().toISOString();
  const displayName = defaultDisplayNameForIdentity(provider, normalizedSubject, {
    deviceLabel: options.deviceLabel,
    email: options.email,
    displayName: options.displayName
  });

  database.prepare(`
    INSERT INTO users (
      id,
      display_name,
      phone_number,
      device_id,
      sex,
      birth_year,
      height_cm,
      created_at,
      updated_at,
      origin_server_id,
      is_disabled
    )
    VALUES (?, ?, ?, ?, 'unknown', 1990, 170.0, ?, ?, ?, 0)
  `).run(
    userId,
    displayName,
    provider === "phone" ? normalizedSubject : null,
    provider === "device" ? normalizedSubject : null,
    now,
    now,
    getCurrentServerId(database)
  );

  return {
    userId,
    isNewUser: true
  };
}

function upsertIdentityRow(
  provider: IdentityProvider,
  subject: string,
  userId: string,
  options: {
    email?: string | null;
    claimsJson?: string | null;
  } = {},
  database: DatabaseSync = getDatabase()
): void {
  const normalizedSubject = normalizeIdentitySubject(provider, subject);
  const now = new Date().toISOString();

  database.prepare(`
    INSERT INTO user_identity (
      id,
      user_id,
      provider,
      provider_subject,
      email,
      claims_json,
      created_at,
      updated_at,
      origin_server_id
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(provider, provider_subject) DO UPDATE SET
      user_id = excluded.user_id,
      email = COALESCE(excluded.email, user_identity.email),
      claims_json = COALESCE(excluded.claims_json, user_identity.claims_json),
      updated_at = excluded.updated_at
  `).run(
    makeIdentityId(provider, normalizedSubject),
    userId,
    provider,
    normalizedSubject,
    options.email ?? null,
    options.claimsJson ?? null,
    now,
    now,
    getCurrentServerId(database)
  );

  syncLegacyUserColumns(userId, database);
}

export function mergeUsers(
  sourceUserId: string,
  targetUserId: string,
  database: DatabaseSync = getDatabase()
): string {
  const sourceCanonical = resolveCanonicalUserId(sourceUserId, database);
  const targetCanonical = resolveCanonicalUserId(targetUserId, database);

  if (sourceCanonical === targetCanonical) {
    return targetCanonical;
  }

  const sourceUser = getUserRow(sourceCanonical, database);
  const targetUser = getUserRow(targetCanonical, database);

  if (!sourceUser || !targetUser) {
    throw new AuthError("待合并账号不存在");
  }

  const now = new Date().toISOString();

  database.exec("BEGIN");
  try {
    const sourceDataSources = database.prepare(`
      SELECT
        id,
        source_type,
        source_name,
        vendor,
        ingest_channel,
        source_file,
        notes,
        created_at,
        origin_server_id
      FROM data_source
      WHERE user_id = ?
    `).all(sourceCanonical) as Array<{
      id: string;
      source_type: string;
      source_name: string;
      vendor: string | null;
      ingest_channel: string;
      source_file: string | null;
      notes: string | null;
      created_at: string;
      origin_server_id: string | null;
    }>;

    const sourceIdMap = new Map<string, string>();
    for (const dataSource of sourceDataSources) {
      const targetSourceId = `data-source::${targetCanonical}::${dataSource.source_type}`;
      sourceIdMap.set(dataSource.id, targetSourceId);

      database.prepare(`
        INSERT INTO data_source (
          id,
          user_id,
          source_type,
          source_name,
          vendor,
          ingest_channel,
          source_file,
          notes,
          created_at,
          updated_at,
          origin_server_id
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          source_name = COALESCE(data_source.source_name, excluded.source_name),
          vendor = COALESCE(data_source.vendor, excluded.vendor),
          ingest_channel = COALESCE(data_source.ingest_channel, excluded.ingest_channel),
          source_file = COALESCE(excluded.source_file, data_source.source_file),
          notes = COALESCE(excluded.notes, data_source.notes),
          updated_at = excluded.updated_at
      `).run(
        targetSourceId,
        targetCanonical,
        dataSource.source_type,
        dataSource.source_name,
        dataSource.vendor,
        dataSource.ingest_channel,
        dataSource.source_file,
        dataSource.notes,
        dataSource.created_at,
        now,
        dataSource.origin_server_id ?? getCurrentServerId(database)
      );
    }

    for (const [oldId, newId] of sourceIdMap.entries()) {
      database.prepare(`
        UPDATE import_task
        SET
          user_id = ?,
          data_source_id = ?,
          updated_at = ?
        WHERE data_source_id = ?
      `).run(targetCanonical, newId, now, oldId);

      database.prepare(`
        UPDATE metric_record
        SET
          user_id = ?,
          data_source_id = ?,
          updated_at = ?
        WHERE data_source_id = ?
      `).run(targetCanonical, newId, now, oldId);
    }

    database.prepare("UPDATE auth_sessions SET user_id = ? WHERE user_id = ?").run(targetCanonical, sourceCanonical);
    database.prepare("UPDATE genetic_findings SET user_id = ? WHERE user_id = ?").run(targetCanonical, sourceCanonical);
    database.prepare("UPDATE health_suggestion_batch SET user_id = ?, updated_at = ? WHERE user_id = ?").run(targetCanonical, now, sourceCanonical);
    database.prepare("UPDATE health_plan_item SET user_id = ?, updated_at = ? WHERE user_id = ?").run(targetCanonical, now, sourceCanonical);
    database.prepare("UPDATE import_task SET user_id = ?, updated_at = ? WHERE user_id = ?").run(targetCanonical, now, sourceCanonical);
    database.prepare("UPDATE insight_record SET user_id = ?, updated_at = ? WHERE user_id = ?").run(targetCanonical, now, sourceCanonical);
    database.prepare("UPDATE measurement_sets SET user_id = ? WHERE user_id = ?").run(targetCanonical, sourceCanonical);
    database.prepare("UPDATE metric_record SET user_id = ?, updated_at = ? WHERE user_id = ?").run(targetCanonical, now, sourceCanonical);
    database.prepare("UPDATE report_snapshot SET user_id = ?, updated_at = ? WHERE user_id = ?").run(targetCanonical, now, sourceCanonical);
    database.prepare("UPDATE user_identity SET user_id = ?, updated_at = ? WHERE user_id = ?").run(targetCanonical, now, sourceCanonical);

    database.prepare("DELETE FROM data_source WHERE user_id = ?").run(sourceCanonical);

    if (isGenericDisplayName(targetUser.display_name) && !isGenericDisplayName(sourceUser.display_name)) {
      database.prepare(`
        UPDATE users
        SET display_name = ?, updated_at = ?
        WHERE id = ?
      `).run(sourceUser.display_name, now, targetCanonical);
    } else {
      database.prepare(`
        UPDATE users
        SET updated_at = ?, is_disabled = 0, merged_into_user_id = NULL
        WHERE id = ?
      `).run(now, targetCanonical);
    }

    database.prepare(`
      UPDATE users
      SET
        phone_number = NULL,
        device_id = NULL,
        merged_into_user_id = ?,
        is_disabled = 1,
        updated_at = ?
      WHERE id = ?
    `).run(targetCanonical, now, sourceCanonical);

    syncLegacyUserColumns(targetCanonical, database);

    database.exec("COMMIT");
    return targetCanonical;
  } catch (error) {
    database.exec("ROLLBACK");
    throw error;
  }
}

function ensureIdentityAttachedToUser(
  provider: IdentityProvider,
  subject: string,
  targetUserId: string,
  options: {
    email?: string | null;
    claimsJson?: string | null;
    moveExistingToTarget?: boolean;
  } = {},
  database: DatabaseSync = getDatabase()
): string {
  const canonicalTargetUserId = resolveCanonicalUserId(targetUserId, database);
  const existingUserId = getIdentityOwner(provider, subject, database);

  if (existingUserId && existingUserId !== canonicalTargetUserId) {
    if (options.moveExistingToTarget) {
      mergeUsers(existingUserId, canonicalTargetUserId, database);
    } else {
      return existingUserId;
    }
  }

  upsertIdentityRow(provider, subject, canonicalTargetUserId, {
    email: options.email,
    claimsJson: options.claimsJson
  }, database);

  return canonicalTargetUserId;
}

function createSessionForUser(
  userId: string,
  deviceLabel: string | undefined,
  database: DatabaseSync = getDatabase()
): AuthResponsePayload {
  const canonicalUserId = resolveCanonicalUserId(userId, database);
  const sessionId = randomUUID();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + SESSION_EXPIRY_DAYS * 24 * 60 * 60 * 1000);
  const secret = getJWTSecret();
  const token = signJWT(
    {
      sub: canonicalUserId,
      sid: sessionId,
      iat: Math.floor(now.getTime() / 1000),
      exp: Math.floor(expiresAt.getTime() / 1000)
    },
    secret
  );

  const tokenHash = createHmac("sha256", secret).update(token).digest("hex");
  database.prepare(`
    INSERT INTO auth_sessions (
      id,
      user_id,
      token_hash,
      device_label,
      created_at,
      expires_at,
      last_active_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(
    sessionId,
    canonicalUserId,
    tokenHash,
    deviceLabel ?? null,
    now.toISOString(),
    expiresAt.toISOString(),
    now.toISOString()
  );

  const user = getUserInfo(canonicalUserId, database);
  if (!user) {
    throw new AuthError("用户不存在");
  }

  return {
    token,
    user
  };
}

export function requestVerificationCode(
  phoneNumber: string,
  database: DatabaseSync = getDatabase()
): { code: string; expiresInSeconds: number } {
  const normalizedPhoneNumber = normalizeIdentitySubject("phone", phoneNumber);
  const code = String(randomInt(100000, 999999));
  const now = new Date();
  const expiresAt = new Date(now.getTime() + CODE_EXPIRY_SECONDS * 1000);

  database.prepare(`
    INSERT INTO phone_verifications (id, phone_number, code, created_at, expires_at, attempts)
    VALUES (?, ?, ?, ?, ?, 0)
  `).run(randomUUID(), normalizedPhoneNumber, code, now.toISOString(), expiresAt.toISOString());

  console.log(`[AUTH] Verification code for ${normalizedPhoneNumber}: ${code}`);

  return { code, expiresInSeconds: CODE_EXPIRY_SECONDS };
}

export function verifyCodeAndLogin(
  phoneNumber: string,
  code: string,
  deviceLabel: string | undefined,
  preferredUserId?: string,
  database: DatabaseSync = getDatabase()
): AuthResponsePayload {
  const normalizedPhoneNumber = normalizeIdentitySubject("phone", phoneNumber);
  const verification = database.prepare(`
    SELECT id, code, attempts FROM phone_verifications
    WHERE phone_number = ? AND verified_at IS NULL AND expires_at > ?
    ORDER BY created_at DESC LIMIT 1
  `).get(normalizedPhoneNumber, new Date().toISOString()) as
    | { id: string; code: string; attempts: number }
    | undefined;

  if (!verification) {
    throw new Error("验证码已过期或不存在，请重新获取");
  }

  if (verification.attempts >= MAX_ATTEMPTS) {
    throw new Error("验证码尝试次数过多，请重新获取");
  }

  database.prepare("UPDATE phone_verifications SET attempts = attempts + 1 WHERE id = ?").run(verification.id);

  if (verification.code !== code) {
    throw new Error("验证码错误");
  }

  database.prepare("UPDATE phone_verifications SET verified_at = ? WHERE id = ?")
    .run(new Date().toISOString(), verification.id);

  const preferredCanonicalUserId = preferredUserId ? resolveCanonicalUserId(preferredUserId, database) : null;
  const existingPhoneOwner = getIdentityOwner("phone", normalizedPhoneNumber, database);

  let targetUserId: string;
  if (preferredCanonicalUserId) {
    targetUserId = preferredCanonicalUserId;
    if (existingPhoneOwner && existingPhoneOwner !== preferredCanonicalUserId) {
      mergeUsers(existingPhoneOwner, preferredCanonicalUserId, database);
    }
  } else if (existingPhoneOwner) {
    targetUserId = existingPhoneOwner;
  } else {
    targetUserId = ensureUserRecord("phone", normalizedPhoneNumber, {}, database).userId;
  }

  ensureIdentityAttachedToUser("phone", normalizedPhoneNumber, targetUserId, {
    moveExistingToTarget: Boolean(preferredCanonicalUserId)
  }, database);

  return createSessionForUser(targetUserId, deviceLabel, database);
}

export function deviceLogin(
  deviceId: string,
  deviceLabel: string | undefined,
  database: DatabaseSync = getDatabase()
): AuthResponsePayload & { isNewUser: boolean } {
  const normalizedDeviceId = normalizeIdentitySubject("device", deviceId);
  if (!normalizedDeviceId || normalizedDeviceId.length < 8) {
    throw new Error("无效的设备标识");
  }

  const existingOwner = getIdentityOwner("device", normalizedDeviceId, database);
  let targetUserId = existingOwner;
  let isNewUser = false;

  if (!targetUserId) {
    const { userId, isNewUser: created } = ensureUserRecord("device", normalizedDeviceId, {
      deviceLabel
    }, database);
    targetUserId = userId;
    isNewUser = created;
  }

  maybePromoteDisplayName(targetUserId, deviceLabel, database);
  ensureIdentityAttachedToUser("device", normalizedDeviceId, targetUserId, {}, database);

  console.log(`[AUTH] Device login: ${targetUserId} (${deviceLabel ?? "unknown device"})`);

  return {
    ...createSessionForUser(targetUserId, deviceLabel, database),
    isNewUser
  };
}

export async function signInWithApple(
  input: AppleAuthRequest,
  deviceLabel: string | undefined,
  database: DatabaseSync = getDatabase(),
  verifyIdentity: AppleIdentityVerifier = verifyAppleIdentityToken
): Promise<AuthResponsePayload & { isNewUser: boolean }> {
  const verifiedIdentity = await verifyIdentity(input.identityToken);
  const existingOwner = getIdentityOwner("apple", verifiedIdentity.subject, database);
  let targetUserId = existingOwner;
  let isNewUser = false;

  if (!targetUserId) {
    const created = ensureUserRecord("apple", verifiedIdentity.subject, {
      displayName: input.displayName,
      email: verifiedIdentity.email ?? input.email ?? null
    }, database);
    targetUserId = created.userId;
    isNewUser = created.isNewUser;
  }

  ensureIdentityAttachedToUser("apple", verifiedIdentity.subject, targetUserId, {
    email: verifiedIdentity.email ?? input.email ?? null,
    claimsJson: JSON.stringify(verifiedIdentity.rawClaims)
  }, database);
  maybePromoteDisplayName(targetUserId, input.displayName, database);

  return {
    ...createSessionForUser(targetUserId, deviceLabel, database),
    isNewUser
  };
}

export async function linkAppleIdentity(
  currentUserId: string,
  input: AppleAuthRequest,
  database: DatabaseSync = getDatabase(),
  verifyIdentity: AppleIdentityVerifier = verifyAppleIdentityToken
): Promise<{ user: UserInfoPayload }> {
  const verifiedIdentity = await verifyIdentity(input.identityToken);
  const canonicalCurrentUserId = resolveCanonicalUserId(currentUserId, database);

  ensureIdentityAttachedToUser("apple", verifiedIdentity.subject, canonicalCurrentUserId, {
    email: verifiedIdentity.email ?? input.email ?? null,
    claimsJson: JSON.stringify(verifiedIdentity.rawClaims),
    moveExistingToTarget: true
  }, database);
  maybePromoteDisplayName(canonicalCurrentUserId, input.displayName, database);

  const user = getUserInfo(canonicalCurrentUserId, database);
  if (!user) {
    throw new AuthError("用户不存在");
  }

  return { user };
}

export function getUserInfo(
  userId: string,
  database: DatabaseSync = getDatabase()
): UserInfoPayload | null {
  const canonicalUserId = resolveCanonicalUserId(userId, database);
  const user = database.prepare(`
    SELECT
      id,
      display_name,
      phone_number,
      device_id,
      created_at,
      updated_at,
      merged_into_user_id,
      is_disabled,
      origin_server_id
    FROM users
    WHERE id = ? AND COALESCE(is_disabled, 0) = 0
  `).get(canonicalUserId) as UserRow | undefined;

  if (!user) {
    return null;
  }

  const identities = listUserIdentityRows(canonicalUserId, database);
  const providerMap = new Map<IdentityProvider, { provider: IdentityProvider; linked_at: string | null; email: string | null }>();

  for (const identity of identities) {
    if (!providerMap.has(identity.provider)) {
      providerMap.set(identity.provider, {
        provider: identity.provider,
        linked_at: identity.created_at ?? null,
        email: identity.email ?? null
      });
      continue;
    }

    const existing = providerMap.get(identity.provider);
    if (existing && !existing.email && identity.email) {
      existing.email = identity.email;
    }
  }

  const phoneIdentity = identities.find((identity) => identity.provider === "phone");
  const appleIdentity = identities.find((identity) => identity.provider === "apple" && identity.email);

  return {
    id: user.id,
    display_name: user.display_name,
    phone_number: phoneIdentity?.provider_subject ?? user.phone_number ?? null,
    email: appleIdentity?.email ?? null,
    auth_providers: [...providerMap.values()],
    has_apple_linked: providerMap.has("apple")
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
  const session = database.prepare(`
    SELECT id, user_id
    FROM auth_sessions
    WHERE token_hash = ? AND expires_at > ?
  `).get(tokenHash, new Date().toISOString()) as { id: string; user_id: string } | undefined;

  if (!session) {
    throw new AuthError("会话已失效，请重新登录");
  }

  const canonicalUserId = resolveCanonicalUserId(session.user_id, database);
  const now = Date.now();
  const lastUpdate = lastActiveCache.get(session.id) ?? 0;

  if (now - lastUpdate > LAST_ACTIVE_UPDATE_INTERVAL_MS || canonicalUserId !== session.user_id) {
    database.prepare(`
      UPDATE auth_sessions
      SET user_id = ?, last_active_at = ?
      WHERE id = ?
    `).run(canonicalUserId, new Date().toISOString(), session.id);
    lastActiveCache.set(session.id, now);
  }

  return canonicalUserId;
}

export function logout(
  token: string,
  database: DatabaseSync = getDatabase()
): void {
  const secret = getJWTSecret();
  const tokenHash = createHmac("sha256", secret).update(token).digest("hex");
  database.prepare("DELETE FROM auth_sessions WHERE token_hash = ?").run(tokenHash);
}

export function listAllUsers(
  database: DatabaseSync = getDatabase()
): Array<{
  id: string;
  display_name: string | null;
  phone_number: string | null;
  device_id: string | null;
  created_at: string | null;
}> {
  return database.prepare(`
    SELECT id, display_name, phone_number, device_id, created_at
    FROM users
    WHERE COALESCE(is_disabled, 0) = 0
      AND merged_into_user_id IS NULL
    ORDER BY created_at
  `).all() as Array<{
    id: string;
    display_name: string | null;
    phone_number: string | null;
    device_id: string | null;
    created_at: string | null;
  }>;
}

export function canUserSwitch(
  userId: string,
  database: DatabaseSync = getDatabase()
): boolean {
  const canonicalUserId = resolveCanonicalUserId(userId, database);
  if (canonicalUserId === "user-self") return true;

  const row = database.prepare(`
    SELECT 1 AS allowed
    FROM user_identity
    WHERE user_id = ? AND provider = 'device'
    LIMIT 1
  `).get(canonicalUserId) as { allowed: number } | undefined;

  return Boolean(row?.allowed);
}

export function switchToUser(
  targetUserId: string,
  deviceLabel?: string,
  database: DatabaseSync = getDatabase()
): AuthResponsePayload {
  const canonicalTargetUserId = resolveCanonicalUserId(targetUserId, database);
  const user = getUserInfo(canonicalTargetUserId, database);
  if (!user) {
    throw new AuthError("目标用户不存在");
  }

  console.log(`[AUTH] Switched to user: ${user.id} (${user.display_name})`);
  return createSessionForUser(canonicalTargetUserId, deviceLabel ?? "account-switch", database);
}
