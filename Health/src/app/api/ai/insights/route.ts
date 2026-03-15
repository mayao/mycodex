import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import {
  getMedicalExamInsights,
  getGeneticInsights
} from "../../../../server/services/document-insight-ai-service";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const { searchParams } = new URL(request.url);
    const type = searchParams.get("type");

    if (type === "medical_exam") {
      return jsonOk(await getMedicalExamInsights(userId));
    }

    if (type === "genetic") {
      return jsonOk(await getGeneticInsights(userId));
    }

    return jsonSafeError({
      message: "type 参数必须为 medical_exam 或 genetic",
      status: 400,
      error: new Error("invalid type"),
      context: { route: "/api/ai/insights", method: "GET" }
    });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({
        message: error.message,
        status: 401,
        error,
        context: { route: "/api/ai/insights", method: "GET" }
      });
    }
    return jsonSafeError({
      message: "AI 洞察分析暂时不可用，请稍后重试。",
      status: 500,
      error,
      context: { route: "/api/ai/insights", method: "GET" }
    });
  }
}
