import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { syncWithAllPeers, getSyncStatus } from "../../../../server/services/sync/sync-service";

export const dynamic = "force-dynamic";

/**
 * POST /api/sync/trigger
 * Manually trigger an immediate sync with all known peers.
 */
export async function POST() {
  try {
    await syncWithAllPeers();
    const status = getSyncStatus();
    return jsonOk({ triggered: true, ...status });
  } catch (error) {
    return jsonSafeError({
      message: "Sync trigger failed",
      error,
      context: { route: "/api/sync/trigger", method: "POST" },
    });
  }
}
