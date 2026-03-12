export async function register() {
  // Only run on the server (not edge runtime)
  if (process.env.NEXT_RUNTIME === "nodejs") {
    const { startUDPBroadcast } = await import(
      "./server/services/udp-broadcast"
    );
    const port = Number(process.env.PORT ?? 3000);
    startUDPBroadcast(port);
  }
}
