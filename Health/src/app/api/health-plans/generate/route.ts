import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { generateSuggestions } from "../../../../server/services/health-plan-service";

export const dynamic = "force-dynamic";

/**
 * POST /api/health-plans/generate — Generate new AI suggestions
 */
export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const result = await generateSuggestions(userId);
    return jsonOk({ batch_id: result.batchId, suggestions: result.suggestions });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/health-plans/generate", method: "POST" } });
    }
    const message = error instanceof Error ? error.message : "建议生成失败";
    return jsonSafeError({
      message,
      status: error instanceof Error && error.message.includes("频率限制") ? 429 : 500,
      error,
      context: { route: "/api/health-plans/generate", method: "POST" }
    });
  }
}
