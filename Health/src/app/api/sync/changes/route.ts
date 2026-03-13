import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { requireSyncPeer } from "../../../../server/http/sync-auth";
import { getChangesSince } from "../../../../server/services/sync/sync-service";

export const dynamic = "force-dynamic";

/**
 * GET /api/sync/changes?since=<ISO timestamp>&tables=<comma-separated>
 * Returns changes since the given timestamp for server-to-server sync.
 * Requires X-Sync-Server-Id header from a registered peer.
 */
export async function GET(request: Request) {
  try {
    const auth = requireSyncPeer(request);
    if (auth instanceof Response) return auth;

    const url = new URL(request.url);
    const since = url.searchParams.get("since") ?? "1970-01-01T00:00:00.000Z";
    const tablesParam = url.searchParams.get("tables");
    const tableFilter = tablesParam ? tablesParam.split(",").map((t) => t.trim()) : undefined;

    const result = getChangesSince(since, tableFilter);
    return jsonOk(result);
  } catch (error) {
    return jsonSafeError({
      message: "Failed to retrieve sync changes",
      error,
      context: { route: "/api/sync/changes", method: "GET" },
    });
  }
}
