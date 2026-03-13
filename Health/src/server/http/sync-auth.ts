import { getDatabase } from "../db/sqlite";

/**
 * Validate that a sync request comes from a known peer server.
 * Checks the X-Sync-Server-Id header against the sync_peer table.
 * Returns the peer server_id if valid, null otherwise.
 */
export function validateSyncPeer(request: Request): string | null {
  const serverId = request.headers.get("X-Sync-Server-Id");
  if (!serverId) return null;

  try {
    const database = getDatabase();
    const peer = database
      .prepare("SELECT server_id FROM sync_peer WHERE server_id = ?")
      .get(serverId) as { server_id: string } | undefined;

    return peer?.server_id ?? null;
  } catch {
    return null;
  }
}

/**
 * Validate sync request and return 401 response if invalid.
 * For use in sync API route handlers.
 */
export function requireSyncPeer(request: Request): { serverId: string } | Response {
  const serverId = validateSyncPeer(request);
  if (!serverId) {
    return new Response(
      JSON.stringify({ error: "Unknown sync peer. X-Sync-Server-Id header required from a registered peer." }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }
  return { serverId };
}
