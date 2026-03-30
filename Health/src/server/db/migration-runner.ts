import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { DatabaseSync } from "node:sqlite";

export const unifiedTables = [
  "users",
  "user_identity",
  "metric_definition",
  "metric_record",
  "data_source",
  "import_task",
  "insight_record",
  "report_snapshot"
] as const;

const migrationsDirectory = join(process.cwd(), "migrations");

interface AppliedMigrationRow {
  id: string;
}

export function ensureMigrationTable(database: DatabaseSync): void {
  database.exec(`
    CREATE TABLE IF NOT EXISTS schema_migration (
      id TEXT PRIMARY KEY,
      applied_at TEXT NOT NULL
    );
  `);
}

export function runPendingMigrations(database: DatabaseSync): string[] {
  ensureMigrationTable(database);

  const applied = new Set(listAppliedMigrations(database));

  const pendingFiles = readdirSync(migrationsDirectory)
    .filter((name) => name.endsWith(".sql"))
    .sort()
    .filter((name) => !applied.has(name));

  for (const fileName of pendingFiles) {
    const sql = readFileSync(join(migrationsDirectory, fileName), "utf8");
    database.exec("BEGIN");

    try {
      database.exec(sql);
      database
        .prepare("INSERT INTO schema_migration (id, applied_at) VALUES (?, ?)")
        .run(fileName, new Date().toISOString());
      database.exec("COMMIT");
    } catch (error) {
      database.exec("ROLLBACK");
      throw error;
    }
  }

  return pendingFiles;
}

export function listAppliedMigrations(database: DatabaseSync): string[] {
  ensureMigrationTable(database);

  const appliedRows = database
    .prepare("SELECT id FROM schema_migration ORDER BY id ASC")
    .all() as unknown as AppliedMigrationRow[];

  return appliedRows.map((row) => row.id);
}
