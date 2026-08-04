import { getAppEnv } from "../config/env";
import { validateToken, AuthError } from "../services/auth-service";

export { AuthError };

const SESSION_COOKIE = "health-auth-token";

/**
 * Extract authenticated user ID from request.
 * When HEALTH_AUTH_ENABLED is false, returns "user-self" for backward compatibility.
 * Checks Authorization header first, then falls back to the session cookie.
 */
export function getAuthenticatedUserId(request: Request): string {
  const env = getAppEnv();

  if (!env.HEALTH_AUTH_ENABLED) {
    return "user-self";
  }

  const token = extractBearerToken(request) ?? extractCookieToken(request);
  if (!token) {
    throw new AuthError("请先登录");
  }

  return validateToken(token);
}

export function extractBearerToken(request: Request): string | null {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;
  return authHeader.slice(7);
}

function extractCookieToken(request: Request): string | null {
  const cookieHeader = request.headers.get("cookie");
  if (!cookieHeader) return null;
  const match = cookieHeader.match(new RegExp(`(?:^|;\\s*)${SESSION_COOKIE}=([^;]+)`));
  return match?.[1] ?? null;
}
