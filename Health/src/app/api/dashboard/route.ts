import { getAuthenticatedUserId, AuthError } from "../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../server/http/safe-response";
import { getHealthHomePageData } from "../../../server/services/health-home-service";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    return jsonOk(await getHealthHomePageData(undefined, userId));
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/dashboard", method: "GET" } });
    }
    return jsonSafeError({
      message: "首页健康数据暂时不可用。",
      error,
      context: { route: "/api/dashboard", method: "GET" }
    });
  }
}
