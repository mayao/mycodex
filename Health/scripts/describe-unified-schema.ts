import { getDatabase } from "../src/server/db/sqlite";
import {
  describeUnifiedTables,
  getMetricRecordSamples,
  getUnifiedTableCounts
} from "../src/server/db/unified-health";

const database = getDatabase();

console.log("Unified table counts:");
console.table(getUnifiedTableCounts(database));

for (const table of describeUnifiedTables(database)) {
  console.log(`\n[${table.table}]`);
  console.table(
    table.columns.map((column) => ({
      column: column.name,
      type: column.type,
      required: column.notnull === 1,
      pk: column.pk === 1
    }))
  );
}

console.log("\nmetric_record samples:");
console.table(getMetricRecordSamples(database, 12));
