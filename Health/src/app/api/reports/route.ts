import { jsonOk, jsonSafeError } from "../../../server/http/safe-response";
import { getReportsIndexData } from "../../../server/services/report-service";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    return jsonOk(await getReportsIndexData());
  } catch (error) {
    return jsonSafeError({
      message: "报告列表暂时不可用。",
      error,
      context: {
        route: "/api/reports",
        method: "GET"
      }
    });
  }
}
