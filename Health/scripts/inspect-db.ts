import path from "node:path";

import { getDatabase, databasePath } from "../src/server/db/sqlite";
import { getDashboardData } from "../src/server/services/dashboard-service";

const database = getDatabase();
const dashboard = getDashboardData(database);

console.log(`SQLite path: ${path.relative(process.cwd(), databasePath)}`);
console.log("Coverage:");
console.table(
  dashboard.coverage.map((item) => ({
    kind: item.kind,
    count: item.count,
    latest: item.latestRecordedAt?.slice(0, 10) ?? "--",
    status: item.status
  }))
);
console.log("KPIs:");
console.table(
  dashboard.kpis.map((item) => ({
    label: item.label,
    tone: item.tone,
    hasValue: item.value !== "--"
  }))
);
