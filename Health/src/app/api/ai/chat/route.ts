import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import {
  healthAIChatRequestSchema,
  replyWithHealthAI
} from "../../../../server/services/ai-chat-service";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const payload = healthAIChatRequestSchema.parse(await request.json());
    return jsonOk(await replyWithHealthAI(payload, userId));
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/ai/chat", method: "POST" } });
    }
    return jsonSafeError({
      message: "AI 对话暂时不可用，请稍后重试。",
      status: 400,
      error,
      context: { route: "/api/ai/chat", method: "POST" }
    });
  }
}
