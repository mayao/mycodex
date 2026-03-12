import { getAuthenticatedUserId, AuthError } from "../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../server/http/safe-response";
import { getReportsIndexData } from "../../../server/services/report-service";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const _userId = getAuthenticatedUserId(request);
    return jsonOk(await getReportsIndexData());
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/reports", method: "GET" } });
    }
    return jsonSafeError({
      message: "报告列表暂时不可用。",
      error,
      context: { route: "/api/reports", method: "GET" }
    });
  }
}
