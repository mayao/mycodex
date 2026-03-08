import assert from "node:assert/strict";
import test from "node:test";

import { runPendingMigrations } from "../db/migration-runner";
import { createInMemoryDatabase } from "../db/sqlite";
import { seedDatabase } from "../db/seed";
import { generateStructuredInsights } from "./structured-rule-engine";

const userId = "user-rules";
const dataSourceId = "data-source::rule-test";

const metricMeta = {
  "body.body_fat_pct": {
    metricName: "体脂率",
    category: "body_composition",
    unit: "%",
    betterDirection: "down",
    referenceRange: "10 - 20 %"
  },
  "body.weight": {
    metricName: "体重",
    category: "body_composition",
    unit: "kg",
    betterDirection: "down",
    referenceRange: "60.6 - 82 kg"
  },
  "lipid.ldl_c": {
    metricName: "低密度脂蛋白胆固醇",
    category: "lipid",
    unit: "mmol/L",
    betterDirection: "down",
    referenceRange: "<= 3.4 mmol/L"
  },
  "lipid.triglycerides": {
    metricName: "甘油三酯",
    category: "lipid",
    unit: "mmol/L",
    betterDirection: "down",
    referenceRange: "<= 1.7 mmol/L"
  },
  "glycemic.glucose": {
    metricName: "血糖",
    category: "lab",
    unit: "mmol/L",
    betterDirection: "down",
    referenceRange: "3.9 - 6.09 mmol/L"
  },
  "activity.exercise_minutes": {
    metricName: "训练分钟",
    category: "activity",
    unit: "min",
    betterDirection: "up",
    referenceRange: null
  }
} as const;

function setupDatabase() {
  const database = createInMemoryDatabase();
  seedDatabase(database);

  database
    .prepare(
      `
      INSERT INTO users (id, display_name, sex, birth_year, height_cm, note)
      VALUES (?, ?, ?, ?, ?, ?)
    `
    )
    .run(userId, "Rule User", "male", 1990, 180, "rule engine test user");

  runPendingMigrations(database);

  database
    .prepare(
      `
      INSERT INTO data_source (
        id, user_id, source_type, source_name, vendor, ingest_channel,
        source_file, notes, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    `
    )
    .run(dataSourceId, userId, "rule_test", "规则测试数据源", null, "manual", null, null);

  return database;
}

function ensureMetricDefinition(database: ReturnType<typeof setupDatabase>, metricCode: keyof typeof metricMeta) {
  const meta = metricMeta[metricCode];

  database
    .prepare(
      `
      INSERT INTO metric_definition (
        metric_code, metric_name, category, description, canonical_unit,
        better_direction, reference_range, supported_source_types, is_active,
        created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT(metric_code) DO NOTHING
    `
    )
    .run(
      metricCode,
      meta.metricName,
      meta.category,
      `${meta.metricName} test metric`,
      meta.unit,
      meta.betterDirection,
      meta.referenceRange,
      "manual"
    );
}

function insertMetricSeries(
  database: ReturnType<typeof setupDatabase>,
  metricCode: keyof typeof metricMeta,
  entries: Array<{ sampleTime: string; value: number; abnormalFlag?: string }>
) {
  ensureMetricDefinition(database, metricCode);
  const meta = metricMeta[metricCode];

  for (const [index, entry] of entries.entries()) {
    database
      .prepare(
        `
        INSERT INTO metric_record (
          id, user_id, data_source_id, import_task_id, metric_code,
          metric_name, category, raw_value, normalized_value, unit,
          reference_range, abnormal_flag, sample_time, source_type,
          source_file, notes, created_at
        )
        VALUES (?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
      `
      )
      .run(
        `${metricCode}::${index + 1}`,
        userId,
        dataSourceId,
        metricCode,
        meta.metricName,
        meta.category,
        String(entry.value),
        entry.value,
        meta.unit,
        meta.referenceRange,
        entry.abnormalFlag ?? "normal",
        entry.sampleTime,
        "rule_test",
        "rule-test.csv",
        null
      );
  }
}

test("metric summaries include trend direction and historical comparisons", () => {
  const database = setupDatabase();

  insertMetricSeries(database, "body.weight", [
    { sampleTime: "2025-03-08T08:00:00+08:00", value: 82.6, abnormalFlag: "high" },
    { sampleTime: "2026-02-08T08:00:00+08:00", value: 81.9, abnormalFlag: "normal" },
    { sampleTime: "2026-03-08T08:00:00+08:00", value: 80.8, abnormalFlag: "normal" }
  ]);

  const result = generateStructuredInsights(database, userId);
  const summary = result.metric_summaries.find((item) => item.metric_code === "body.weight");

  assert.equal(summary?.trend_direction, "down");
  assert.ok(typeof summary?.latest_vs_mean === "number");
  assert.ok(typeof summary?.month_over_month === "number");
  assert.ok(typeof summary?.year_over_year === "number");
});

