import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getSuggestedQuestions } from "../../../../server/services/ai-chat-service";
import { getDatabase } from "../../../../server/db/sqlite";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    return jsonOk(await getSuggestedQuestions(userId, getDatabase()));
  } catch (error) {
    if (error instanceof AuthError) return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/ai/suggested-questions" } });
    return jsonSafeError({ message: "获取建议问题失败", status: 500, error, context: { route: "/api/ai/suggested-questions" } });
  }
}
