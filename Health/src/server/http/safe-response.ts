import { NextResponse } from "next/server";

export function jsonOk(
  data: unknown,
  options?: { status?: number }
): NextResponse {
  return NextResponse.json(data, { status: options?.status ?? 200 });
}

export function jsonSafeError(
  input: string | { message: string; status?: number; error?: unknown; context?: Record<string, string> },
  status?: number
): NextResponse {
  if (typeof input === "string") {
    return NextResponse.json({ error: { message: input } }, { status: status ?? 500 });
  }

  const errorStatus = input.status ?? status ?? 500;

  if (input.error) {
    console.error("[safe-response]", input.context ?? {}, input.error);
  }

  return NextResponse.json(
    { error: { message: input.message } },
    { status: errorStatus }
  );
}
