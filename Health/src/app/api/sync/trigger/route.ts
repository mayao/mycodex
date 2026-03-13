import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { syncWithAllPeers, getSyncStatus } from "../../../../server/services/sync/sync-service";

export const dynamic = "force-dynamic";

/**
 * POST /api/sync/trigger
 * Manually trigger an immediate sync with all known peers.
 * Requires user authentication.
 */
export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    void userId; // sync trigger is server-level, auth just gates access
    await syncWithAllPeers();
    const status = getSyncStatus();
    return jsonOk({ triggered: true, ...status });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/sync/trigger", method: "POST" } });
    }
    return jsonSafeError({
      message: "Sync trigger failed",
      error,
      context: { route: "/api/sync/trigger", method: "POST" },
    });
  }
}
