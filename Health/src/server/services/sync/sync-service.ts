import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import { getDatabase } from "../../db/sqlite";
import { getServerId } from "./server-identity";

// ---------------------------------------------------------------------------
// Syncable table registry (ordered by foreign key dependencies)
// ---------------------------------------------------------------------------

interface SyncableTable {
  name: string;
  pk: string;
  updatedAtCol: string;
}

const SYNCABLE_TABLES: SyncableTable[] = [
  { name: "users", pk: "id", updatedAtCol: "updated_at" },
  { name: "metric_definition", pk: "metric_code", updatedAtCol: "updated_at" },
  { name: "data_source", pk: "id", updatedAtCol: "updated_at" },
  { name: "import_task", pk: "id", updatedAtCol: "updated_at" },
  { name: "metric_record", pk: "id", updatedAtCol: "updated_at" },
  { name: "insight_record", pk: "id", updatedAtCol: "updated_at" },
  { name: "report_snapshot", pk: "id", updatedAtCol: "updated_at" },
  { name: "health_suggestion_batch", pk: "id", updatedAtCol: "updated_at" },
  { name: "health_suggestion", pk: "id", updatedAtCol: "updated_at" },
  { name: "health_plan_item", pk: "id", updatedAtCol: "updated_at" },
  { name: "health_plan_check", pk: "id", updatedAtCol: "updated_at" },
];

const ROWS_PER_TABLE_LIMIT = 1000;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface SyncChangesResponse {
  server_id: string;
  changes: Record<string, Record<string, unknown>[]>;
  cursor: string; // max updated_at across all returned rows
}

export interface ApplyResult {
  applied: number;
  skipped: number;
  conflicts: number;
}

export interface SyncPeer {
  server_id: string;
  name: string;
  url: string;
  last_seen_at: string;
  last_sync_at: string | null;
  last_sync_cursor: string | null;
  created_at: string;
}

export interface SyncLogEntry {
  id: string;
  peer_server_id: string;
  direction: string;
  tables_synced: string;
  rows_received: number;
  rows_sent: number;
  status: string;
  error_message: string | null;
  started_at: string;
  finished_at: string;
}

// ---------------------------------------------------------------------------
// Get changes since a timestamp
// ---------------------------------------------------------------------------

export function getChangesSince(
  since: string,
  tableFilter?: string[],
  database: DatabaseSync = getDatabase()
): SyncChangesResponse {
  const serverId = getServerId(database);
  const tables = tableFilter
    ? SYNCABLE_TABLES.filter((t) => tableFilter.includes(t.name))
    : SYNCABLE_TABLES;

  const changes: Record<string, Record<string, unknown>[]> = {};
  let maxCursor = since;

  for (const table of tables) {
    const rows = database
      .prepare(
        `SELECT * FROM ${table.name} WHERE ${table.updatedAtCol} > ? ORDER BY ${table.updatedAtCol} ASC LIMIT ?`
      )
      .all(since, ROWS_PER_TABLE_LIMIT) as unknown as Record<string, unknown>[];

    if (rows.length > 0) {
      changes[table.name] = rows;
      // Track the max updated_at as cursor
      const lastRow = rows[rows.length - 1];
      const lastUpdated = lastRow[table.updatedAtCol] as string;
      if (lastUpdated > maxCursor) {
        maxCursor = lastUpdated;
      }
    }
  }

  return { server_id: serverId, changes, cursor: maxCursor };
}

// ---------------------------------------------------------------------------
// Apply changes from a peer
// ---------------------------------------------------------------------------

function getTableColumns(
  tableName: string,
  database: DatabaseSync
): string[] {
  const info = database
    .prepare(`PRAGMA table_info(${tableName})`)
    .all() as unknown as Array<{ name: string }>;
  return info.map((col) => col.name);
}

