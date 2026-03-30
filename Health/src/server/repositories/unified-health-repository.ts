import type { DatabaseSync } from "node:sqlite";

import type { ReportKind } from "../domain/health-hub";

export interface UnifiedMetricRecordRow {
  id: string;
  metricCode: string;
  metricName: string;
  category: string;
  normalizedValue: number;
  unit: string;
  abnormalFlag: string;
  sampleTime: string;
  referenceRange: string | null;
}

export interface UnifiedTrendPoint {
  date: string;
  [key: string]: number | string | undefined;
}

export interface UnifiedReportSnapshotRow {
  id: string;
  report_type: string;
  period_start: string;
  period_end: string;
  summary_json: string;
  source_type: string;
  created_at: string;
  notes: string | null;
}

function sortBySampleTime<T extends { sampleTime: string }>(rows: T[]): T[] {
  return [...rows].sort((left, right) => left.sampleTime.localeCompare(right.sampleTime));
}

export function getUnifiedMetricRecords(
  database: DatabaseSync,
  userId: string,
  metricCodes?: string[],
  asOf?: string
): UnifiedMetricRecordRow[] {
  if (metricCodes && metricCodes.length > 0) {
    const placeholders = metricCodes.map(() => "?").join(", ");

    if (asOf) {
      return database
        .prepare(
          `
          SELECT
            id,
            metric_code AS metricCode,
            metric_name AS metricName,
            category,
            normalized_value AS normalizedValue,
            unit,
            abnormal_flag AS abnormalFlag,
            sample_time AS sampleTime,
            reference_range AS referenceRange
          FROM metric_record
          WHERE user_id = ? AND metric_code IN (${placeholders}) AND sample_time <= ?
          ORDER BY sample_time ASC, metric_code ASC
        `
        )
        .all(userId, ...metricCodes, asOf) as unknown as UnifiedMetricRecordRow[];
    }

    return database
      .prepare(
        `
        SELECT
          id,
          metric_code AS metricCode,
          metric_name AS metricName,
          category,
          normalized_value AS normalizedValue,
          unit,
          abnormal_flag AS abnormalFlag,
          sample_time AS sampleTime,
          reference_range AS referenceRange
        FROM metric_record
        WHERE user_id = ? AND metric_code IN (${placeholders})
        ORDER BY sample_time ASC, metric_code ASC
      `
      )
      .all(userId, ...metricCodes) as unknown as UnifiedMetricRecordRow[];
  }

  if (asOf) {
    return database
      .prepare(
        `
        SELECT
          id,
          metric_code AS metricCode,
          metric_name AS metricName,
          category,
          normalized_value AS normalizedValue,
          unit,
          abnormal_flag AS abnormalFlag,
          sample_time AS sampleTime,
          reference_range AS referenceRange
        FROM metric_record
        WHERE user_id = ? AND sample_time <= ?
        ORDER BY sample_time ASC, metric_code ASC
      `
      )
      .all(userId, asOf) as unknown as UnifiedMetricRecordRow[];
  }

  return database
    .prepare(
      `
      SELECT
        id,
        metric_code AS metricCode,
        metric_name AS metricName,
        category,
        normalized_value AS normalizedValue,
        unit,
        abnormal_flag AS abnormalFlag,
        sample_time AS sampleTime,
        reference_range AS referenceRange
      FROM metric_record
      WHERE user_id = ?
      ORDER BY sample_time ASC, metric_code ASC
    `
    )
    .all(userId) as unknown as UnifiedMetricRecordRow[];
}

export function getLatestSampleTime(database: DatabaseSync, userId: string): string | undefined {
  const row = database
    .prepare(
      `
      SELECT MAX(sample_time) AS latestSampleTime
      FROM metric_record
      WHERE user_id = ?
    `
    )
    .get(userId) as { latestSampleTime?: string } | undefined;

  return row?.latestSampleTime;
}

