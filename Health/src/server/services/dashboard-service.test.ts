import assert from "node:assert/strict";
import test from "node:test";

import { seedDatabase } from "../db/seed";
import { createInMemoryDatabase } from "../db/sqlite";
import { getDashboardData } from "./dashboard-service";

test("dashboard service aggregates seeded SQLite data", () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);

  const dashboard = getDashboardData(database);

  assert.equal(
    dashboard.coverage.find((item) => item.kind === "lipid_panel")?.count,
    3
  );
  assert.equal(dashboard.trends.bodyComposition.at(-1)?.weight, 78.9);
  assert.ok(dashboard.attentionItems.some((item) => item.title.includes("睡眠")));
  assert.equal(dashboard.kpis[0]?.value, "78.9 kg");
});
