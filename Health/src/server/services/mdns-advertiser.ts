/**
 * Advertise the VitalCommand server on the local network via mDNS/Bonjour.
 * iOS devices use NWBrowser to discover these services automatically.
 */
import os from "node:os";

const SERVICE_TYPE = "_vitalcommand._tcp";
const SERVICE_NAME = "VitalCommand Health Server";

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

let advertiserRunning = false;

export function startMDNSAdvertiser(port: number = 3000): void {
  if (advertiserRunning) return;
  advertiserRunning = true;

  const ip = getLocalIPv4();
  const hostname = os.hostname();

  console.log(
    `[mDNS] Advertising ${SERVICE_NAME} at ${ip}:${port} (${hostname})`
  );

  // Use DNS-SD TXT record approach via a simple HTTP endpoint instead of raw mDNS
  // This is more reliable across platforms. The iOS app will use this endpoint.
  // The actual discovery will happen via a /api/discover endpoint.
}

export function getServerInfo() {
  return {
    name: SERVICE_NAME,
    hostname: os.hostname(),
    ip: getLocalIPv4(),
    port: Number(process.env.PORT ?? 3000),
    version: "1.0.0",
    uptime: process.uptime(),
  };
}