test("latest out-of-range values produce anomaly insights", () => {
  const database = setupDatabase();

  insertMetricSeries(database, "lipid.ldl_c", [
    { sampleTime: "2026-01-08T08:00:00+08:00", value: 3.2, abnormalFlag: "normal" },
    { sampleTime: "2026-03-08T08:00:00+08:00", value: 4.1, abnormalFlag: "high" }
  ]);

  const result = generateStructuredInsights(database, userId);

  assert.ok(result.insights.some((item) => item.title.includes("最近一次高于参考范围")));
});

test("consecutive abnormal values produce continuous abnormal insights", () => {
  const database = setupDatabase();

  insertMetricSeries(database, "lipid.triglycerides", [
    { sampleTime: "2026-01-08T08:00:00+08:00", value: 2.0, abnormalFlag: "high" },
    { sampleTime: "2026-02-08T08:00:00+08:00", value: 2.2, abnormalFlag: "high" },
    { sampleTime: "2026-03-08T08:00:00+08:00", value: 2.1, abnormalFlag: "high" }
  ]);

  const result = generateStructuredInsights(database, userId);

  assert.ok(result.insights.some((item) => item.title.includes("连续 3 次偏高")));
});

test("near-threshold values produce borderline warning insights", () => {
  const database = setupDatabase();

  insertMetricSeries(database, "glycemic.glucose", [
    { sampleTime: "2026-01-08T08:00:00+08:00", value: 5.8, abnormalFlag: "normal" },
    { sampleTime: "2026-03-08T08:00:00+08:00", value: 5.95, abnormalFlag: "normal" }
  ]);

  const result = generateStructuredInsights(database, userId);

  assert.ok(result.insights.some((item) => item.title.includes("接近参考范围上限")));
});

test("body fat decrease with higher exercise load produces positive correlation insight", () => {
  const database = setupDatabase();

  insertMetricSeries(database, "body.body_fat_pct", [
    { sampleTime: "2026-02-15T08:00:00+08:00", value: 23.4, abnormalFlag: "high" },
    { sampleTime: "2026-03-08T08:00:00+08:00", value: 22.6, abnormalFlag: "high" }
  ]);
  insertMetricSeries(database, "activity.exercise_minutes", [
    { sampleTime: "2026-02-10T08:00:00+08:00", value: 20 },
    { sampleTime: "2026-02-18T08:00:00+08:00", value: 24 },
    { sampleTime: "2026-02-24T08:00:00+08:00", value: 54 },
    { sampleTime: "2026-03-01T08:00:00+08:00", value: 58 },
    { sampleTime: "2026-03-05T08:00:00+08:00", value: 60 }
  ]);

  const result = generateStructuredInsights(database, userId);

  assert.ok(result.insights.some((item) => item.id === "correlation-body-fat-vs-activity-positive"));
});

test("body fat improvement with worsening LDL produces divergence insight", () => {
  const database = setupDatabase();

  insertMetricSeries(database, "body.body_fat_pct", [
    { sampleTime: "2026-02-01T08:00:00+08:00", value: 23.5, abnormalFlag: "high" },
    { sampleTime: "2026-03-08T08:00:00+08:00", value: 22.8, abnormalFlag: "high" }
  ]);
  insertMetricSeries(database, "lipid.ldl_c", [
    { sampleTime: "2026-02-08T08:00:00+08:00", value: 3.1, abnormalFlag: "normal" },
    { sampleTime: "2026-03-08T08:00:00+08:00", value: 3.5, abnormalFlag: "high" }
  ]);

  const result = generateStructuredInsights(database, userId);

  assert.ok(result.insights.some((item) => item.id === "correlation-body-fat-vs-lipid-divergence"));
});

test("higher exercise frequency with lower weight produces positive correlation insight", () => {
  const database = setupDatabase();

  insertMetricSeries(database, "activity.exercise_minutes", [
    { sampleTime: "2026-02-12T08:00:00+08:00", value: 24 },
    { sampleTime: "2026-02-24T08:00:00+08:00", value: 42 },
    { sampleTime: "2026-02-27T08:00:00+08:00", value: 48 },
    { sampleTime: "2026-03-01T08:00:00+08:00", value: 55 },
    { sampleTime: "2026-03-05T08:00:00+08:00", value: 53 }
  ]);
  insertMetricSeries(database, "body.weight", [
    { sampleTime: "2026-02-15T08:00:00+08:00", value: 82.4, abnormalFlag: "high" },
    { sampleTime: "2026-03-08T08:00:00+08:00", value: 81.6, abnormalFlag: "normal" }
  ]);

  const result = generateStructuredInsights(database, userId);

  assert.ok(result.insights.some((item) => item.id === "correlation-exercise-frequency-vs-weight-positive"));
});
