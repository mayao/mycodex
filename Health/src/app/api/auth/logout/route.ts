import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { extractBearerToken } from "../../../../server/http/auth-middleware";
import { logout } from "../../../../server/services/auth-service";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const token = extractBearerToken(request);
    if (token) {
      logout(token);
    }
    return jsonOk({ success: true });
  } catch (error) {
    return jsonSafeError({
      message: "登出失败",
      status: 500,
      error,
      context: { route: "/api/auth/logout", method: "POST" },
    });
  }
}
