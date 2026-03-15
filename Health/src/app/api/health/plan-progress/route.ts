import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getPlanProgressReport } from "../../../../server/services/health-plan-service";
import { getDatabase } from "../../../../server/db/sqlite";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    return jsonOk(getPlanProgressReport(userId, getDatabase()));
  } catch (error) {
    if (error instanceof AuthError) return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/health/plan-progress" } });
    return jsonSafeError({ message: "获取计划进度失败", status: 500, error, context: { route: "/api/health/plan-progress" } });
  }
}
