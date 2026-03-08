import { jsonOk, jsonSafeError } from "../../../server/http/safe-response";
import { getHealthHomePageData } from "../../../server/services/health-home-service";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    return jsonOk(await getHealthHomePageData());
  } catch (error) {
    return jsonSafeError({
      message: "首页健康数据暂时不可用。",
      error,
      context: {
        route: "/api/dashboard",
        method: "GET"
      }
    });
  }
}
