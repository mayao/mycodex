import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import { getAppEnv } from "../config/env";
import { getDatabase } from "../db/sqlite";
import { getKimiOpenAIHeaders } from "./llm-provider-routing";
import {
  buildHealthPlanSystemPrompt,
  buildHealthPlanUserPrompt,
  healthPlanSuggestionSchema,
  type HealthPlanSuggestionOutput
} from "../llm/health-plan-prompt";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SuggestionRow {
  id: string;
  batch_id: string;
  dimension: string;
  title: string;
  description: string;
  target_metric_code: string | null;
  target_value: number | null;
  target_unit: string | null;
  frequency: string;
  time_hint: string | null;
  priority: number;
  created_at: string;
}

interface PlanItemRow {
  id: string;
  user_id: string;
  suggestion_id: string | null;
  dimension: string;
  title: string;
  description: string;
  target_metric_code: string | null;
  target_value: number | null;
  target_unit: string | null;
  frequency: string;
  time_hint: string | null;
  status: string;
  created_at: string;
  updated_at: string;
}

interface PlanCheckRow {
  id: string;
  plan_item_id: string;
  check_date: string;
  actual_value: number | null;
  is_completed: number;
  source: string;
  created_at: string;
}

interface MetricSummaryRow {
  metric_code: string;
  metric_name: string;
  avg_value: number | null;
  latest_value: number | null;
  unit: string;
  count: number;
}

export interface HealthPlanDashboard {
  planItems: PlanItemRow[];
  pausedItems: PlanItemRow[];
  suggestions: SuggestionRow[];
  todayChecks: PlanCheckRow[];
  stats: {
    activeCount: number;
    todayCompleted: number;
    todayTotal: number;
    weekCompletionRate: number;
  };
}

// ---------------------------------------------------------------------------
// Generate suggestions via LLM
// ---------------------------------------------------------------------------

