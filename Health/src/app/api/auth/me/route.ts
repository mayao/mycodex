import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { getUserInfo } from "../../../../server/services/auth-service";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const user = getUserInfo(userId);
    if (!user) {
      return jsonSafeError({
        message: "用户不存在",
        status: 404,
        context: { route: "/api/auth/me", method: "GET" },
      });
    }
    return jsonOk({ user });
  } catch (error) {
    return jsonSafeError({
      message: error instanceof AuthError ? error.message : "获取用户信息失败",
      status: error instanceof AuthError ? 401 : 500,
      error,
      context: { route: "/api/auth/me", method: "GET" },
    });
  }
}
