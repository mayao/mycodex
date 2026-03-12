import type { DatabaseSync } from "node:sqlite";

import type {
  HealthReportSnapshotRecord,
  HealthSummaryGenerationResult,
  HealthSummaryPeriod,
  ReportKind,
  ReportsIndexData,
  SummaryPeriodKind
} from "../domain/health-hub";
import { getDatabase } from "../db/sqlite";
import type { StructuredInsightsResult } from "../insights/types";
import { generateHealthSummaryFromStructuredInsights, resolveHealthSummaryProvider } from "../llm/health-summary-service";
import {
  getLatestSampleTime,
  getUnifiedReportSnapshotById,
  listUnifiedReportSnapshots,
  saveUnifiedReportSnapshot
} from "../repositories/unified-health-repository";
import {
  addDaysToAppDate,
  formatAppDate,
  resolveAnalysisAsOf,
  toEndOfAppDayIso
} from "../utils/app-time";
import { generateHolisticStructuredInsights } from "./holistic-insight-service";
import { getPlanReviewForPeriod, type PlanReviewData } from "./health-plan-service";
import { sanitizeHealthSummary, sanitizeReportSnapshot } from "./user-facing-copy";

interface StoredReportSnapshotPayload {
  schemaVersion: number;
  title: string;
  promptVersion: string;
  summary: HealthSummaryGenerationResult;
  structuredInsights: StructuredInsightsResult;
  planReview?: PlanReviewData;
}

interface ServiceClockOptions {
  now?: Date;
}

function toPeriodLabel(kind: SummaryPeriodKind, start: string, end: string): string {
  if (kind === "day") {
    return `${end} 日摘要`;
  }

  if (kind === "week") {
    return `${start} 至 ${end} 周报`;
  }

  return `${start} 至 ${end} 月报`;
}

export function buildSummaryPeriod(kind: SummaryPeriodKind, asOfIso: string): HealthSummaryPeriod {
  const end = formatAppDate(asOfIso);
  const start = kind === "day" ? end : addDaysToAppDate(end, kind === "week" ? -6 : -29);

  return {
    kind,
    label: toPeriodLabel(kind, start, end),
    start,
    end,
    asOf: asOfIso
  };
}

function buildSnapshotId(reportType: ReportKind, periodEnd: string): string {
  return `llm-report::${reportType}::${periodEnd}`;
}

function buildReportTitle(reportType: ReportKind, period: HealthSummaryPeriod): string {
  return reportType === "weekly"
    ? `${period.start} 至 ${period.end} 健康周报`
    : `${period.start} 至 ${period.end} 健康月报`;
}

function safeParseSnapshotPayload(rawJson: string): StoredReportSnapshotPayload | undefined {
  try {
    return JSON.parse(rawJson) as StoredReportSnapshotPayload;
  } catch {
    return undefined;
  }
}

function hydrateSnapshotRecord(row: {
  id: string;
  report_type: string;
  period_start: string;
  period_end: string;
  summary_json: string;
  created_at: string;
}): HealthReportSnapshotRecord | undefined {
  const payload = safeParseSnapshotPayload(row.summary_json);

  if (!payload) {
    return undefined;
  }

  return sanitizeReportSnapshot({
    id: row.id,
    reportType: row.report_type as ReportKind,
    periodStart: row.period_start,
    periodEnd: row.period_end,
    createdAt: row.created_at,
    title: payload.title,
    summary: payload.summary,
    structuredInsights: payload.structuredInsights,
    planReview: payload.planReview
  });
}

