import { getAppEnv } from "../config/env";
import { classifySensitiveHeader, formatRedactionLabel } from "./sensitive-fields";

function sanitizeString(value: string): string {
  return value
    .replace(/(Bearer\s+)[A-Za-z0-9._-]+/gi, "$1[REDACTED]")
    .replace(/(api[_-]?key["'\s:=]+)[^\s"',}]+/gi, "$1[REDACTED]");
}

function sanitizeValue(value: unknown): unknown {
  if (value === null || value === undefined) {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map((item) => sanitizeValue(item));
  }

  if (typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => {
        const category = classifySensitiveHeader(key);

        return [key, category ? formatRedactionLabel(category) : sanitizeValue(item)];
      })
    );
  }

  if (typeof value === "string") {
    return sanitizeString(value);
  }

  return value;
}

interface SafeErrorLogInput {
  errorId: string;
  publicMessage: string;
  error?: unknown;
  context?: Record<string, unknown>;
}

export function logServerError(input: SafeErrorLogInput): void {
  const env = getAppEnv();

  if (env.HEALTH_LOG_LEVEL === "silent") {
    return;
  }

  console.error("[safe-error]", {
    errorId: input.errorId,
    publicMessage: input.publicMessage,
    errorName: input.error instanceof Error ? input.error.name : "UnknownError",
    context: sanitizeValue(input.context ?? {}),
    occurredAt: new Date().toISOString()
  });
}
