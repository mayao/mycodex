import { z } from "zod";

import { jsonOk, jsonSafeError } from "../../../../../server/http/safe-response";
import { signInWithApple } from "../../../../../server/services/auth-service";

export const dynamic = "force-dynamic";

const appleAuthSchema = z.object({
  identityToken: z.string().min(1).optional(),
  identity_token: z.string().min(1).optional(),
  authorizationCode: z.string().optional(),
  authorization_code: z.string().optional(),
  email: z.string().email().optional().or(z.literal("").transform(() => undefined)),
  displayName: z.string().optional(),
  display_name: z.string().optional(),
  deviceLabel: z.string().optional(),
  device_label: z.string().optional(),
}).refine((value) => value.identityToken || value.identity_token, {
  message: "缺少 Apple 身份令牌"
});

export async function POST(request: Request) {
  try {
    const body = appleAuthSchema.parse(await request.json());
    const result = await signInWithApple(
      {
        identityToken: body.identityToken || body.identity_token!,
        authorizationCode: body.authorizationCode || body.authorization_code,
        email: body.email,
        displayName: body.displayName || body.display_name
      },
      body.deviceLabel || body.device_label
    );
    return jsonOk(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Apple 登录失败，请重试";
    return jsonSafeError({
      message,
      status: 401,
      error,
      context: { route: "/api/auth/apple/sign-in", method: "POST" }
    });
  }
}
