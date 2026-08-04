import { cookies } from "next/headers";
import { z } from "zod";

import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { extractBearerToken } from "../../../../server/http/auth-middleware";
import { logout, validateToken } from "../../../../server/services/auth-service";

export const dynamic = "force-dynamic";

const SESSION_COOKIE = "health-auth-token";
const SESSION_MAX_AGE = 30 * 24 * 60 * 60; // 30 days

const setSessionSchema = z.object({
  token: z.string().min(1),
});

export async function POST(request: Request) {
  try {
    const body = setSessionSchema.parse(await request.json());
    validateToken(body.token);

    const jar = await cookies();
    jar.set(SESSION_COOKIE, body.token, {
      httpOnly: true,
      sameSite: "lax",
      path: "/",
      maxAge: SESSION_MAX_AGE,
      secure: process.env.NODE_ENV === "production",
    });

    return jsonOk({ success: true });
  } catch (error) {
    return jsonSafeError({
      message: error instanceof Error ? error.message : "登录失败",
      status: 401,
      error,
      context: { route: "/api/auth/session", method: "POST" },
    });
  }
}

export async function DELETE(request: Request) {
  try {
    const token = extractBearerToken(request);
    const jar = await cookies();
    const cookieToken = jar.get(SESSION_COOKIE)?.value;

    const tokenToRevoke = token ?? cookieToken;
    if (tokenToRevoke) {
      logout(tokenToRevoke);
    }

    jar.delete(SESSION_COOKIE);
    return jsonOk({ success: true });
  } catch (error) {
    return jsonSafeError({
      message: "登出失败",
      status: 500,
      error,
      context: { route: "/api/auth/session", method: "DELETE" },
    });
  }
}