export function applyChanges(
  changes: Record<string, Record<string, unknown>[]>,
  peerServerId: string,
  database: DatabaseSync = getDatabase()
): ApplyResult {
  let applied = 0;
  let skipped = 0;
  let conflicts = 0;

  // Process tables in dependency order
  for (const tableDef of SYNCABLE_TABLES) {
    const rows = changes[tableDef.name];
    if (!rows || rows.length === 0) continue;

    const columns = getTableColumns(tableDef.name, database);

    database.exec("BEGIN");
    try {
      for (const row of rows) {
        const pkValue = row[tableDef.pk];
        if (pkValue == null) {
          skipped++;
          continue;
        }

        // Check if row exists locally
        const localRow = database
          .prepare(`SELECT ${tableDef.updatedAtCol} AS local_updated, origin_server_id AS local_origin FROM ${tableDef.name} WHERE ${tableDef.pk} = ?`)
          .get(pkValue) as { local_updated: string | null; local_origin: string | null } | undefined;

        const remoteUpdated = row[tableDef.updatedAtCol] as string | null;

        if (!localRow) {
          // INSERT — row doesn't exist locally
          const validCols = columns.filter((c) => c in row);
          const placeholders = validCols.map(() => "?").join(", ");
          const values = validCols.map((c) => row[c] ?? null);

          database
            .prepare(
              `INSERT OR IGNORE INTO ${tableDef.name} (${validCols.join(", ")}) VALUES (${placeholders})`
            )
            .run(...values);
          applied++;
        } else if (remoteUpdated && localRow.local_updated && remoteUpdated > localRow.local_updated) {
          // UPDATE — remote is newer (last-write-wins)
          const updateCols = columns.filter(
            (c) => c !== tableDef.pk && c in row
          );
          const setClause = updateCols.map((c) => `${c} = ?`).join(", ");
          const values = updateCols.map((c) => row[c] ?? null);
          values.push(pkValue);

          database
            .prepare(
              `UPDATE ${tableDef.name} SET ${setClause} WHERE ${tableDef.pk} = ?`
            )
            .run(...values);
          applied++;
          conflicts++;
        } else if (
          remoteUpdated &&
          localRow.local_updated &&
          remoteUpdated === localRow.local_updated
        ) {
          // Tie-breaker: higher origin_server_id wins
          const remoteOrigin = (row.origin_server_id as string) ?? peerServerId;
          const localOrigin = localRow.local_origin ?? getServerId(database);
          if (remoteOrigin > localOrigin) {
            const updateCols = columns.filter(
              (c) => c !== tableDef.pk && c in row
            );
            const setClause = updateCols.map((c) => `${c} = ?`).join(", ");
            const values = updateCols.map((c) => row[c] ?? null);
            values.push(pkValue);

            database
              .prepare(
                `UPDATE ${tableDef.name} SET ${setClause} WHERE ${tableDef.pk} = ?`
              )
              .run(...values);
            applied++;
            conflicts++;
          } else {
            skipped++;
          }
        } else {
          // Local is newer or same — skip
          skipped++;
        }
      }
      database.exec("COMMIT");
    } catch (error) {
      database.exec("ROLLBACK");
      throw error;
    }
  }

  return { applied, skipped, conflicts };
}

// ---------------------------------------------------------------------------
// Sync with a single peer
// ---------------------------------------------------------------------------