export async function generateSuggestions(
  userId: string,
  database: DatabaseSync = getDatabase()
): Promise<{ batchId: string; suggestions: SuggestionRow[] }> {
  const env = getAppEnv();

  // Throttle: at most 1 LLM generation per hour (mock batches don't count)
  const lastBatch = database
    .prepare(
      `SELECT created_at, provider FROM health_suggestion_batch
       WHERE user_id = ? ORDER BY created_at DESC LIMIT 1`
    )
    .get(userId) as { created_at: string; provider: string } | undefined;

  if (lastBatch && lastBatch.provider !== "mock") {
    const elapsed = Date.now() - new Date(lastBatch.created_at).getTime();
    if (elapsed < 60 * 60 * 1000) {
      throw new Error("建议生成频率限制：每小时最多 1 次。请稍后再试。");
    }
  }

  // Gather recent 7-day metric summaries
  const metricRows = database
    .prepare(
      `SELECT
         metric_code,
         metric_name,
         AVG(normalized_value) AS avg_value,
         (SELECT normalized_value FROM metric_record r2
          WHERE r2.metric_code = mr.metric_code AND r2.user_id = ?
          ORDER BY sample_time DESC LIMIT 1) AS latest_value,
         unit,
         COUNT(*) AS count
       FROM metric_record mr
       WHERE user_id = ? AND sample_time >= datetime('now', '-7 days')
       GROUP BY metric_code`
    )
    .all(userId, userId) as unknown as MetricSummaryRow[];

  // Call LLM
  const suggestions = await callLLMForSuggestions(metricRows, env);

  // Persist batch + suggestions
  const batchId = randomUUID();
  database
    .prepare(
      `INSERT INTO health_suggestion_batch (id, user_id, data_window_days, provider, model)
       VALUES (?, ?, 7, ?, ?)`
    )
    .run(batchId, userId, env.HEALTH_LLM_PROVIDER ?? "anthropic", env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514");

  const insertSuggestion = database.prepare(
    `INSERT INTO health_suggestion
       (id, batch_id, dimension, title, description, target_metric_code, target_value, target_unit, frequency, time_hint, priority)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );

  const savedSuggestions: SuggestionRow[] = [];

  for (const s of suggestions.suggestions) {
    const id = randomUUID();
    insertSuggestion.run(
      id,
      batchId,
      s.dimension,
      s.title,
      s.description,
      s.target_metric_code ?? null,
      s.target_value ?? null,
      s.target_unit ?? null,
      s.frequency,
      s.time_hint ?? null,
      s.priority
    );
    savedSuggestions.push({
      id,
      batch_id: batchId,
      dimension: s.dimension,
      title: s.title,
      description: s.description,
      target_metric_code: s.target_metric_code ?? null,
      target_value: s.target_value ?? null,
      target_unit: s.target_unit ?? null,
      frequency: s.frequency,
      time_hint: s.time_hint ?? null,
      priority: s.priority,
      created_at: new Date().toISOString()
    });
  }

  return { batchId, suggestions: savedSuggestions };
}

async function callLLMForSuggestions(
  metrics: MetricSummaryRow[],
  env: ReturnType<typeof getAppEnv>
): Promise<HealthPlanSuggestionOutput> {
  const systemPrompt = buildHealthPlanSystemPrompt();
  const userPrompt = buildHealthPlanUserPrompt(metrics);

  const provider = env.HEALTH_LLM_PROVIDER ?? "anthropic";
  const apiKey = env.HEALTH_LLM_API_KEY;
  const model = env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514";

  if (!apiKey) {
    // Return mock suggestions when no API key
    return getMockSuggestions(metrics);
  }

  if (provider === "anthropic") {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01"
      },
      body: JSON.stringify({
        model,
        max_tokens: 2048,
        system: systemPrompt,
        messages: [{ role: "user", content: userPrompt }]
      })
    });

    if (!response.ok) {
      const errorBody = await response.text().catch(() => "");
      throw new Error(`Anthropic API failed: ${response.status} ${errorBody.slice(0, 200)}`);
    }

    const payload = (await response.json()) as {
      content?: Array<{ type: string; text?: string }>;
    };
    const rawContent = payload.content
      ?.filter((b) => b.type === "text")
      .map((b) => b.text)
      .join("\n")
      .trim();

    if (!rawContent) throw new Error("LLM returned empty content");

    return parseLLMSuggestions(rawContent);
  }

  // OpenAI-compatible
  const baseUrl = (env.HEALTH_LLM_BASE_URL ?? "https://api.openai.com/v1").replace(/\/$/, "");
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      ...(getKimiOpenAIHeaders(apiKey) ?? {})
    },
    body: JSON.stringify({
      model,
      temperature: 0.3,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt }
      ]
    })
  });

  if (!response.ok) throw new Error("LLM provider request failed");

  const payload = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const rawContent = payload.choices?.[0]?.message?.content;
  if (!rawContent) throw new Error("LLM returned empty content");

  return parseLLMSuggestions(rawContent);
}

/**
 * Parse LLM response text into validated suggestions.
 * Handles both `{ suggestions: [...] }` and bare `[...]` formats,
 * and strips markdown code fences.
 */
function parseLLMSuggestions(rawContent: string): HealthPlanSuggestionOutput {
  // Strip markdown code fences
  const jsonStr = rawContent
    .replace(/^```(?:json)?\s*/m, "")
    .replace(/\s*```\s*$/m, "")
    .trim();

  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonStr);
  } catch {
    // Try extracting JSON object or array from surrounding text
    const objMatch = jsonStr.match(/(\{[\s\S]*\})/);
    const arrMatch = jsonStr.match(/(\[[\s\S]*\])/);
    const match = objMatch ?? arrMatch;
    if (!match) throw new Error("LLM 返回的内容无法解析为 JSON");
    parsed = JSON.parse(match[1]);
  }

  // If LLM returned a bare array, wrap it
  if (Array.isArray(parsed)) {
    parsed = { suggestions: parsed };
  }

  return healthPlanSuggestionSchema.parse(parsed);
}

function getMockSuggestions(metrics: MetricSummaryRow[] = []): HealthPlanSuggestionOutput {
  const byCode = Object.fromEntries(metrics.map((metric) => [metric.metric_code, metric])) as Record<string, MetricSummaryRow | undefined>;
  const dietMetric = byCode["diet.calories_intake_kcal"];
  const dietCoverageMetric = byCode["diet.meal_upload_count"];
  const weightMetric = byCode["body.weight"];
  const sleepMetric = byCode["sleep.asleep_minutes"];
  const exerciseMetric = byCode["activity.exercise_minutes"];
  const hasDietData = Boolean(dietMetric && dietMetric.count > 0);
  const hasLowDietCoverage = !dietCoverageMetric || (dietCoverageMetric.avg_value ?? 0) < 1;

  return {
    suggestions: [
      {
        dimension: "exercise",
        title: "每日步行 8000 步",
        description: "根据您最近的活动数据，建议将每日步数目标设为 8000 步。可以通过午餐后散步 20 分钟和晚饭后散步 15 分钟来达成。规律步行有助于改善心血管健康和体重管理。",
        target_metric_code: "activity.steps",
        target_value: 8000,
        target_unit: "count",
        frequency: "daily",
        time_hint: "morning",
        priority: 3
      },
      {
        dimension: "exercise",
        title: "每周 3 次 30 分钟中等强度运动",
        description: "建议每周安排至少 3 次 30 分钟的中等强度运动（如快走、游泳、骑车），以提升活动消耗和心肺功能。",
        target_metric_code: "activity.exercise_minutes",
        target_value: 30,
        target_unit: "min",
        frequency: "weekly",
        time_hint: "18:00",
        priority: exerciseMetric?.latest_value != null && exerciseMetric.latest_value < 30 ? 4 : 3
      },
      {
        dimension: "sleep",
        title: "保证每晚 7-8 小时睡眠",
        description: "充足的睡眠对身体恢复和代谢至关重要。建议在 23:00 前入睡，保证 7-8 小时的睡眠时间。",
        target_metric_code: "sleep.asleep_minutes",
        target_value: 420,
        target_unit: "min",
        frequency: "daily",
        time_hint: "22:30",
        priority: sleepMetric?.latest_value != null && sleepMetric.latest_value < 420 ? 4 : 3
      },
      {
        dimension: "diet",
        title: hasDietData ? "连续记录饮食热量 7 天" : "先连续上传 3-7 天饮食照片",
        description: hasDietData
          ? `目前已有饮食热量记录${dietMetric?.latest_value != null ? `，最近值约 ${Math.round(dietMetric.latest_value)} kcal` : ""}${weightMetric?.latest_value != null ? `，可与当前体重 ${weightMetric.latest_value} ${weightMetric.unit} 一起看趋势` : ""}。接下来优先保证每天都有饮食照片，让热量趋势先稳定下来。`
          : "当前还缺少连续饮食记录。建议先连续 3-7 天上传每次进食照片，建立最基本的热量趋势和记录覆盖，再决定是否需要更细化调整。",
        target_metric_code: hasDietData ? "diet.meal_upload_count" : null,
        target_value: hasDietData ? 1 : null,
        target_unit: hasDietData ? "count" : null,
        frequency: "daily",
        time_hint: "evening",
        priority: hasLowDietCoverage ? 5 : 3
      },
      {
        dimension: "checkup",
        title: "预约年度体检",
        description: "定期体检是健康管理的基础。建议每年进行一次全面体检，包括血常规、肝肾功能、血脂血糖等基本项目。",
        target_metric_code: null,
        target_value: null,
        target_unit: null,
        frequency: "once",
        time_hint: null,
        priority: 3
      }
    ]
  };
}

// ---------------------------------------------------------------------------
// Get latest suggestions for user
// ---------------------------------------------------------------------------

export function getLatestSuggestions(
  userId: string,
  database: DatabaseSync = getDatabase()
): SuggestionRow[] {
  const batch = database
    .prepare(
      `SELECT id FROM health_suggestion_batch
       WHERE user_id = ? ORDER BY created_at DESC LIMIT 1`
    )
    .get(userId) as { id: string } | undefined;

  if (!batch) return [];

  return database
    .prepare(`SELECT * FROM health_suggestion WHERE batch_id = ? ORDER BY priority DESC`)
    .all(batch.id) as unknown as SuggestionRow[];
}

// ---------------------------------------------------------------------------
// Accept suggestion → create plan item
// ---------------------------------------------------------------------------

export function acceptSuggestion(
  userId: string,
  suggestionId: string,
  overrides?: { target_value?: number; target_unit?: string; frequency?: string; time_hint?: string },
  database: DatabaseSync = getDatabase()
): PlanItemRow {
  const suggestion = database
    .prepare(`SELECT * FROM health_suggestion WHERE id = ?`)
    .get(suggestionId) as unknown as SuggestionRow | undefined;

  if (!suggestion) throw new Error("建议不存在");

  // Check if already accepted
  const existing = database
    .prepare(`SELECT id, status FROM health_plan_item WHERE suggestion_id = ? AND user_id = ?`)
    .get(suggestionId, userId) as { id: string; status: string } | undefined;

  if (existing) {
    if (existing.status === "paused" || existing.status === "archived") {
      // Reactivate and apply overrides if provided
      const now = new Date().toISOString();
      if (overrides) {
        database.prepare(
          `UPDATE health_plan_item SET status = 'active',
            target_value = COALESCE(?, target_value),
            target_unit = COALESCE(?, target_unit),
            frequency = COALESCE(?, frequency),
            time_hint = COALESCE(?, time_hint),
            updated_at = ? WHERE id = ?`
        ).run(
          overrides.target_value ?? null,
          overrides.target_unit ?? null,
          overrides.frequency ?? null,
          overrides.time_hint ?? null,
          now,
          existing.id
        );
      } else {
        database.prepare(
          `UPDATE health_plan_item SET status = 'active', updated_at = ? WHERE id = ?`
        ).run(now, existing.id);
      }
      return database.prepare(`SELECT * FROM health_plan_item WHERE id = ?`).get(existing.id) as unknown as PlanItemRow;
    }
    if (existing.status === "active") {
      throw new Error("该建议正在执行中");
    }
    // status === "completed" → fall through to create a new plan item
  }

  const id = randomUUID();
  const now = new Date().toISOString();

  database
    .prepare(
      `INSERT INTO health_plan_item
       (id, user_id, suggestion_id, dimension, title, description, target_metric_code, target_value, target_unit, frequency, time_hint, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)`
    )
    .run(
      id,
      userId,
      suggestionId,
      suggestion.dimension,
      suggestion.title,
      suggestion.description,
      suggestion.target_metric_code,
      overrides?.target_value ?? suggestion.target_value,
      overrides?.target_unit ?? suggestion.target_unit,
      overrides?.frequency ?? suggestion.frequency,
      overrides?.time_hint ?? suggestion.time_hint,
      now,
      now
    );

  return database.prepare(`SELECT * FROM health_plan_item WHERE id = ?`).get(id) as unknown as PlanItemRow;
}

// ---------------------------------------------------------------------------
// Get active plan items
// ---------------------------------------------------------------------------

export function getActivePlanItems(
  userId: string,
  database: DatabaseSync = getDatabase()
): PlanItemRow[] {
  return database
    .prepare(
      `SELECT * FROM health_plan_item
       WHERE user_id = ? AND status = 'active'
       ORDER BY dimension, created_at DESC`
    )
    .all(userId) as unknown as PlanItemRow[];
}

// ---------------------------------------------------------------------------
// Get paused plan items
// ---------------------------------------------------------------------------

export function getPausedPlanItems(
  userId: string,
  database: DatabaseSync = getDatabase()
): PlanItemRow[] {
  return database
    .prepare(
      `SELECT * FROM health_plan_item WHERE user_id = ? AND status = 'paused' ORDER BY updated_at DESC`
    )
    .all(userId) as unknown as PlanItemRow[];
}

// ---------------------------------------------------------------------------
// Update plan item fields
// ---------------------------------------------------------------------------

export function updatePlanItem(
  userId: string,
  planItemId: string,
  fields: { target_value?: number; target_unit?: string; frequency?: string; time_hint?: string },
  database: DatabaseSync = getDatabase()
): PlanItemRow {
  const item = database
    .prepare(`SELECT * FROM health_plan_item WHERE id = ? AND user_id = ?`)
    .get(planItemId, userId) as unknown as PlanItemRow | undefined;

  if (!item) throw new Error("计划项不存在");

  const now = new Date().toISOString();
  database
    .prepare(
      `UPDATE health_plan_item SET
        target_value = COALESCE(?, target_value),
        target_unit = COALESCE(?, target_unit),
        frequency = COALESCE(?, frequency),
        time_hint = COALESCE(?, time_hint),
        updated_at = ?
      WHERE id = ?`
    )
    .run(
      fields.target_value ?? null,
      fields.target_unit ?? null,
      fields.frequency ?? null,
      fields.time_hint ?? null,
      now,
      planItemId
    );

  return database.prepare(`SELECT * FROM health_plan_item WHERE id = ?`).get(planItemId) as unknown as PlanItemRow;
}

// ---------------------------------------------------------------------------
// Update plan item status
// ---------------------------------------------------------------------------

export function updatePlanItemStatus(
  userId: string,
  planItemId: string,
  status: "active" | "paused" | "completed" | "archived",
  database: DatabaseSync = getDatabase()
): PlanItemRow {
  const item = database
    .prepare(`SELECT * FROM health_plan_item WHERE id = ? AND user_id = ?`)
    .get(planItemId, userId) as unknown as PlanItemRow | undefined;

  if (!item) throw new Error("计划项不存在");

  database
    .prepare(`UPDATE health_plan_item SET status = ?, updated_at = ? WHERE id = ?`)
    .run(status, new Date().toISOString(), planItemId);

  return database.prepare(`SELECT * FROM health_plan_item WHERE id = ?`).get(planItemId) as unknown as PlanItemRow;
}

// ---------------------------------------------------------------------------
// Check plan completion against actual data
// ---------------------------------------------------------------------------

export function checkPlanCompletion(
  userId: string,
  date?: string,
  database: DatabaseSync = getDatabase()
): PlanCheckRow[] {
  const checkDate = date ?? new Date().toISOString().split("T")[0];

  const activeItems = database
    .prepare(
      `SELECT * FROM health_plan_item
       WHERE user_id = ? AND status = 'active' AND target_metric_code IS NOT NULL`
    )
    .all(userId) as unknown as PlanItemRow[];

  const results: PlanCheckRow[] = [];

  for (const item of activeItems) {
    // Check frequency: should we check today?
    if (item.frequency === "weekly") {
      // Only check on the same weekday as creation
      const createdDay = new Date(item.created_at).getDay();
      const checkDay = new Date(checkDate).getDay();
      if (createdDay !== checkDay) continue;
    }

    // Get actual value from metric_record for today
    const actualRow = database
      .prepare(
        `SELECT normalized_value FROM metric_record
         WHERE user_id = ? AND metric_code = ? AND DATE(sample_time) = ?
         ORDER BY sample_time DESC LIMIT 1`
      )
      .get(userId, item.target_metric_code, checkDate) as { normalized_value: number | null } | undefined;

    const actualValue = actualRow?.normalized_value ?? null;
    const isCompleted = actualValue != null && item.target_value != null && actualValue >= item.target_value;

    // Upsert check record
    const existingCheck = database
      .prepare(`SELECT id FROM health_plan_check WHERE plan_item_id = ? AND check_date = ?`)
      .get(item.id, checkDate) as { id: string } | undefined;

    if (existingCheck) {
      database
        .prepare(
          `UPDATE health_plan_check SET actual_value = ?, is_completed = ?, source = 'auto', updated_at = ? WHERE id = ?`
        )
        .run(actualValue, isCompleted ? 1 : 0, new Date().toISOString(), existingCheck.id);
      results.push(
        database.prepare(`SELECT * FROM health_plan_check WHERE id = ?`).get(existingCheck.id) as unknown as PlanCheckRow
      );
    } else {
      const checkId = randomUUID();
      database
        .prepare(
          `INSERT INTO health_plan_check (id, plan_item_id, check_date, actual_value, is_completed, source)
           VALUES (?, ?, ?, ?, ?, 'auto')`
        )
        .run(checkId, item.id, checkDate, actualValue, isCompleted ? 1 : 0);
      results.push(
        database.prepare(`SELECT * FROM health_plan_check WHERE id = ?`).get(checkId) as unknown as PlanCheckRow
      );
    }
  }

  return results;
}

// ---------------------------------------------------------------------------
// Manual check-in (for items without auto-tracking)
// ---------------------------------------------------------------------------

export function manualCheckIn(
  userId: string,
  planItemId: string,
  date?: string,
  database: DatabaseSync = getDatabase()
): PlanCheckRow {
  const checkDate = date ?? new Date().toISOString().split("T")[0];

  // Verify ownership
  const item = database
    .prepare(`SELECT id FROM health_plan_item WHERE id = ? AND user_id = ?`)
    .get(planItemId, userId) as { id: string } | undefined;

  if (!item) throw new Error("计划项不存在");

  const existingCheck = database
    .prepare(`SELECT id FROM health_plan_check WHERE plan_item_id = ? AND check_date = ?`)
    .get(planItemId, checkDate) as { id: string } | undefined;

  if (existingCheck) {
    database
      .prepare(`UPDATE health_plan_check SET is_completed = 1, source = 'manual', updated_at = ? WHERE id = ?`)
      .run(new Date().toISOString(), existingCheck.id);
    return database.prepare(`SELECT * FROM health_plan_check WHERE id = ?`).get(existingCheck.id) as unknown as PlanCheckRow;
  }

  const checkId = randomUUID();
  database
    .prepare(
      `INSERT INTO health_plan_check (id, plan_item_id, check_date, is_completed, source)
       VALUES (?, ?, ?, 1, 'manual')`
    )
    .run(checkId, planItemId, checkDate);

  return database.prepare(`SELECT * FROM health_plan_check WHERE id = ?`).get(checkId) as unknown as PlanCheckRow;
}

// ---------------------------------------------------------------------------
// Dashboard aggregation
// ---------------------------------------------------------------------------

export async function getPlanDashboard(
  userId: string,
  database: DatabaseSync = getDatabase()
): Promise<HealthPlanDashboard> {
  const today = new Date().toISOString().split("T")[0];

  const planItems = getActivePlanItems(userId, database);
  const pausedItems = getPausedPlanItems(userId, database);
  let suggestions = getLatestSuggestions(userId, database);

  // If no suggestions exist yet, immediately return mock suggestions
  // so the user sees something right away. Also kick off real LLM generation
  // in the background for next time.
  if (suggestions.length === 0 && planItems.length === 0) {
    const mock = getMockSuggestions();
    // Seed mock suggestions into DB so they persist
    const batchId = randomUUID();
    database
      .prepare(
        `INSERT INTO health_suggestion_batch (id, user_id, data_window_days, provider, model)
         VALUES (?, ?, 7, 'mock', 'built-in')`
      )
      .run(batchId, userId);

    const insertStmt = database.prepare(
      `INSERT INTO health_suggestion
         (id, batch_id, dimension, title, description, target_metric_code, target_value, target_unit, frequency, time_hint, priority)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );

    for (const s of mock.suggestions) {
      const id = randomUUID();
      insertStmt.run(
        id, batchId, s.dimension, s.title, s.description,
        s.target_metric_code ?? null, s.target_value ?? null,
        s.target_unit ?? null, s.frequency, s.time_hint ?? null, s.priority
      );
    }

    suggestions = getLatestSuggestions(userId, database);
  }

  // Auto-check completion against actual metric data
  if (planItems.length > 0) {
    checkPlanCompletion(userId, today, database);
  }

  // Get today's checks for active items
  const todayChecks = planItems.length > 0
    ? (database
        .prepare(
          `SELECT c.* FROM health_plan_check c
           JOIN health_plan_item p ON c.plan_item_id = p.id
           WHERE p.user_id = ? AND c.check_date = ?`
        )
        .all(userId, today) as unknown as PlanCheckRow[])
    : [];

  // Week completion rate
  const weekStart = new Date();
  weekStart.setDate(weekStart.getDate() - 7);
  const weekStartStr = weekStart.toISOString().split("T")[0];

  const weekStats = planItems.length > 0
    ? (database
        .prepare(
          `SELECT
             COUNT(*) AS total,
             SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) AS completed
           FROM health_plan_check c
           JOIN health_plan_item p ON c.plan_item_id = p.id
           WHERE p.user_id = ? AND c.check_date >= ?`
        )
        .get(userId, weekStartStr) as { total: number; completed: number })
    : { total: 0, completed: 0 };

  const todayCompleted = todayChecks.filter((c) => c.is_completed).length;

  // Filter out suggestions that are already accepted (active or paused)
  const allItems = [...planItems, ...pausedItems];
  const acceptedSuggestionIds = new Set(
    allItems.filter((p) => p.suggestion_id).map((p) => p.suggestion_id!)
  );
  const unacceptedSuggestions = suggestions.filter((s) => !acceptedSuggestionIds.has(s.id));

  return {
    planItems: planItems,
    pausedItems: pausedItems,
    suggestions: unacceptedSuggestions,
    todayChecks: todayChecks,
    stats: {
      activeCount: planItems.length,
      todayCompleted: todayCompleted,
      todayTotal: planItems.length,
      weekCompletionRate: weekStats.total > 0 ? weekStats.completed / weekStats.total : 0
    }
  };
}

