import { ZodError } from "zod";

import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { buildPrivacyExportPlaceholder } from "../../../../server/privacy/privacy-service";

export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const body = await request.json().catch(() => ({}));
    return jsonOk(buildPrivacyExportPlaceholder(body, undefined, userId), { status: 501 });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/privacy/export", method: "POST" } });
    }
    return jsonSafeError({
      message: error instanceof ZodError ? "隐私导出请求参数无效。" : "隐私导出能力暂时不可用。",
      status: error instanceof ZodError ? 400 : 500,
      error,
      context: { route: "/api/privacy/export", method: "POST" }
    });
  }
}
