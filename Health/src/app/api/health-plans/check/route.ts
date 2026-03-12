import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { checkPlanCompletion } from "../../../../server/services/health-plan-service";

export const dynamic = "force-dynamic";

/**
 * POST /api/health-plans/check — Trigger auto-completion check for today
 */
export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const checks = checkPlanCompletion(userId);
    return jsonOk({ checks });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/health-plans/check", method: "POST" } });
    }
    return jsonSafeError({
      message: "完成检查失败",
      error,
      context: { route: "/api/health-plans/check", method: "POST" }
    });
  }
}
