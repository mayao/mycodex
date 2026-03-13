import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { requireSyncPeer } from "../../../../server/http/sync-auth";
import { applyChanges } from "../../../../server/services/sync/sync-service";

export const dynamic = "force-dynamic";

/**
 * POST /api/sync/apply
 * Receive and apply changes from a peer server.
 * Body: { server_id: string, changes: { table_name: Row[] } }
 * Requires X-Sync-Server-Id header from a registered peer.
 */
export async function POST(request: Request) {
  try {
    const auth = requireSyncPeer(request);
    if (auth instanceof Response) return auth;

    const body = (await request.json()) as {
      server_id?: string;
      changes?: Record<string, Record<string, unknown>[]>;
    };

    if (!body.server_id || !body.changes) {
      return jsonSafeError({ message: "Missing server_id or changes", status: 400 });
    }

    const result = applyChanges(body.changes, body.server_id);
    return jsonOk(result);
  } catch (error) {
    return jsonSafeError({
      message: "Failed to apply sync changes",
      error,
      context: { route: "/api/sync/apply", method: "POST" },
    });
  }
}
