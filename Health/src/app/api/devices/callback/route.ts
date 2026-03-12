import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import {
  exchangeCodeForTokens,
  type DeviceProvider,
} from "../../../../server/services/device-auth-service";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    const provider = url.searchParams.get("provider") as DeviceProvider | null;

    if (!code || !provider) {
      return new Response(
        `<html><body><h2>授权失败</h2><p>缺少必要参数。</p><script>
          if (window.opener) { window.opener.postMessage({type:'device-auth',success:false}, '*'); window.close(); }
        </script></body></html>`,
        { headers: { "Content-Type": "text/html; charset=utf-8" } }
      );
    }

    const callbackUrl = `${url.origin}/api/devices/callback`;
    const result = await exchangeCodeForTokens(provider, code, callbackUrl);

    if (result.success) {
      // Return HTML that will close the auth window and notify the app
      return new Response(
        `<html><body>
          <h2>✅ 授权成功</h2>
          <p>已成功连接，你可以关闭此窗口返回 APP。</p>
          <script>
            // For web-based flow
            if (window.opener) {
              window.opener.postMessage({type:'device-auth',success:true,provider:'${provider}'}, '*');
              setTimeout(() => window.close(), 1500);
            }
            // For iOS deep link callback
            setTimeout(() => {
              window.location.href = 'healthai://device-callback?provider=${provider}&success=true';
            }, 500);
          </script>
        </body></html>`,
        { headers: { "Content-Type": "text/html; charset=utf-8" } }
      );
    }

    return new Response(
      `<html><body>
        <h2>❌ 授权失败</h2>
        <p>${result.error ?? "未知错误"}</p>
        <script>
          if (window.opener) {
            window.opener.postMessage({type:'device-auth',success:false,error:'${(result.error ?? "").replace(/'/g, "\\'")}'}, '*');
          }
          setTimeout(() => {
            window.location.href = 'healthai://device-callback?provider=${provider}&success=false';
          }, 500);
        </script>
      </body></html>`,
      { headers: { "Content-Type": "text/html; charset=utf-8" } }
    );
  } catch (error) {
    return jsonSafeError({
      message: "设备回调处理失败",
      status: 500,
      error,
      context: { route: "/api/devices/callback", method: "GET" },
    });
  }
}
