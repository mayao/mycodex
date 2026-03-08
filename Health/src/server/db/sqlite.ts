import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

import { runPendingMigrations } from "./migration-runner";
import { applySchema } from "./schema";
import { SEED_VERSION, seedDatabase } from "./seed";

export const databasePath = join(process.cwd(), "data", "health-system.sqlite");

let database: DatabaseSync | undefined;

function configureDatabase(target: DatabaseSync): void {
  target.exec("PRAGMA foreign_keys = ON;");
  target.exec("PRAGMA journal_mode = WAL;");
}

function readSeedVersion(target: DatabaseSync): string | undefined {
  const row = target
    .prepare("SELECT value FROM app_meta WHERE key = ?")
    .get("seed_version") as { value?: string } | undefined;

  return row?.value;
}

function bootstrapLegacySchema(target: DatabaseSync): void {
  applySchema(target);

  if (readSeedVersion(target) !== SEED_VERSION) {
    seedDatabase(target);
  }
}

export function createInMemoryDatabase(): DatabaseSync {
  const memoryDatabase = new DatabaseSync(":memory:");
  configureDatabase(memoryDatabase);
  applySchema(memoryDatabase);
  return memoryDatabase;
}

export function getDatabase(): DatabaseSync {
  if (!database) {
    mkdirSync(join(process.cwd(), "data"), { recursive: true });
    database = new DatabaseSync(databasePath);
    configureDatabase(database);
    bootstrapLegacySchema(database);
    runPendingMigrations(database);
  }

  return database;
}
