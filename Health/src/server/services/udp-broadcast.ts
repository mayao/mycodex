import { createSocket, type Socket } from "node:dgram";
import os from "node:os";

const BROADCAST_PORT = 41234;
const BROADCAST_INTERVAL = 5000;

interface LocalNet {
  address: string;
  netmask: string;
  broadcast: string;
}

function getLocalNetwork(): LocalNet {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name] ?? []) {
      if (iface.family === "IPv4" && !iface.internal) {
        const ipParts = iface.address.split(".").map(Number);
        const maskParts = iface.netmask.split(".").map(Number);
        const broadcastParts = ipParts.map(
          (ip, i) => (ip | (~maskParts[i] & 0xff))
        );
        return {
          address: iface.address,
          netmask: iface.netmask,
          broadcast: broadcastParts.join("."),
        };
      }
    }
  }
  return { address: "0.0.0.0", netmask: "255.255.255.0", broadcast: "255.255.255.255" };
}

let intervalId: ReturnType<typeof setInterval> | null = null;
let listenerSocket: Socket | null = null;

// Injected dependencies — set by startUDPBroadcast caller
let _getServerId: (() => string) | null = null;
let _onPeerDiscovered: ((serverId: string, name: string, ip: string, port: number) => void) | null = null;

export interface UDPBroadcastOptions {
  httpPort?: number;
  getServerId?: () => string;
  onPeerDiscovered?: (serverId: string, name: string, ip: string, port: number) => void;
}

export function startUDPBroadcast(options: UDPBroadcastOptions = {}): void {
  if (intervalId) return;

  const httpPort = options.httpPort ?? 3000;
  _getServerId = options.getServerId ?? null;
  _onPeerDiscovered = options.onPeerDiscovered ?? null;

  const localServerId = _getServerId?.() ?? "unknown";

  // --- Sender socket ---
  const senderSocket = createSocket({ type: "udp4", reuseAddr: true });

  senderSocket.bind(() => {
    senderSocket.setBroadcast(true);

    const net = getLocalNetwork();

    const broadcast = () => {
      const message = JSON.stringify({
        service: "vital-command",
        name: os.hostname(),
        ip: net.address,
        port: httpPort,
        version: "1.0.0",
        server_id: _getServerId?.() ?? localServerId,
      });

      const buf = Buffer.from(message);
      senderSocket.send(
        buf,
        0,
        buf.length,
        BROADCAST_PORT,
        net.broadcast,
        (err) => {
          if (err) {
            const code = (err as NodeJS.ErrnoException).code;
            if (code !== "ENETUNREACH" && code !== "EHOSTUNREACH" && code !== "EADDRNOTAVAIL") {
              console.error("[UDP Broadcast] Error:", err.message);
            }
          }
        }
      );
    };

    broadcast();
    intervalId = setInterval(broadcast, BROADCAST_INTERVAL);
    console.log(
      `[UDP Broadcast] Broadcasting on port ${BROADCAST_PORT} every ${BROADCAST_INTERVAL / 1000}s`
    );
  });

  senderSocket.on("error", (err) => {
    console.error("[UDP Broadcast] Sender socket error:", err.message);
  });

  // --- Listener socket (for peer discovery) ---
  listenerSocket = createSocket({ type: "udp4", reuseAddr: true });

  listenerSocket.on("message", (msg, rinfo) => {
    try {
      const data = JSON.parse(msg.toString());
      const currentServerId = _getServerId?.() ?? localServerId;
      if (
        data.service === "vital-command" &&
        data.server_id &&
        data.server_id !== currentServerId
      ) {
        _onPeerDiscovered?.(
          data.server_id,
          data.name ?? rinfo.address,
          data.ip ?? rinfo.address,
          data.port ?? 3000
        );
      }
    } catch {
      // Ignore malformed messages
    }
  });

  listenerSocket.on("error", (err) => {
    console.error("[UDP Listener] Error:", err.message);
  });

  listenerSocket.bind(BROADCAST_PORT, () => {
    console.log(`[UDP Listener] Listening for peer broadcasts on port ${BROADCAST_PORT}`);
  });
}

export function stopUDPBroadcast(): void {
  if (intervalId) {
    clearInterval(intervalId);
    intervalId = null;
  }
  if (listenerSocket) {
    listenerSocket.close();
    listenerSocket = null;
  }
}
