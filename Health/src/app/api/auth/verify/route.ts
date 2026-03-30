import { z } from "zod";

import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { extractBearerToken } from "../../../../server/http/auth-middleware";
import { validateToken, verifyCodeAndLogin, AuthError } from "../../../../server/services/auth-service";

export const dynamic = "force-dynamic";

const phoneRegex = /^1[3-9]\d{9}$/;

const verifySchema = z.object({
  phoneNumber: z.string().regex(phoneRegex).optional(),
  phone_number: z.string().regex(phoneRegex).optional(),
  code: z.string().length(6),
  deviceLabel: z.string().optional(),
  device_label: z.string().optional(),
}).refine(d => d.phoneNumber || d.phone_number, { message: "请输入有效的手机号码" });

export async function POST(request: Request) {
  try {
    const body = verifySchema.parse(await request.json());
    const phoneNumber = (body.phoneNumber || body.phone_number)!;
    const deviceLabel = body.deviceLabel || body.device_label;
    const bearerToken = extractBearerToken(request);
    const preferredUserId = bearerToken ? validateToken(bearerToken) : undefined;
    const result = verifyCodeAndLogin(phoneNumber, body.code, deviceLabel, preferredUserId);
    return jsonOk(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "验证失败，请重试";
    return jsonSafeError({
      message,
      status: error instanceof AuthError ? 401 : 401,
      error,
      context: { route: "/api/auth/verify", method: "POST" },
    });
  }
}
