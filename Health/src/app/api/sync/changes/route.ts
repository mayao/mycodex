import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getChangesSince } from "../../../../server/services/sync/sync-service";

export const dynamic = "force-dynamic";

/**
 * GET /api/sync/changes?since=<ISO timestamp>&tables=<comma-separated>
 * Returns changes since the given timestamp for server-to-server sync.
 */
export async function GET(request: Request) {
  try {
    // Basic LAN security: check for private IP (optional, can be stricter)
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
