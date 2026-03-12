import { syncWithAllPeers } from "./sync-service";

const SYNC_INTERVAL = 30_000; // 30 seconds
const STARTUP_DELAY = 10_000; // 10 seconds — wait for peer discovery

let schedulerInterval: ReturnType<typeof setInterval> | null = null;

export function startSyncScheduler(): void {
  if (schedulerInterval) return;

  console.log(`[Sync Scheduler] Starting (first sync in ${STARTUP_DELAY / 1000}s, then every ${SYNC_INTERVAL / 1000}s)`);

  setTimeout(() => {
    syncWithAllPeers().catch((err) => {
      console.error("[Sync Scheduler] Initial sync error:", err);
    });

    schedulerInterval = setInterval(() => {
      syncWithAllPeers().catch((err) => {
        console.error("[Sync Scheduler] Sync error:", err);
      });
    }, SYNC_INTERVAL);
  }, STARTUP_DELAY);
}

export function stopSyncScheduler(): void {
  if (schedulerInterval) {
    clearInterval(schedulerInterval);
    schedulerInterval = null;
  }
}
