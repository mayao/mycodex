import assert from "node:assert/strict";
import test from "node:test";

import { seedDatabase } from "./seed";
import { createInMemoryDatabase } from "./sqlite";
import { listAppliedMigrations, runPendingMigrations, unifiedTables } from "./migration-runner";

test("unified schema migrations create required tables and load 30+ metric records", () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);

  const applied = runPendingMigrations(database);
  assert.deepEqual(applied, [
    "001_unified_health_schema.sql",
    "002_backfill_unified_health_data.sql",
    "003_seed_unified_insight_and_report.sql",
    "004_import_row_log.sql",
    "005_scrub_import_row_payloads.sql",
    "006_sync_seeded_genetic_findings.sql",
    "007_auth_tables.sql",
    "008_device_auth.sql",
    "009_health_plans.sql",
    "010_sync_system.sql",
    "011_genetic_findings_user_id.sql",
    "012_user_scoped_data_source_ids.sql",
    "013_diet_metric_category.sql",
    "014_genetic_findings_unified_source_fk.sql",
    "015_user_identity_and_merge.sql"
  ]);
  assert.deepEqual(listAppliedMigrations(database), applied);

  for (const table of unifiedTables) {
    const row = database
      .prepare(
        `
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name = ?
      `
      )
      .get(table) as { name?: string } | undefined;

    assert.equal(row?.name, table);
  }

  const metricRecordCount = database
    .prepare("SELECT COUNT(*) AS count FROM metric_record")
    .get() as { count: number };
  assert.ok(metricRecordCount.count >= 30);
});

test("metric_record supports same metric across years and different source types", () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);

  const weightHistory = database
    .prepare(
      `
      SELECT metric_code, source_type, sample_time
      FROM metric_record
      WHERE metric_code = 'body.weight'
      ORDER BY sample_time ASC
    `
    )
    .all() as Array<{
    metric_code: string;
    source_type: string;
    sample_time: string;
  }>;

  assert.ok(weightHistory.length >= 5);
  assert.ok(new Set(weightHistory.map((row) => row.source_type)).size >= 2);
  assert.ok(new Set(weightHistory.map((row) => row.sample_time.slice(0, 4))).size >= 2);

  const categories = database
    .prepare("SELECT DISTINCT category FROM metric_record ORDER BY category ASC")
    .all() as Array<{ category: string }>;
  const categorySet = new Set(categories.map((row) => row.category));

  assert.ok(categorySet.has("lipid"));
  assert.ok(categorySet.has("body_composition"));
  assert.ok(categorySet.has("activity"));
  assert.ok(categorySet.has("diet"));
});
