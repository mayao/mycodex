import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getSyncStatus } from "../../../../server/services/sync/sync-service";

export const dynamic = "force-dynamic";

/**
 * GET /api/sync/status
 * Returns current sync state: server_id, known peers, recent sync logs.
 */
export async function GET() {
  try {
    return jsonOk(getSyncStatus());
  } catch (error) {
    return jsonSafeError({
      message: "Failed to get sync status",
      error,
      context: { route: "/api/sync/status", method: "GET" },
    });
  }
}
