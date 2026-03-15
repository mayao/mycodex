import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getDatabase } from "../../../../server/db/sqlite";
import { listGeneticFindingDigests } from "../../../../server/repositories/document-insight-repository";
import { generateGeneticsInsight } from "../../../../server/services/document-insight-llm-service";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const database = getDatabase();
    const findings = listGeneticFindingDigests(database, userId);

    if (findings.length === 0) {
      return jsonOk({ available: false });
    }

    const insight = await generateGeneticsInsight(findings);
    return jsonOk({ available: true, insight });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/insights/genetics" } });
    }
    return jsonSafeError({
      message: "基因报告洞察分析暂时不可用，请稍后重试。",
      status: 500,
      error,
      context: { route: "/api/insights/genetics" }
    });
  }
}
