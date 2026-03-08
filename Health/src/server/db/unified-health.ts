import type { DatabaseSync } from "node:sqlite";

import { unifiedTables } from "./migration-runner";

interface TableInfoRow {
  cid: number;
  name: string;
  type: string;
  notnull: number;
  dflt_value: string | null;
  pk: number;
}

interface SampleMetricRecordRow {
  sample_time: string;
  metric_code: string;
  metric_name: string;
  category: string;
  abnormal_flag: string;
  source_type: string;
}

export function describeUnifiedTables(database: DatabaseSync) {
  return unifiedTables.map((table) => ({
    table,
    columns: database
      .prepare(`PRAGMA table_info(${table})`)
      .all() as unknown as TableInfoRow[]
  }));
}

export function getUnifiedTableCounts(database: DatabaseSync) {
  return unifiedTables.map((table) => {
    const row = database
      .prepare(`SELECT COUNT(*) AS count FROM ${table}`)
      .get() as { count: number };

    return {
      table,
      count: row.count
    };
  });
}

export function getMetricRecordSamples(
  database: DatabaseSync,
  limit = 8
): SampleMetricRecordRow[] {
  return database
    .prepare(
      `
      SELECT
        sample_time,
        metric_code,
        metric_name,
        category,
        abnormal_flag,
        source_type
      FROM metric_record
      ORDER BY sample_time DESC, metric_code ASC
      LIMIT ?
    `
    )
    .all(limit) as unknown as SampleMetricRecordRow[];
}