export function getLatestMetricRecordsMap(
  database: DatabaseSync,
  userId: string,
  metricCodes: string[],
  asOf?: string
): Record<string, UnifiedMetricRecordRow | undefined> {
  const records = getUnifiedMetricRecords(database, userId, metricCodes, asOf);
  const latestByMetric = new Map<string, UnifiedMetricRecordRow>();

  for (const row of records) {
    latestByMetric.set(row.metricCode, row);
  }

  return Object.fromEntries(metricCodes.map((metricCode) => [metricCode, latestByMetric.get(metricCode)]));
}

export function getUnifiedTrendSeries(
  database: DatabaseSync,
  userId: string,
  queries: Array<{ metricCode: string; alias: string }>,
  asOf?: string
): UnifiedTrendPoint[] {
  const rows = getUnifiedMetricRecords(
    database,
    userId,
    queries.map((query) => query.metricCode),
    asOf
  );
  const codeToAlias = new Map(queries.map((query) => [query.metricCode, query.alias]));
  const byMetricDate = new Map<string, UnifiedMetricRecordRow>();

  for (const row of rows) {
    const date = row.sampleTime.slice(0, 10);
    byMetricDate.set(`${row.metricCode}::${date}`, row);
  }

  const byDate = new Map<string, UnifiedTrendPoint>();

  for (const row of sortBySampleTime([...byMetricDate.values()])) {
    const date = row.sampleTime.slice(0, 10);
    const item = byDate.get(date) ?? { date };
    const alias = codeToAlias.get(row.metricCode);

    if (alias) {
      item[alias] = row.normalizedValue;
      byDate.set(date, item);
    }
  }

  return [...byDate.values()].sort((left, right) => left.date.localeCompare(right.date));
}

export function saveUnifiedReportSnapshot(
  database: DatabaseSync,
  snapshot: {
    id: string;
    userId: string;
    reportType: ReportKind;
    periodStart: string;
    periodEnd: string;
    summaryJson: string;
    sourceType: string;
    createdAt: string;
    notes?: string;
  }
): void {
  database
    .prepare(
      `
      INSERT INTO report_snapshot (
        id, user_id, report_type, period_start, period_end,
        summary_json, source_type, created_at, notes
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        summary_json = excluded.summary_json,
        source_type = excluded.source_type,
        created_at = excluded.created_at,
        notes = excluded.notes
    `
    )
    .run(
      snapshot.id,
      snapshot.userId,
      snapshot.reportType,
      snapshot.periodStart,
      snapshot.periodEnd,
      snapshot.summaryJson,
      snapshot.sourceType,
      snapshot.createdAt,
      snapshot.notes ?? null
    );
}

export function listUnifiedReportSnapshots(
  database: DatabaseSync,
  userId: string,
  reportType?: ReportKind
): UnifiedReportSnapshotRow[] {
  if (reportType) {
    return database
      .prepare(
        `
        SELECT id, report_type, period_start, period_end, summary_json, source_type, created_at, notes
        FROM report_snapshot
        WHERE user_id = ? AND report_type = ? AND source_type = 'llm_summary'
        ORDER BY period_end DESC, created_at DESC
      `
      )
      .all(userId, reportType) as unknown as UnifiedReportSnapshotRow[];
  }

  return database
    .prepare(
      `
      SELECT id, report_type, period_start, period_end, summary_json, source_type, created_at, notes
      FROM report_snapshot
      WHERE user_id = ? AND source_type = 'llm_summary'
      ORDER BY period_end DESC, created_at DESC
    `
    )
    .all(userId) as unknown as UnifiedReportSnapshotRow[];
}

export function getUnifiedReportSnapshotById(
  database: DatabaseSync,
  userId: string,
  snapshotId: string
): UnifiedReportSnapshotRow | undefined {
  return database
    .prepare(
      `
      SELECT id, report_type, period_start, period_end, summary_json, source_type, created_at, notes
      FROM report_snapshot
      WHERE id = ? AND user_id = ? AND source_type = 'llm_summary'
      LIMIT 1
    `
    )
    .get(snapshotId, userId) as UnifiedReportSnapshotRow | undefined;
}

export function deleteReportSnapshotsForUser(
  database: DatabaseSync,
  userId: string
): void {
  database
    .prepare(
      `
      DELETE FROM report_snapshot
      WHERE user_id = ?
    `
    )
    .run(userId);
}