async function createReportSnapshot(
  database: DatabaseSync,
  userId: string,
  reportType: ReportKind,
  asOfIso: string
): Promise<HealthReportSnapshotRecord> {
  const periodKind: SummaryPeriodKind = reportType === "weekly" ? "week" : "month";
  const period = buildSummaryPeriod(periodKind, asOfIso);
  const structuredInsights = generateHolisticStructuredInsights(database, userId, {
    asOf: period.asOf
  });
  const summary = sanitizeHealthSummary(
    await generateHealthSummaryFromStructuredInsights(
      structuredInsights,
      period,
      resolveHealthSummaryProvider()
    )
  );
  const title = buildReportTitle(reportType, period);
  const planReview = getPlanReviewForPeriod(userId, period.start, period.end, database);
  const payload: StoredReportSnapshotPayload = {
    schemaVersion: 1,
    title,
    promptVersion: summary.prompt.version,
    summary,
    structuredInsights,
    planReview: planReview.items.length > 0 ? planReview : undefined
  };
  const snapshotId = buildSnapshotId(reportType, period.end);

  saveUnifiedReportSnapshot(database, {
    id: snapshotId,
    userId,
    reportType,
    periodStart: period.start,
    periodEnd: period.end,
    summaryJson: JSON.stringify(payload),
    sourceType: "llm_summary",
    createdAt: new Date().toISOString(),
    notes: `${summary.provider}:${summary.model}:${summary.prompt.version}`
  });

  return sanitizeReportSnapshot({
    id: snapshotId,
    reportType,
    periodStart: period.start,
    periodEnd: period.end,
    createdAt: new Date().toISOString(),
    title,
    summary,
    structuredInsights,
    planReview: planReview.items.length > 0 ? planReview : undefined
  });
}

async function ensureReportSeries(
  database: DatabaseSync,
  userId: string,
  reportType: ReportKind,
  asOfIso: string,
  count: number,
  spacingDays: number
): Promise<HealthReportSnapshotRecord[]> {
  const snapshots: HealthReportSnapshotRecord[] = [];
  const latestDate = formatAppDate(asOfIso);

  for (let index = 0; index < count; index += 1) {
    const targetDate = addDaysToAppDate(latestDate, -spacingDays * index);
    const targetAsOf = toEndOfAppDayIso(targetDate);
    const period = buildSummaryPeriod(reportType === "weekly" ? "week" : "month", targetAsOf);
    const snapshotId = buildSnapshotId(reportType, period.end);
    const existing = index === 0 ? undefined : getUnifiedReportSnapshotById(database, userId, snapshotId);

    if (existing) {
      const hydrated = hydrateSnapshotRecord(existing);

      if (hydrated) {
        snapshots.push(hydrated);
        continue;
      }
    }

    snapshots.push(await createReportSnapshot(database, userId, reportType, targetAsOf));
  }

  return snapshots.sort((left, right) => right.periodEnd.localeCompare(left.periodEnd));
}

export async function getCurrentDailySummary(
  database: DatabaseSync = getDatabase(),
  userId = "user-self",
  options: ServiceClockOptions = {}
): Promise<HealthSummaryGenerationResult> {
  const latestAsOf = resolveAnalysisAsOf(getLatestSampleTime(database, userId), options.now);
  const period = buildSummaryPeriod("day", latestAsOf);
  const structuredInsights = generateHolisticStructuredInsights(database, userId, {
    asOf: period.asOf
  });

  return sanitizeHealthSummary(
    await generateHealthSummaryFromStructuredInsights(
      structuredInsights,
      period,
      resolveHealthSummaryProvider()
    )
  );
}

export async function getReportsIndexData(
  database: DatabaseSync = getDatabase(),
  userId = "user-self",
  options: ServiceClockOptions = {}
): Promise<ReportsIndexData> {
  const latestAsOf = resolveAnalysisAsOf(getLatestSampleTime(database, userId), options.now);
  const provider = resolveHealthSummaryProvider();
  const weeklyCount = provider.kind === "mock" ? 4 : 1;
  const monthlyCount = provider.kind === "mock" ? 3 : 1;

  const weeklyReports = await ensureReportSeries(
    database,
    userId,
    "weekly",
    latestAsOf,
    weeklyCount,
    7
  );
  const monthlyReports = await ensureReportSeries(
    database,
    userId,
    "monthly",
    latestAsOf,
    monthlyCount,
    30
  );

  return {
    generatedAt: new Date().toISOString(),
    weeklyReports,
    monthlyReports
  };
}

export async function getReportSnapshotDetail(
  snapshotId: string,
  database: DatabaseSync = getDatabase(),
  userId = "user-self"
): Promise<HealthReportSnapshotRecord | undefined> {
  const row = getUnifiedReportSnapshotById(database, userId, snapshotId);
  return row ? hydrateSnapshotRecord(row) : undefined;
}

export function listSavedReportSnapshots(
  database: DatabaseSync = getDatabase(),
  userId = "user-self",
  reportType?: ReportKind
): HealthReportSnapshotRecord[] {
  return listUnifiedReportSnapshots(database, userId, reportType)
    .map((row) => hydrateSnapshotRecord(row))
    .filter((row): row is HealthReportSnapshotRecord => Boolean(row));
}
