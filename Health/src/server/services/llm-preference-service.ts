import type { DatabaseSync } from "node:sqlite";

const KEY_PREFIX = "preferred_provider:";

export function getUserPreferredProvider(db: DatabaseSync, userId: string): string | null {
  const row = db.prepare("SELECT value FROM app_meta WHERE key = ?").get(`${KEY_PREFIX}${userId}`) as { value: string } | undefined;
  return row?.value ?? null;
}

export function setUserPreferredProvider(db: DatabaseSync, userId: string, provider: string | null): void {
  if (provider) {
    db.prepare(
      "INSERT INTO app_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
    ).run(`${KEY_PREFIX}${userId}`, provider);
  } else {
    db.prepare("DELETE FROM app_meta WHERE key = ?").run(`${KEY_PREFIX}${userId}`);
  }
}
