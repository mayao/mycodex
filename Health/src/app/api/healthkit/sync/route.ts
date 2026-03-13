import { revalidatePath } from "next/cache";

import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import {
  syncHealthKitSamples,
  type HealthKitSyncRequestPayload
} from "../../../../server/services/healthkit-sync-service";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const payload = (await request.json()) as HealthKitSyncRequestPayload;
    const result = syncHealthKitSamples(payload, undefined, userId);

    revalidatePath("/", "layout");
    revalidatePath("/data", "page");
    revalidatePath("/reports", "page");

    return jsonOk({ result });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/healthkit/sync", method: "POST" } });
    }
    return jsonSafeError({
      message: "Apple 健康同步失败，请稍后重试。",
      status: 400,
      error
    });
  }
}