export async function syncWithPeer(
  peerUrl: string,
  peerServerId: string,
  database: DatabaseSync = getDatabase()
): Promise<{ pulled: ApplyResult; pushed: { rows_sent: number } }> {
  const startedAt = new Date().toISOString();

  // Read cursor
  const peer = database
    .prepare("SELECT last_sync_cursor FROM sync_peer WHERE server_id = ?")
    .get(peerServerId) as { last_sync_cursor: string | null } | undefined;

  const cursor = peer?.last_sync_cursor ?? "1970-01-01T00:00:00.000Z";

  // Pull: get changes from peer
  const pullUrl = `${peerUrl.replace(/\/$/, "")}/api/sync/changes?since=${encodeURIComponent(cursor)}`;
  const pullResponse = await fetch(pullUrl, {
    headers: { "X-Sync-Server-Id": getServerId(database) },
    signal: AbortSignal.timeout(15000),
  });

  if (!pullResponse.ok) {
    throw new Error(`Pull from ${peerUrl} failed: ${pullResponse.status}`);
  }

  const pullData = (await pullResponse.json()) as SyncChangesResponse;
  const pullResult = applyChanges(pullData.changes, peerServerId, database);

  // Push: send our changes since the cursor to the peer
  const localChanges = getChangesSince(cursor, undefined, database);
  let rowsSent = 0;

  const totalRows = Object.values(localChanges.changes).reduce(
    (sum, rows) => sum + rows.length,
    0
  );

  if (totalRows > 0) {
    const pushUrl = `${peerUrl.replace(/\/$/, "")}/api/sync/apply`;
    const pushResponse = await fetch(pushUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Sync-Server-Id": getServerId(database),
      },
      body: JSON.stringify({
        server_id: getServerId(database),
        changes: localChanges.changes,
      }),
      signal: AbortSignal.timeout(30000),
    });

    if (pushResponse.ok) {
      rowsSent = totalRows;
    }
  }

  // Update peer cursor
  const newCursor =
    pullData.cursor > localChanges.cursor
      ? pullData.cursor
      : localChanges.cursor;
  const now = new Date().toISOString();

  database
    .prepare(
      "UPDATE sync_peer SET last_sync_at = ?, last_sync_cursor = ? WHERE server_id = ?"
    )
    .run(now, newCursor, peerServerId);

  // Write sync log
  const finishedAt = new Date().toISOString();
  database
    .prepare(
      `INSERT INTO sync_log (id, peer_server_id, direction, tables_synced, rows_received, rows_sent, status, started_at, finished_at)
       VALUES (?, ?, 'bidirectional', ?, ?, ?, 'success', ?, ?)`
    )
    .run(
      randomUUID(),
      peerServerId,
      Object.keys({ ...pullData.changes, ...localChanges.changes }).join(","),
      pullResult.applied,
      rowsSent,
      startedAt,
      finishedAt
    );

  return {
    pulled: pullResult,
    pushed: { rows_sent: rowsSent },
  };
}

// ---------------------------------------------------------------------------
// Sync with all known peers
// ---------------------------------------------------------------------------

let isSyncing = false;

export async function syncWithAllPeers(
  database: DatabaseSync = getDatabase()
): Promise<void> {
  if (isSyncing) return;
  isSyncing = true;

  try {
    const peers = database
      .prepare(
        "SELECT server_id, url, name FROM sync_peer WHERE last_seen_at > datetime('now', '-5 minutes')"
      )
      .all() as unknown as SyncPeer[];

    for (const peer of peers) {
      try {
        const result = await syncWithPeer(peer.url, peer.server_id, database);
        console.log(
          `[Sync] ✅ ${peer.name}: pulled ${result.pulled.applied}, pushed ${result.pushed.rows_sent}`
        );
      } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        console.error(`[Sync] ❌ ${peer.name}: ${msg}`);

        // Log error
        database
          .prepare(
            `INSERT INTO sync_log (id, peer_server_id, direction, tables_synced, rows_received, rows_sent, status, error_message, started_at, finished_at)
             VALUES (?, ?, 'bidirectional', '', 0, 0, 'error', ?, ?, ?)`
          )
          .run(
            randomUUID(),
            peer.server_id,
            msg,
            new Date().toISOString(),
            new Date().toISOString()
          );
      }
    }
  } finally {
    isSyncing = false;
  }
}

// ---------------------------------------------------------------------------
// Get sync status
// ---------------------------------------------------------------------------

export function getSyncStatus(database: DatabaseSync = getDatabase()) {
  const serverId = getServerId(database);

  const peers = database
    .prepare("SELECT * FROM sync_peer ORDER BY last_seen_at DESC")
    .all() as unknown as SyncPeer[];

  const recentLogs = database
    .prepare(
      "SELECT * FROM sync_log ORDER BY finished_at DESC LIMIT 20"
    )
    .all() as unknown as SyncLogEntry[];

  return {
    server_id: serverId,
    peers,
    recent_logs: recentLogs,
  };
}
