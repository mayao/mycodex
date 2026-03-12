import { z } from "zod";

import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { deviceLogin } from "../../../../server/services/auth-service";

export const dynamic = "force-dynamic";

const deviceLoginSchema = z.object({
  device_id: z.string().min(8, "无效的设备标识"),
  device_label: z.string().optional(),
});

export async function POST(request: Request) {
  try {
    const body = deviceLoginSchema.parse(await request.json());
    const result = deviceLogin(body.device_id, body.device_label);
    return jsonOk(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "设备登录失败，请重试";
    return jsonSafeError({
      message,
      status: error instanceof z.ZodError ? 400 : 401,
      error,
      context: { route: "/api/auth/device-login", method: "POST" },
    });
  }
}
