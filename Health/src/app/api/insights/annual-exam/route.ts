import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getDatabase } from "../../../../server/db/sqlite";
import { getAnnualExamDigest } from "../../../../server/repositories/document-insight-repository";
import { generateAnnualExamInsight } from "../../../../server/services/document-insight-llm-service";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const database = getDatabase();
    const digest = getAnnualExamDigest(database, userId);

    if (!digest) {
      return jsonOk({ available: false });
    }

    const insight = await generateAnnualExamInsight(digest);
    return jsonOk({ available: true, insight });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/insights/annual-exam" } });
    }
    return jsonSafeError({
      message: "体检报告洞察分析暂时不可用，请稍后重试。",
      status: 500,
      error,
      context: { route: "/api/insights/annual-exam" }
    });
  }
}
