import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import { getDatabase } from "../../db/sqlite";

let cachedServerId: string | null = null;

/**
 * Get or create the persistent server ID for this instance.
 * Stored in app_meta table and cached in-process.
 */
export function getServerId(database: DatabaseSync = getDatabase()): string {
  if (cachedServerId) return cachedServerId;

  const row = database
    .prepare("SELECT value FROM app_meta WHERE key = ?")
    .get("server_id") as { value: string } | undefined;

  if (row?.value) {
    cachedServerId = row.value;
    return cachedServerId;
  }

  // Generate and persist a new server ID
  const newId = randomUUID();
  database
    .prepare("INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)")
    .run("server_id", newId);

  cachedServerId = newId;
  return cachedServerId;
}
