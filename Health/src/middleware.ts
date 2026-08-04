import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

const SESSION_COOKIE = "health-auth-token";

const PUBLIC_PATHS = [
  "/login",
  "/share",
  "/api/auth/request-code",
  "/api/auth/verify",
  "/api/auth/session",
  "/api/auth/device-login",
  "/api/auth/apple",
];

function isPublicPath(pathname: string): boolean {
  return PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"));
}

export function middleware(request: NextRequest) {
  const authEnabled = process.env.HEALTH_AUTH_ENABLED === "true" || process.env.HEALTH_AUTH_ENABLED === "1";

  if (!authEnabled) {
    return NextResponse.next();
  }

  const { pathname } = request.nextUrl;

  if (isPublicPath(pathname)) {
    return NextResponse.next();
  }

  const token = request.cookies.get(SESSION_COOKIE)?.value;
  if (!token) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/login";
    loginUrl.search = "";
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico).*)",
  ],
};
