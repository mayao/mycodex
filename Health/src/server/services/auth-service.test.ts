import assert from "node:assert/strict";
import test from "node:test";
import { randomUUID } from "node:crypto";

import { createInMemoryDatabase } from "../db/sqlite";
import { seedDatabase } from "../db/seed";
import { runPendingMigrations } from "../db/migration-runner";
import { getHealthHomePageData } from "./health-home-service";
import { getPlanDashboard } from "./health-plan-service";
import { getReportsIndexData, getReportsIndexDataCached } from "./report-service";
import {
  deviceLogin,
  getUserInfo,
  linkAppleIdentity,
  requestVerificationCode,
  resolveCanonicalUserId,
  signInWithApple,
  verifyCodeAndLogin
} from "./auth-service";

process.env.HEALTH_AUTH_ENABLED = "true";
process.env.HEALTH_JWT_SECRET = "health-auth-test-secret-123456";
process.env.HEALTH_APPLE_CLIENT_ID = "com.xihe.healthai";

function setupDatabase() {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);
  return database;
}

function insertUserMetricRecord(database: ReturnType<typeof createInMemoryDatabase>, userId: string): void {
  const now = new Date().toISOString();
  const dataSourceId = `data-source::${userId}::apple_health`;

  database.prepare(`
    INSERT OR IGNORE INTO data_source (
      id, user_id, source_type, source_name, vendor, ingest_channel,
      source_file, notes, created_at, updated_at, origin_server_id
    )
    VALUES (?, ?, 'apple_health', 'Apple 健康同步', NULL, 'healthkit', NULL, NULL, ?, ?, NULL)
  `).run(dataSourceId, userId, now, now);

  database.prepare(`
    INSERT INTO metric_record (
      id, user_id, data_source_id, import_task_id, metric_code, metric_name,
      category, raw_value, normalized_value, unit, reference_range,
      abnormal_flag, sample_time, source_type, source_file, notes,
      created_at, updated_at, origin_server_id
    )
    VALUES (?, ?, ?, NULL, 'body.weight', '体重', 'body_composition', '71.2', 71.2, 'kg', NULL, 'normal', ?, 'apple_health', NULL, NULL, ?, ?, NULL)
  `).run(randomUUID(), userId, dataSourceId, "2026-03-20T08:00:00+08:00", now, now);
}

function insertPlanItem(database: ReturnType<typeof createInMemoryDatabase>, userId: string, title: string): void {
  const now = new Date().toISOString();
  database.prepare(`
    INSERT INTO health_plan_item (
      id, user_id, suggestion_id, dimension, title, description,
      target_metric_code, target_value, target_unit, frequency,
      time_hint, status, created_at, updated_at, origin_server_id
    )
    VALUES (?, ?, NULL, 'exercise', ?, '测试计划', 'activity.exercise_minutes', 30, 'min', 'daily', '20:00', 'active', ?, ?, NULL)
  `).run(randomUUID(), userId, title, now, now);
}

function appleVerifier(subject: string, email = "apple@example.com") {
  return async () => ({
    subject,
    email,
    emailVerified: true,
    rawClaims: {
      sub: subject,
      aud: "com.xihe.healthai",
      iss: "https://appleid.apple.com",
      exp: Math.floor(Date.now() / 1000) + 3600,
      email,
      email_verified: "true"
    }
  });
}

