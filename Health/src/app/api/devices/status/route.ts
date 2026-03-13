import { getAuthenticatedUserId } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getDeviceConnectionStatus, disconnectDevice, type DeviceProvider } from "../../../../server/services/device-auth-service";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    void userId; // device status is not user-scoped currently
    const devices = getDeviceConnectionStatus();
    return jsonOk({ devices });
  } catch (error) {
    return jsonSafeError({
      message: "获取设备状态失败",
      status: 500,
      error,
      context: { route: "/api/devices/status", method: "GET" },
    });
  }
}

export async function DELETE(request: Request) {
  try {
    const body = (await request.json()) as { provider?: string };
    const provider = body.provider as DeviceProvider;

    if (!provider) {
      return jsonSafeError({
        message: "缺少 provider 参数",
        status: 400,
        context: { route: "/api/devices/status", method: "DELETE" },
      });
    }

    disconnectDevice(provider);
    return jsonOk({ success: true, provider });
  } catch (error) {
    return jsonSafeError({
      message: "断开连接失败",
      status: 500,
      error,
      context: { route: "/api/devices/status", method: "DELETE" },
    });
  }
}
