import { cookies } from "next/headers";

import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { extractBearerToken } from "../../../../server/http/auth-middleware";
import { logout } from "../../../../server/services/auth-service";

export const dynamic = "force-dynamic";

const SESSION_COOKIE = "health-auth-token";

export async function POST(request: Request) {
  try {
    const jar = await cookies();
    const bearerToken = extractBearerToken(request);
    const cookieToken = jar.get(SESSION_COOKIE)?.value;
    const token = bearerToken ?? cookieToken;
    if (token) {
      logout(token);
    }
    jar.delete(SESSION_COOKIE);
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
