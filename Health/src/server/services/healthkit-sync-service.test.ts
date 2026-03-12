import assert from "node:assert/strict";
import test from "node:test";

import { runPendingMigrations } from "../db/migration-runner";
import { seedDatabase } from "../db/seed";
import { createInMemoryDatabase } from "../db/sqlite";
import { getHealthHomePageData } from "./health-home-service";
import { syncHealthKitSamples } from "./healthkit-sync-service";

function setupDatabase() {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);
  return database;
}

test("healthkit sync accepts iOS snake_case payload fields", () => {
  const database = setupDatabase();

  const result = syncHealthKitSamples(
    {
      samples: [
        {
          kind: "weight",
          value: 77.5,
          unit: "kg",
          sample_time: "2026-03-11T07:30:00+08:00",
          source_label: "iPhone"
        },
        {
          kind: "sleepMinutes",
          value: 420,
          unit: "min",
          sample_time: "2026-03-11",
          source_label: "Apple Watch"
        }
      ]
    },
    database
  );

  assert.equal(result.taskStatus, "completed");
  assert.equal(result.successRecords, 2);

  const records = database
    .prepare(
      `
      SELECT metric_code, normalized_value, unit, sample_time, notes
      FROM metric_record
      WHERE import_task_id = ?
      ORDER BY metric_code ASC
    `
    )
    .all(result.importTaskId) as Array<{
      metric_code: string;
      normalized_value: number;
      unit: string;
      sample_time: string;
      notes: string | null;
    }>;

  assert.deepEqual(
    records.map((record) => record.metric_code),
    ["body.weight", "sleep.asleep_minutes"]
  );
  assert.equal(records[0]?.normalized_value, 77.5);
  assert.equal(records[0]?.sample_time, "2026-03-11T07:30:00+08:00");
  assert.equal(records[0]?.notes, "iPhone");
  assert.equal(records[1]?.normalized_value, 420);
  assert.equal(records[1]?.sample_time, "2026-03-11T08:00:00+08:00");
  assert.equal(records[1]?.notes, "Apple Watch");
});

test("healthkit sync accepts alternate time fields and numeric strings", () => {
  const database = setupDatabase();

  const result = syncHealthKitSamples(
    {
      samples: [
        {
          kind: "steps",
          value: "8123",
          unit: "count",
          recorded_at: "2026-03-11"
        },
        {
          kind: "exerciseMinutes",
          value: "42",
          unit: "min",
          sample_date: "2026-03-11"
        }
      ]
    },
    database
  );

  assert.equal(result.taskStatus, "completed");
  assert.equal(result.successRecords, 2);

  const records = database
    .prepare(
      `
      SELECT metric_code, normalized_value, sample_time
      FROM metric_record
      WHERE import_task_id = ?
      ORDER BY metric_code ASC
    `
    )
    .all(result.importTaskId) as Array<{
      metric_code: string;
      normalized_value: number;
      sample_time: string;
    }>;

  assert.deepEqual(
    records.map((record) => record.metric_code),
    ["activity.exercise_minutes", "activity.steps"]
  );
  assert.equal(records[0]?.normalized_value, 42);
  assert.equal(records[0]?.sample_time, "2026-03-11T08:00:00+08:00");
  assert.equal(records[1]?.normalized_value, 8123);
  assert.equal(records[1]?.sample_time, "2026-03-11T08:00:00+08:00");
});

test("health home data reflects newly synced Apple Health samples", async () => {
  const database = setupDatabase();

  syncHealthKitSamples(
    {
      samples: [
        {
          kind: "weight",
          value: 77.2,
          unit: "kg",
          sample_time: "2026-03-11T07:20:00+08:00"
        },
        {
          kind: "exerciseMinutes",
          value: 46,
          unit: "min",
          sample_time: "2026-03-11"
        },
        {
          kind: "sleepMinutes",
          value: 435,
          unit: "min",
          sample_time: "2026-03-11"
        }
      ]
    },
    database
  );

  const data = await getHealthHomePageData(database, "user-self");
  const appleHealth = data.sourceDimensions.find((item) => item.key === "apple_health");

  assert.equal(appleHealth?.highlight, "已同步 3 条");
  assert.equal(appleHealth?.latestAt, "2026-03-11T08:00:00+08:00");
  assert.equal(data.charts.bodyComposition.data.at(-1)?.weight, 77.2);
  assert.equal(data.charts.activity.data.at(-1)?.exerciseMinutes, 46);
  assert.equal(data.charts.recovery.data.at(-1)?.sleepMinutes, 435);
});
