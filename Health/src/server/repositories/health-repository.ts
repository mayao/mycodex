import type { DatabaseSync } from "node:sqlite";

import type {
  CoverageItem,
  LatestMetric,
  MeasurementSetKind,
  TrendPoint
} from "../domain/types";

const coverageMeta: Record<
  MeasurementSetKind,
  Pick<CoverageItem, "label" | "status" | "detail">
> = {
  annual_exam: {
    label: "历年体检",
    status: "ready",
    detail: "用于承载历年体检摘要趋势，当前已放入 2 份样例。"
  },
  lipid_panel: {
    label: "血脂专项",
    status: "ready",
    detail: "重点覆盖 TC、TG、HDL-C、LDL-C、ApoA1、ApoB、Lp(a) 等指标。"
  },
  body_composition: {
    label: "体脂秤",
    status: "ready",
    detail: "当前为 Fitdays 样例，保留体重、体脂、肌肉和内脏脂肪等结构化指标。"
  },
  activity_daily: {
    label: "运动活动",
    status: "ready",
    detail: "当前以 Apple Health 日汇总形式入库，后续可扩展为单次运动 session。"
  },
  sleep_daily: {
    label: "睡眠恢复",
    status: "ready",
    detail: "当前保存卧床和睡眠分钟，后续可扩展睡眠阶段与 HRV。"
  },
  diet_daily: {
    label: "饮食记录",
    status: "ready",
    detail: "当前仅保留每日热量汇总与记录次数，用于趋势反馈和记录覆盖分析。"
  },
  genetic_panel: {
    label: "基因检测",
    status: "demo",
    detail: "当前仅放入演示 finding，用于验证 schema 的可扩展性。"
  }
};

interface MetricSeriesRow {
  recordedAt: string;
  value: number;
}

interface SqliteMetricSeriesRow {
  recordedAt: string;
  value: number;
}

export interface MetricSeriesQuery {
  metricCode: string;
  alias: string;
}

export function getLatestMetric(
  database: DatabaseSync,
  metricCode: string,
  userId?: string
): LatestMetric | undefined {
  if (userId) {
    return database
      .prepare(
        `
        SELECT
          m.metric_code AS metricCode,
          c.label AS label,
          c.short_label AS shortLabel,
          m.value_numeric AS value,
          m.unit AS unit,
          s.recorded_at AS recordedAt,
          s.set_kind AS setKind,
          s.title AS setTitle
        FROM measurements m
        JOIN measurement_sets s ON s.id = m.measurement_set_id
        JOIN metric_catalog c ON c.code = m.metric_code
        WHERE m.metric_code = ? AND s.user_id = ?
        ORDER BY s.recorded_at DESC
        LIMIT 1
      `
      )
      .get(metricCode, userId) as LatestMetric | undefined;
  }

  return database
    .prepare(
      `
      SELECT
        m.metric_code AS metricCode,
        c.label AS label,
        c.short_label AS shortLabel,
        m.value_numeric AS value,
        m.unit AS unit,
        s.recorded_at AS recordedAt,
        s.set_kind AS setKind,
        s.title AS setTitle
      FROM measurements m
      JOIN measurement_sets s ON s.id = m.measurement_set_id
      JOIN metric_catalog c ON c.code = m.metric_code
      WHERE m.metric_code = ?
      ORDER BY s.recorded_at DESC
      LIMIT 1
    `
    )
    .get(metricCode) as LatestMetric | undefined;
}

export function getLatestMetricsMap(
  database: DatabaseSync,
  metricCodes: string[],
  userId?: string
): Record<string, LatestMetric | undefined> {
  return Object.fromEntries(
    metricCodes.map((metricCode) => [metricCode, getLatestMetric(database, metricCode, userId)])
  );
}

function getMetricSeries(
  database: DatabaseSync,
  metricCode: string,
  kinds?: MeasurementSetKind[],
  userId?: string
): MetricSeriesRow[] {
  const mapRows = (rows: SqliteMetricSeriesRow[]): MetricSeriesRow[] =>
    rows.map((row) => ({
      recordedAt: row.recordedAt,
      value: Number(row.value)
    }));

  const userFilter = userId ? " AND s.user_id = ?" : "";

  if (kinds && kinds.length > 0) {
    const placeholders = kinds.map(() => "?").join(", ");
    const params = userId
      ? [metricCode, ...kinds, userId]
      : [metricCode, ...kinds];
    const rows = database
      .prepare(
        `
        SELECT s.recorded_at AS recordedAt, m.value_numeric AS value
        FROM measurements m
        JOIN measurement_sets s ON s.id = m.measurement_set_id
        WHERE m.metric_code = ? AND s.set_kind IN (${placeholders})${userFilter}
        ORDER BY s.recorded_at ASC
      `
      )
      .all(...params) as unknown as SqliteMetricSeriesRow[];

    return mapRows(rows);
  }

  const params = userId ? [metricCode, userId] : [metricCode];
  const rows = database
    .prepare(
      `
      SELECT s.recorded_at AS recordedAt, m.value_numeric AS value
      FROM measurements m
      JOIN measurement_sets s ON s.id = m.measurement_set_id
      WHERE m.metric_code = ?${userFilter}
      ORDER BY s.recorded_at ASC
    `
    )
    .all(...params) as unknown as SqliteMetricSeriesRow[];

  return mapRows(rows);
}

export function getMergedSeries(
  database: DatabaseSync,
  queries: MetricSeriesQuery[],
  kinds?: MeasurementSetKind[],
  userId?: string
): TrendPoint[] {
  const byDate = new Map<string, TrendPoint>();

  for (const query of queries) {
    const rows = getMetricSeries(database, query.metricCode, kinds, userId);

    for (const row of rows) {
      const date = row.recordedAt.slice(0, 10);
      const current = byDate.get(date) ?? { date };
      current[query.alias] = row.value;
      byDate.set(date, current);
    }
  }

  return [...byDate.values()].sort((left, right) => left.date.localeCompare(right.date));
}

export function getCoverageSummary(database: DatabaseSync, userId?: string): CoverageItem[] {
  const userFilter = userId ? " WHERE user_id = ?" : "";
  const params = userId ? [userId] : [];

  const rows = database
    .prepare(
      `
      SELECT set_kind AS kind, COUNT(*) AS count, MAX(recorded_at) AS latestRecordedAt
      FROM measurement_sets${userFilter}
      GROUP BY set_kind
    `
    )
    .all(...params) as Array<{
    kind: MeasurementSetKind;
    count: number;
    latestRecordedAt: string | null;
  }>;

  const measurementItems = rows.map((row) => ({
    kind: row.kind,
    count: row.count,
    latestRecordedAt: row.latestRecordedAt,
    ...coverageMeta[row.kind]
  }));

  const geneRow = database
    .prepare(
      `
      SELECT COUNT(*) AS count, MAX(recorded_at) AS latestRecordedAt
      FROM genetic_findings${userFilter}
    `
    )
    .get(...params) as { count: number; latestRecordedAt: string | null };

  measurementItems.push({
    kind: "genetic_panel",
    count: geneRow.count,
    latestRecordedAt: geneRow.latestRecordedAt,
    ...coverageMeta.genetic_panel
  });

  const order: MeasurementSetKind[] = [
    "annual_exam",
    "lipid_panel",
    "body_composition",
    "activity_daily",
    "sleep_daily",
    "diet_daily",
    "genetic_panel"
  ];

  return measurementItems.sort(
    (left, right) => order.indexOf(left.kind) - order.indexOf(right.kind)
  );
}
