import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getSyncStatus } from "../../../../server/services/sync/sync-service";

export const dynamic = "force-dynamic";

/**
 * GET /api/sync/status
 * Returns current sync state: server_id, known peers, recent sync logs.
 * Requires user authentication.
 */
export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    void userId; // sync status is server-level, auth just gates access
    return jsonOk(getSyncStatus());
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/sync/status", method: "GET" } });
    }
    return jsonSafeError({
      message: "Failed to get sync status",
      error,
      context: { route: "/api/sync/status", method: "GET" },
    });
  }
}
