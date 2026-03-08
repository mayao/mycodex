import { getDatabase } from "../src/server/db/sqlite";
import {
  listAppliedMigrations,
  runPendingMigrations
} from "../src/server/db/migration-runner";
import { describeUnifiedTables, getUnifiedTableCounts } from "../src/server/db/unified-health";

const database = getDatabase();
const applied = runPendingMigrations(database);

console.log(`Applied migrations: ${applied.length > 0 ? applied.join(", ") : "none"}`);
console.log(`Current migration state: ${listAppliedMigrations(database).join(", ")}`);
console.table(getUnifiedTableCounts(database));

for (const table of describeUnifiedTables(database)) {
  console.log(`\n[${table.table}]`);
  console.table(
    table.columns.map((column) => ({
      name: column.name,
      type: column.type,
      required: column.notnull === 1,
      primaryKey: column.pk === 1,
      defaultValue: column.dflt_value ?? ""
    }))
  );
}
