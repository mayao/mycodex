import { z } from "zod";

import { getAuthenticatedUserId, AuthError } from "../../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../../server/http/safe-response";
import { linkAppleIdentity } from "../../../../../server/services/auth-service";

export const dynamic = "force-dynamic";

const appleLinkSchema = z.object({
  identityToken: z.string().min(1).optional(),
  identity_token: z.string().min(1).optional(),
  authorizationCode: z.string().optional(),
  authorization_code: z.string().optional(),
  email: z.string().email().optional().or(z.literal("").transform(() => undefined)),
  displayName: z.string().optional(),
  display_name: z.string().optional(),
}).refine((value) => value.identityToken || value.identity_token, {
  message: "缺少 Apple 身份令牌"
});

export async function POST(request: Request) {
  try {
    const currentUserId = getAuthenticatedUserId(request);
    const body = appleLinkSchema.parse(await request.json());
    const result = await linkAppleIdentity(currentUserId, {
      identityToken: body.identityToken || body.identity_token!,
      authorizationCode: body.authorizationCode || body.authorization_code,
      email: body.email,
      displayName: body.displayName || body.display_name
    });
    return jsonOk(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Apple 账号绑定失败，请重试";
    return jsonSafeError({
      message,
      status: error instanceof AuthError ? 401 : 400,
      error,
      context: { route: "/api/auth/apple/link", method: "POST" }
    });
  }
}
