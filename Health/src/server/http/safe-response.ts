import { randomUUID } from "node:crypto";

import { NextResponse } from "next/server";

import { logServerError } from "../privacy/safe-logger";

export function jsonOk(payload: unknown, init?: ResponseInit) {
  return NextResponse.json(payload, init);
}

interface JsonSafeErrorOptions {
  message?: string;
  status?: number;
  error?: unknown;
  context?: Record<string, unknown>;
}

export function jsonSafeError(message?: string, status?: number): NextResponse;
export function jsonSafeError(options: JsonSafeErrorOptions): NextResponse;
export function jsonSafeError(
  messageOrOptions: string | JsonSafeErrorOptions = "请求暂时无法完成，请稍后重试。",
  status = 500
) {
  const options =
    typeof messageOrOptions === "string"
      ? {
          message: messageOrOptions,
          status
        }
      : messageOrOptions;
  const errorId = randomUUID();

  if (options.error || options.context) {
    logServerError({
      errorId,
      publicMessage: options.message ?? "请求暂时无法完成，请稍后重试。",
      error: options.error,
      context: options.context
    });
  }

  return NextResponse.json(
    {
      error: {
        id: errorId,
        message: options.message ?? "请求暂时无法完成，请稍后重试。"
      }
    },
    { status: options.status ?? 500 }
  );
}
