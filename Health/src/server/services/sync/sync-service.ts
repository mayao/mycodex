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
  { name: "user_identity", pk: "id", updatedAtCol: "updated_at" },
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

export interface SyncRunSummary {
  attempted_peers: number;
  successful_peers: number;
  failed_peers: number;
  message: string;
}

interface DiscoverPeerPayload {
  service?: string;
  name?: string;
  ip?: string;
  port?: number;
  server_id?: string;
}

function getLocalServerBaseUrl(): string {
  const port = Number(process.env.PORT ?? 3000);
  const host =
    process.env.SYNC_SERVER_URL?.trim().replace(/\/$/, "") ||
    process.env.PUBLIC_BASE_URL?.trim().replace(/\/$/, "") ||
    `http://127.0.0.1:${port}`;
  return normalizePeerUrl(host);
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
          .get(pkValue as string) as { local_updated: string | null; local_origin: string | null } | undefined;

        const remoteUpdated = row[tableDef.updatedAtCol] as string | null;

        if (!localRow) {
          // INSERT — row doesn't exist locally
          const validCols = columns.filter((c) => c in row);
          const placeholders = validCols.map(() => "?").join(", ");
          const values = validCols.map((c) => row[c] ?? null) as unknown[];

          database
            .prepare(
              `INSERT OR IGNORE INTO ${tableDef.name} (${validCols.join(", ")}) VALUES (${placeholders})`
            )
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            .run(...(values as any[]))
          applied++;
        } else if (remoteUpdated && localRow.local_updated && remoteUpdated > localRow.local_updated) {
          // UPDATE — remote is newer (last-write-wins)
          const updateCols = columns.filter(
            (c) => c !== tableDef.pk && c in row
          );
          const setClause = updateCols.map((c) => `${c} = ?`).join(", ");
          const values = updateCols.map((c) => row[c] ?? null) as unknown[];
          values.push(pkValue);

          database
            .prepare(
              `UPDATE ${tableDef.name} SET ${setClause} WHERE ${tableDef.pk} = ?`
            )
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            .run(...(values as any[]))
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
            const values = updateCols.map((c) => row[c] ?? null) as unknown[];
            values.push(pkValue);

            database
              .prepare(
                `UPDATE ${tableDef.name} SET ${setClause} WHERE ${tableDef.pk} = ?`
              )
              // eslint-disable-next-line @typescript-eslint/no-explicit-any
              .run(...(values as any[]))
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
    headers: {
      "X-Sync-Server-Id": getServerId(database),
      "X-Sync-Server-Name": "HealthAI",
      "X-Sync-Server-Url": getLocalServerBaseUrl(),
    },
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
        "X-Sync-Server-Name": "HealthAI",
        "X-Sync-Server-Url": getLocalServerBaseUrl(),
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

function normalizePeerUrl(url: string): string {
  const trimmed = url.trim();
  if (!trimmed) return trimmed;

  try {
    const parsed = new URL(trimmed.endsWith("/") ? trimmed : `${trimmed}/`);
    parsed.pathname = "/";
    parsed.search = "";
    parsed.hash = "";
    return parsed.toString();
  } catch {
    return trimmed;
  }
}

async function registerPeerByUrl(
  peerUrl: string,
  database: DatabaseSync
): Promise<SyncPeer> {
  const normalizedUrl = normalizePeerUrl(peerUrl);
  const discoverUrl = `${normalizedUrl.replace(/\/$/, "")}/api/discover`;
  const response = await fetch(discoverUrl, {
    signal: AbortSignal.timeout(5000),
  });

  if (!response.ok) {
    throw new Error(`发现节点失败: ${response.status}`);
  }

  const payload = (await response.json()) as DiscoverPeerPayload;
  if (payload.service !== "vital-command") {
    throw new Error("发现的服务不是 HealthAI 节点");
  }

  const peerServerId = payload.server_id;
  if (!peerServerId) {
    throw new Error("发现信息缺少 server_id");
  }

  const localServerId = getServerId(database);
  if (peerServerId === localServerId) {
    throw new Error("目标节点与当前服务器使用了相同的 server_id，请先修复实例标识");
  }

  const peerName = payload.name?.trim() || normalizedUrl;
  const peerBaseUrl =
    payload.ip && payload.port
      ? normalizePeerUrl(`http://${payload.ip}:${payload.port}/`)
      : normalizedUrl;
  const now = new Date().toISOString();

  const existing = database
    .prepare("SELECT server_id FROM sync_peer WHERE server_id = ?")
    .get(peerServerId) as { server_id: string } | undefined;

  if (existing) {
    database
      .prepare(
        "UPDATE sync_peer SET name = ?, url = ?, last_seen_at = ? WHERE server_id = ?"
      )
      .run(peerName, peerBaseUrl, now, peerServerId);
  } else {
    database
      .prepare(
        "INSERT INTO sync_peer (server_id, name, url, last_seen_at, created_at) VALUES (?, ?, ?, ?, ?)"
      )
      .run(peerServerId, peerName, peerBaseUrl, now, now);
  }

  return {
    server_id: peerServerId,
    name: peerName,
    url: peerBaseUrl,
    last_seen_at: now,
    last_sync_at: null,
    last_sync_cursor: null,
    created_at: now,
  };
}

// ---------------------------------------------------------------------------
// Sync with all known peers
// ---------------------------------------------------------------------------

let isSyncing = false;

export async function syncWithAllPeers(
  options: { candidatePeerUrls?: string[] } = {},
  database: DatabaseSync = getDatabase()
): Promise<SyncRunSummary> {
  if (isSyncing) {
    return {
      attempted_peers: 0,
      successful_peers: 0,
      failed_peers: 0,
      message: "同步任务已在进行中，请稍后再试。",
    };
  }
  isSyncing = true;

  try {
    const registrationErrors: string[] = [];
    const candidateUrls = [...new Set(
      (options.candidatePeerUrls ?? [])
        .map((url) => normalizePeerUrl(url))
        .filter(Boolean)
    )];

    for (const peerUrl of candidateUrls) {
      try {
        await registerPeerByUrl(peerUrl, database);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        registrationErrors.push(`${peerUrl}: ${message}`);
      }
    }

    const recentPeers = database
      .prepare(
        "SELECT server_id, url, name FROM sync_peer WHERE last_seen_at > datetime('now', '-5 minutes')"
      )
      .all() as unknown as SyncPeer[];

    const fallbackPeers = recentPeers.length > 0
      ? []
      : (database
          .prepare(
            "SELECT server_id, url, name FROM sync_peer ORDER BY COALESCE(last_seen_at, created_at) DESC LIMIT 12"
          )
          .all() as unknown as SyncPeer[]);

    const peers = [...recentPeers, ...fallbackPeers].filter((peer, index, all) =>
      all.findIndex((candidate) => candidate.server_id === peer.server_id) == index
    );

    if (peers.length === 0) {
      return {
        attempted_peers: 0,
        successful_peers: 0,
        failed_peers: registrationErrors.length,
        message: registrationErrors.length === 0
          ? "当前没有可同步的其他节点，请先扫描或保存另一台服务器地址。"
          : `没有可同步的其他节点。${registrationErrors.join("；")}`,
      };
    }

    let successfulPeers = 0;
    let failedPeers = registrationErrors.length;

    for (const peer of peers) {
      try {
        const result = await syncWithPeer(peer.url, peer.server_id, database);
        console.log(
          `[Sync] ✅ ${peer.name}: pulled ${result.pulled.applied}, pushed ${result.pushed.rows_sent}`
        );
        successfulPeers += 1;
      } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        console.error(`[Sync] ❌ ${peer.name}: ${msg}`);
        failedPeers += 1;

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

    const attemptedPeers = peers.length;
    const message =
      successfulPeers > 0
        ? `已完成 ${successfulPeers}/${attemptedPeers} 个节点同步。`
        : failedPeers > 0
          ? "没有节点同步成功，请检查另一台服务器地址、登录和网络连通性。"
          : "当前没有可执行的同步任务。";

    return {
      attempted_peers: attemptedPeers,
      successful_peers: successfulPeers,
      failed_peers: failedPeers,
      message,
    };
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
