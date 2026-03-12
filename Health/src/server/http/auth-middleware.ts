import { getAppEnv } from "../config/env";
import { validateToken, AuthError } from "../services/auth-service";

export { AuthError };

/**
 * Extract authenticated user ID from request.
 * When HEALTH_AUTH_ENABLED is false, returns "user-self" for backward compatibility.
 */
export function getAuthenticatedUserId(request: Request): string {
  const env = getAppEnv();

  if (!env.HEALTH_AUTH_ENABLED) {
    return "user-self";
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    throw new AuthError("请先登录");
  }

  const token = authHeader.slice(7);
  return validateToken(token);
}

/**
 * Extract Bearer token from request (for logout etc).
 */
export function extractBearerToken(request: Request): string | null {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;
  return authHeader.slice(7);
}
