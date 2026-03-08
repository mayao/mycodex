import assert from "node:assert/strict";
import test from "node:test";

import { runPendingMigrations } from "../db/migration-runner";
import { seedDatabase } from "../db/seed";
import { createInMemoryDatabase } from "../db/sqlite";
import { generateHolisticStructuredInsights } from "./holistic-insight-service";

test("holistic structured insights include annual exam and genetic context", () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);

  const result = generateHolisticStructuredInsights(database, "user-self");

  assert.ok(
    result.insights.some((insight) => insight.title.includes("年度体检"))
  );
  assert.ok(
    result.insights.some((insight) => insight.title.includes("Lp(a)") || insight.title.includes("基因背景"))
  );
});
