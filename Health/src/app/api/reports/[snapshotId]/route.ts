import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getReportSnapshotDetail } from "../../../../server/services/report-service";

export const dynamic = "force-dynamic";

export async function GET(
  request: Request,
  context: { params: Promise<{ snapshotId: string }> }
) {
  try {
    const userId = getAuthenticatedUserId(request);
    const { snapshotId } = await context.params;
    const report = await getReportSnapshotDetail(decodeURIComponent(snapshotId), undefined, userId);

    if (!report) {
      return jsonSafeError("未找到对应报告。", 404);
    }

    return jsonOk(report);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/reports/[snapshotId]", method: "GET" } });
    }
    return jsonSafeError({
      message: "报告详情暂时不可用。",
      error,
      context: { route: "/api/reports/[snapshotId]", method: "GET" }
    });
  }
}
