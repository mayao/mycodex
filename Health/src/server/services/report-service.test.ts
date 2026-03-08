import assert from "node:assert/strict";
import test from "node:test";

import { runPendingMigrations } from "../db/migration-runner";
import { seedDatabase } from "../db/seed";
import { createInMemoryDatabase } from "../db/sqlite";
import {
  buildSummaryPeriod,
  getCurrentDailySummary,
  getReportSnapshotDetail,
  getReportsIndexData
} from "./report-service";

function insertFutureMetricRecord(database: ReturnType<typeof createInMemoryDatabase>): void {
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
      "future-activity-steps",
      "user-self",
      "source-apple-health",
      "activity.exercise_minutes",
      "训练分钟",
      "activity",
      "55",
      55,
      "min",
      null,
      "normal",
      "2026-03-09T08:00:00+08:00",
      "activity_import",
      "activity_future.csv",
      "future-dated import row"
    );
}

test("summary periods use the app-local calendar day", () => {
  const daily = buildSummaryPeriod("day", "2026-03-08T01:15:00+08:00");
  const weekly = buildSummaryPeriod("week", "2026-03-08T01:15:00+08:00");

  assert.equal(daily.start, "2026-03-08");
  assert.equal(daily.end, "2026-03-08");
  assert.equal(weekly.start, "2026-03-02");
  assert.equal(weekly.end, "2026-03-08");
});

test("report service creates weekly and monthly snapshots and lists history", async () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);

  const reports = await getReportsIndexData(database, "user-self");

  assert.ok(reports.weeklyReports.length >= 1);
  assert.ok(reports.monthlyReports.length >= 1);
  assert.equal(reports.weeklyReports[0]?.summary.provider, "mock");

  const snapshotDetail = await getReportSnapshotDetail(reports.weeklyReports[0]!.id, database, "user-self");

  assert.equal(snapshotDetail?.id, reports.weeklyReports[0]?.id);
  assert.ok(snapshotDetail?.structuredInsights.insights.length);
});

test("daily summary is available for dashboard latest narrative", async () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);

  const summary = await getCurrentDailySummary(database, "user-self");

  assert.equal(summary.output.period_kind, "day");
  assert.ok(summary.output.most_important_changes.length > 0);
});

test("future-dated metric rows do not shift current summaries or report windows", async () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);
  insertFutureMetricRecord(database);
  const now = new Date("2026-03-08T20:13:56+08:00");

  const summary = await getCurrentDailySummary(database, "user-self", { now });
  const reports = await getReportsIndexData(database, "user-self", { now });

  assert.match(summary.output.headline, /^2026-03-08 日摘要/);
  assert.equal(reports.weeklyReports[0]?.periodEnd, "2026-03-08");
  assert.equal(reports.monthlyReports[0]?.periodEnd, "2026-03-08");
});
