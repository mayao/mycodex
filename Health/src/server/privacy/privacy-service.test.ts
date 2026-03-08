import assert from "node:assert/strict";
import test from "node:test";

import { runPendingMigrations } from "../db/migration-runner";
import { seedDatabase } from "../db/seed";
import { createInMemoryDatabase } from "../db/sqlite";
import { buildPrivacyDeletePlaceholder, buildPrivacyExportPlaceholder } from "./privacy-service";

function setupDatabase() {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);
  return database;
}

function withEnv<T>(entries: Record<string, string | undefined>, run: () => T): T {
  const previous = Object.fromEntries(
    Object.keys(entries).map((key) => [key, process.env[key]])
  );

  for (const [key, value] of Object.entries(entries)) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  try {
    return run();
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

test("privacy export placeholder returns counts and sensitive field catalog", () => {
  const database = setupDatabase();

  withEnv(
    {
      HEALTH_ALLOW_LOCAL_EXPORTS: "0"
    },
    () => {
      const result = buildPrivacyExportPlaceholder(
        {
          scope: "imports",
          format: "json",
          includeAuditLogs: false
        },
        database
      );
      const availableData = result.availableData as {
        importTasks: number;
        importRowLogs: number;
      };

      assert.equal(result.status, "placeholder");
      assert.equal(result.enabled, false);
      assert.equal(availableData.importTasks > 0, true);
      assert.equal(availableData.importRowLogs >= 0, true);
      assert.ok(result.sensitiveFields.some((field) => field.category === "health_metric"));
    }
  );
});

test("privacy delete placeholder requires confirmation and respects local env gate", () => {
  const database = setupDatabase();

  withEnv(
    {
      HEALTH_ALLOW_LOCAL_DELETE: "1"
    },
    () => {
      const result = buildPrivacyDeletePlaceholder(
        {
          scope: "all",
          confirm: false
        },
        database
      );
      const availableData = result.availableData as {
        metricRecords: number;
        reportSnapshots: number;
      };

      assert.equal(result.status, "placeholder");
      assert.equal(result.enabled, true);
      assert.equal(result.requiresExplicitConfirmation, true);
      assert.equal(availableData.metricRecords > 0, true);
      assert.equal(availableData.reportSnapshots > 0, true);
    }
  );
});
