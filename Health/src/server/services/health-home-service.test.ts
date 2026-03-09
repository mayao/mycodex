import assert from "node:assert/strict";
import test from "node:test";

import { runPendingMigrations } from "../db/migration-runner";
import { seedDatabase } from "../db/seed";
import { createInMemoryDatabase } from "../db/sqlite";
import { getHealthHomePageData } from "./health-home-service";

test("health home service returns overview cards, charts and latest narrative", async () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);

  const data = await getHealthHomePageData(database, "user-self");

  assert.ok(data.overviewCards.length >= 10);
  assert.equal(data.sourceDimensions.length, 5);
  assert.ok(data.overviewHeadline.includes("年度体检"));
  assert.ok(data.charts.lipid.data.length > 0);
  assert.ok(data.charts.recovery.data.length > 0);
  assert.ok(data.keyReminders.length > 0);
  assert.ok(data.keyReminders.some((item) => item.title.includes("体检") || item.title.includes("基因")));
  assert.ok(data.keyReminders.some((item) => typeof item.indicatorMeaning === "string"));
  assert.ok(data.keyReminders.some((item) => typeof item.practicalAdvice === "string"));
  assert.ok(data.annualExam?.latestTitle.includes("2025"));
  assert.ok(data.annualExam?.metrics.some((metric) => typeof metric.meaning === "string"));
  assert.ok((data.geneticFindings?.length ?? 0) >= 2);
  assert.ok(data.geneticFindings.some((item) => typeof item.plainMeaning === "string"));
  assert.ok(data.latestNarrative.output.priority_actions.length > 0);
  assert.ok(data.latestReports.length >= 2);
});
