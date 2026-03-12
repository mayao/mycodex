import { createSocket } from "node:dgram";
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
        // Calculate subnet broadcast address from IP + netmask
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

export function startUDPBroadcast(httpPort: number = 3000): void {
  if (intervalId) return;

  const socket = createSocket({ type: "udp4", reuseAddr: true });

  socket.bind(() => {
    socket.setBroadcast(true);

    const net = getLocalNetwork();

    const broadcast = () => {
      const message = JSON.stringify({
        service: "vital-command",
        name: os.hostname(),
        ip: net.address,
        port: httpPort,
        version: "1.0.0",
      });

      const buf = Buffer.from(message);
      // Broadcast to subnet broadcast address (e.g. 10.8.143.255)
      socket.send(
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

  socket.on("error", (err) => {
    console.error("[UDP Broadcast] Socket error:", err.message);
  });
}

export function stopUDPBroadcast(): void {
  if (intervalId) {
    clearInterval(intervalId);
    intervalId = null;
  }
}