// ---------------------------------------------------------------------------
// Plan review for reports
// ---------------------------------------------------------------------------

export interface PlanItemReview {
  plan_item_id: string;
  title: string;
  dimension: string;
  frequency: string;
  target_value: number | null;
  target_unit: string | null;
  expected_checks: number;
  actual_completed: number;
  completion_rate: number;
  status: string;
}

export interface PlanReviewData {
  period_start: string;
  period_end: string;
  total_items: number;
  overall_completion_rate: number;
  items: PlanItemReview[];
  ai_comment: string;
}

export interface PlanProgressReport {
  periodStart: string;
  periodEnd: string;
  items: Array<{
    planItemId: string;
    title: string;
    dimension: string;
    frequency: string;
    expectedDays: number;
    completedDays: number;
    completionRate: number;
    dataBackedNote: string;
  }>;
  overallRate: number;
  aiNudge: string;
}

export function getPlanProgressReport(
  userId: string,
  database: DatabaseSync = getDatabase()
): PlanProgressReport {
  const today = new Date();
  const periodEnd = today.toISOString().slice(0, 10);
  const periodStart = new Date(today.getTime() - 6 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

  let review: PlanReviewData;
  try {
    review = getPlanReviewForPeriod(userId, periodStart, periodEnd, database);
  } catch {
    return {
      periodStart,
      periodEnd,
      items: [],
      overallRate: 0,
      aiNudge: "暂无计划数据，先去「健康计划」页面生成建议并接受吧！"
    };
  }

  const items = review.items.map((item) => ({
    planItemId: item.plan_item_id,
    title: item.title,
    dimension: item.dimension,
    frequency: item.frequency,
    expectedDays: item.expected_checks,
    completedDays: item.actual_completed,
    completionRate: item.completion_rate,
    dataBackedNote: item.completion_rate >= 0.8 ? "执行良好，继续保持！" : item.completion_rate >= 0.5 ? "完成了一半以上，再努力一把！" : "完成率偏低，尝试降低难度或调整时间。"
  }));

  const overallRate = Math.round(review.overall_completion_rate * 100) / 100;
  let aiNudge = "";
  if (items.length === 0) {
    aiNudge = "还没有活跃计划，去设置你的健康目标吧！";
  } else if (overallRate >= 0.8) {
    aiNudge = "本周执行非常棒！坚持下去，健康就在这些细节里。";
  } else if (overallRate >= 0.5) {
    aiNudge = "本周完成了一半以上，保持节奏，慢慢提升！";
  } else {
    aiNudge = "本周有些计划未能完成，试着把计划拆小一点，降低门槛！";
  }

  return { periodStart, periodEnd, items, overallRate, aiNudge };
}

export function getPlanReviewForPeriod(
  userId: string,
  periodStart: string,
  periodEnd: string,
  database: DatabaseSync = getDatabase()
): PlanReviewData {
  // Get all plan items that were active during this period
  // (created before periodEnd, and not completed/archived before periodStart)
  const items = database
    .prepare(
      `SELECT * FROM health_plan_item
       WHERE user_id = ? AND created_at <= ? AND status IN ('active', 'paused', 'completed')
       ORDER BY dimension, created_at`
    )
    .all(userId, periodEnd + "T23:59:59Z") as unknown as PlanItemRow[];

  const reviews: PlanItemReview[] = [];

  for (const item of items) {
    // Count completed checks in this period
    const checkStats = database
      .prepare(
        `SELECT COUNT(*) as total, SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) as completed
         FROM health_plan_check
         WHERE plan_item_id = ? AND check_date >= ? AND check_date <= ?`
      )
      .get(item.id, periodStart, periodEnd) as { total: number; completed: number };

    // Calculate expected checks based on frequency
    const startDate = new Date(periodStart);
    const endDate = new Date(periodEnd);
    const daysDiff = Math.max(1, Math.round((endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24)) + 1);

    let expectedChecks: number;
    if (item.frequency === "daily") {
      expectedChecks = daysDiff;
    } else if (item.frequency === "weekly") {
      expectedChecks = Math.max(1, Math.round(daysDiff / 7));
    } else {
      // "once"
      expectedChecks = 1;
    }

    const actualCompleted = checkStats.completed ?? 0;
    const completionRate = expectedChecks > 0 ? Math.min(1, actualCompleted / expectedChecks) : 0;

    reviews.push({
      plan_item_id: item.id,
      title: item.title,
      dimension: item.dimension,
      frequency: item.frequency,
      target_value: item.target_value,
      target_unit: item.target_unit,
      expected_checks: expectedChecks,
      actual_completed: actualCompleted,
      completion_rate: Math.round(completionRate * 100) / 100,
      status: item.status
    });
  }

  const overallRate = reviews.length > 0
    ? reviews.reduce((sum, r) => sum + r.completion_rate, 0) / reviews.length
    : 0;

  return {
    period_start: periodStart,
    period_end: periodEnd,
    total_items: reviews.length,
    overall_completion_rate: Math.round(overallRate * 100) / 100,
    items: reviews,
    ai_comment: ""
  };
}
