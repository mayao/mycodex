import { z } from "zod";

import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { requestVerificationCode } from "../../../../server/services/auth-service";

export const dynamic = "force-dynamic";

const phoneRegex = /^1[3-9]\d{9}$/;

const requestCodeSchema = z.object({
  phoneNumber: z.string().regex(phoneRegex, "请输入有效的手机号码").optional(),
  phone_number: z.string().regex(phoneRegex, "请输入有效的手机号码").optional(),
}).refine(d => d.phoneNumber || d.phone_number, { message: "请输入有效的手机号码" });

export async function POST(request: Request) {
  try {
    const body = requestCodeSchema.parse(await request.json());
    const phoneNumber = (body.phoneNumber || body.phone_number)!;
    const result = requestVerificationCode(phoneNumber);
    return jsonOk({
      message: "验证码已发送",
      expires_in_seconds: result.expiresInSeconds,
      // Return code directly until real SMS service is integrated
      code: result.code,
    });
  } catch (error) {
    return jsonSafeError({
      message: error instanceof z.ZodError ? "请输入有效的手机号码" : "发送验证码失败，请稍后重试",
      status: 400,
      error,
      context: { route: "/api/auth/request-code", method: "POST" },
    });
  }
}
