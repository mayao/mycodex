import os from "node:os";
import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

function getLocalIPv4(): string {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name] ?? []) {
      if (iface.family === "IPv4" && !iface.internal) {
        return iface.address;
      }
    }
  }
  return "0.0.0.0";
}

export async function GET() {
  return NextResponse.json({
    service: "vital-command",
    name: os.hostname(),
    ip: getLocalIPv4(),
    port: Number(process.env.PORT ?? 3000),
    version: "1.0.0",
  });
}