test("verifying a phone while logged in merges phone account into the current device account", async () => {
  const database = setupDatabase();
  const deviceResult = deviceLogin("11111111-1111-4111-8111-111111111111", "当前设备", database);
  const currentUserId = deviceResult.user.id;

  const firstCode = requestVerificationCode("13900000001", database).code;
  const phoneLogin = verifyCodeAndLogin("13900000001", firstCode, "Phone Login", undefined, database);
  const legacyPhoneUserId = phoneLogin.user.id;
  assert.notEqual(legacyPhoneUserId, currentUserId);

  insertUserMetricRecord(database, legacyPhoneUserId);
  insertPlanItem(database, legacyPhoneUserId, "晚饭后步行 30 分钟");
  await getReportsIndexData(database, legacyPhoneUserId);

  const secondCode = requestVerificationCode("13900000001", database).code;
  const mergedLogin = verifyCodeAndLogin("13900000001", secondCode, "当前设备", currentUserId, database);

  assert.equal(mergedLogin.user.id, currentUserId);
  assert.equal(resolveCanonicalUserId(legacyPhoneUserId, database), currentUserId);

  const sourceUser = database.prepare(`
    SELECT merged_into_user_id, is_disabled
    FROM users
    WHERE id = ?
  `).get(legacyPhoneUserId) as { merged_into_user_id: string | null; is_disabled: number };
  assert.equal(sourceUser.merged_into_user_id, currentUserId);
  assert.equal(sourceUser.is_disabled, 1);

  const userInfo = getUserInfo(currentUserId, database);
  assert.equal(userInfo?.phone_number, "13900000001");
  assert.equal(userInfo?.auth_providers.some((provider) => provider.provider === "phone"), true);

  const homeData = await getHealthHomePageData(database, currentUserId);
  assert.ok(
    homeData.charts.bodyComposition.data.some((point) => {
      const chartPoint = point as Record<string, unknown> & {
        values?: Record<string, unknown>;
      };
      const value = chartPoint.values ? chartPoint.values.weight : chartPoint.weight;
      return typeof value === "number";
    })
  );

  const planDashboard = await getPlanDashboard(currentUserId, database);
  assert.ok(planDashboard.planItems.some((item) => item.title === "晚饭后步行 30 分钟"));

  const reports = await getReportsIndexDataCached(database, currentUserId);
  assert.ok(reports.weeklyReports.length >= 1);
});

test("linking Apple to the current device account preserves current user id and absorbs previous Apple account data", async () => {
  const database = setupDatabase();
  const deviceResult = deviceLogin("22222222-2222-4222-8222-222222222222", "我的 iPhone", database);
  const currentUserId = deviceResult.user.id;

  const initialAppleLogin = await signInWithApple(
    {
      identityToken: "unused-token",
      displayName: "Apple 马尧",
      email: "apple@example.com"
    },
    "Apple 登录",
    database,
    appleVerifier("apple-sub-001")
  );
  const previousAppleUserId = initialAppleLogin.user.id;
  assert.notEqual(previousAppleUserId, currentUserId);

  insertPlanItem(database, previousAppleUserId, "Apple 账号来源的计划");

  const linkResult = await linkAppleIdentity(
    currentUserId,
    {
      identityToken: "unused-token",
      displayName: "Apple 马尧",
      email: "apple@example.com"
    },
    database,
    appleVerifier("apple-sub-001")
  );

  assert.equal(linkResult.user.id, currentUserId);
  assert.equal(linkResult.user.has_apple_linked, true);
  assert.equal(linkResult.user.email, "apple@example.com");

  const sourceUser = database.prepare(`
    SELECT merged_into_user_id, is_disabled
    FROM users
    WHERE id = ?
  `).get(previousAppleUserId) as { merged_into_user_id: string | null; is_disabled: number };
  assert.equal(sourceUser.merged_into_user_id, currentUserId);
  assert.equal(sourceUser.is_disabled, 1);

  const appleLoginAfterMerge = await signInWithApple(
    {
      identityToken: "unused-token",
      displayName: "Apple 马尧",
      email: "apple@example.com"
    },
    "Apple 登录",
    database,
    appleVerifier("apple-sub-001")
  );
  assert.equal(appleLoginAfterMerge.user.id, currentUserId);

  const planDashboard = await getPlanDashboard(currentUserId, database);
  assert.ok(planDashboard.planItems.some((item) => item.title === "Apple 账号来源的计划"));
});
