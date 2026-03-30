import type { DatabaseSync } from "node:sqlite";

import {
  appendTaskNotes,
  buildReferenceRange,
  buildTaskNotes,
  createImportTask,
  ensureDataSource,
  ensureMetricDefinition,
  finalizeImportTask,
  insertImportRowLog,
  makeTaskNoteEntries,
  upsertMetricRecord
} from "../importers/import-task-support";
import { computeAbnormalFlag, normalizeMetricValue } from "../importers/unit-normalizer";
import type { ImportFieldMapping } from "../importers/types";
import { getDatabase } from "../db/sqlite";

export type HealthKitMetricKind =
  | "weight"
  | "bodyFat"
  | "bmi"
  | "steps"
  | "distanceWalkingRunning"
  | "activeEnergy"
  | "exerciseMinutes"
  | "sleepMinutes"
  | "restingHeartRate"
  | "walkingHeartRateAverage"
  | "heartRateVariability"
  | "oxygenSaturation"
  | "respiratoryRate";

export interface HealthKitSyncSampleInput {
  kind: HealthKitMetricKind;
  value: number;
  unit: string;
  sampleTime: string;
  sourceLabel?: string;
}

export interface HealthKitSyncRequestPayload {
  samples: HealthKitSyncSampleInput[];
}

interface HealthKitSyncSampleWireInput {
  kind?: string;
  value?: number | string;
  unit?: string;
  sampleTime?: string;
  sample_time?: string;
  sampleDate?: string;
  sample_date?: string;
  recordedAt?: string;
  recorded_at?: string;
  sourceLabel?: string;
  source_label?: string;
}

interface HealthKitSyncRequestWirePayload {
  samples?: HealthKitSyncSampleWireInput[];
}

export interface HealthKitSyncResult {
  importTaskId: string;
  taskStatus: "completed" | "failed" | "completed_with_errors";
  totalRecords: number;
  successRecords: number;
  failedRecords: number;
  syncedKinds: HealthKitMetricKind[];
  latestSampleTime?: string;
}

const healthKitMappings: Record<HealthKitMetricKind, ImportFieldMapping> = {
  weight: {
    metricCode: "body.weight",
    metricName: "体重",
    category: "body_composition",
    aliases: ["体重", "weight"],
    canonicalUnit: "kg",
    betterDirection: "down",
    description: "Apple 健康同步的体重",
    defaultSourceUnit: "kg",
    referenceLow: 60.6,
    referenceHigh: 82,
    referenceRange: "60.6 - 82 kg",
    normalizer: "weight"
  },
  bodyFat: {
    metricCode: "body.body_fat_pct",
    metricName: "体脂率",
    category: "body_composition",
    aliases: ["体脂率", "bodyfat"],
    canonicalUnit: "%",
    betterDirection: "down",
    description: "Apple 健康同步的体脂率",
    defaultSourceUnit: "%",
    referenceLow: 10,
    referenceHigh: 20,
    referenceRange: "10 - 20 %",
    normalizer: "percentage"
  },
  bmi: {
    metricCode: "body.bmi",
    metricName: "BMI",
    category: "body_composition",
    aliases: ["BMI"],
    canonicalUnit: "kg/m2",
    betterDirection: "down",
    description: "Apple 健康同步的 BMI",
    defaultSourceUnit: "kg/m2",
    referenceLow: 18.5,
    referenceHigh: 24.9,
    referenceRange: "18.5 - 24.9 kg/m2",
    normalizer: "identity"
  },
  steps: {
    metricCode: "activity.steps",
    metricName: "步数",
    category: "activity",
    aliases: ["步数", "steps"],
    canonicalUnit: "count",
    betterDirection: "up",
    description: "Apple 健康同步的步数",
    defaultSourceUnit: "count",
    normalizer: "identity"
  },
  distanceWalkingRunning: {
    metricCode: "activity.distance_km",
    metricName: "距离",
    category: "activity",
    aliases: ["距离", "distance"],
    canonicalUnit: "km",
    betterDirection: "up",
    description: "Apple 健康同步的步行/跑步距离",
    defaultSourceUnit: "km",
    normalizer: "distance"
  },
  activeEnergy: {
    metricCode: "activity.active_kcal",
    metricName: "活动能量",
    category: "activity",
    aliases: ["活动能量", "activekcal"],
    canonicalUnit: "kcal",
    betterDirection: "up",
    description: "Apple 健康同步的活动能量",
    defaultSourceUnit: "kcal",
    normalizer: "energy"
  },
  exerciseMinutes: {
    metricCode: "activity.exercise_minutes",
    metricName: "训练分钟",
    category: "activity",
    aliases: ["训练分钟", "exerciseminutes"],
    canonicalUnit: "min",
    betterDirection: "up",
    description: "Apple 健康同步的锻炼分钟",
    defaultSourceUnit: "min",
    normalizer: "duration"
  },
  sleepMinutes: {
    metricCode: "sleep.asleep_minutes",
    metricName: "睡眠时间",
    category: "sleep",
    aliases: ["睡眠时间", "sleepminutes"],
    canonicalUnit: "min",
    betterDirection: "up",
    description: "Apple 健康同步的睡眠时长",
    defaultSourceUnit: "min",
    referenceLow: 420,
    referenceHigh: 540,
    referenceRange: "420 - 540 min",
    normalizer: "duration"
  },
  restingHeartRate: {
    metricCode: "activity.resting_heart_rate",
    metricName: "静息心率",
    category: "activity",
    aliases: ["静息心率", "restingHeartRate"],
    canonicalUnit: "count/min",
    betterDirection: "down",
    description: "Apple 健康同步的静息心率",
    defaultSourceUnit: "count/min",
    referenceLow: 45,
    referenceHigh: 75,
    referenceRange: "45 - 75 count/min",
    normalizer: "heart_rate"
  },
  walkingHeartRateAverage: {
    metricCode: "activity.walking_heart_rate_avg",
    metricName: "步行平均心率",
    category: "activity",
    aliases: ["步行平均心率", "walkingHeartRateAverage"],
    canonicalUnit: "count/min",
    betterDirection: "down",
    description: "Apple 健康同步的步行平均心率",
    defaultSourceUnit: "count/min",
    referenceLow: 60,
    referenceHigh: 110,
    referenceRange: "60 - 110 count/min",
    normalizer: "heart_rate"
  },
  heartRateVariability: {
    metricCode: "activity.hrv_sdnn",
    metricName: "心率变异性",
    category: "activity",
    aliases: ["心率变异性", "heartRateVariability"],
    canonicalUnit: "ms",
    betterDirection: "up",
    description: "Apple 健康同步的心率变异性 SDNN",
    defaultSourceUnit: "ms",
    referenceLow: 20,
    referenceHigh: 120,
    referenceRange: "20 - 120 ms",
    normalizer: "identity"
  },
  oxygenSaturation: {
    metricCode: "activity.oxygen_saturation_pct",
    metricName: "血氧饱和度",
    category: "activity",
    aliases: ["血氧饱和度", "oxygenSaturation"],
    canonicalUnit: "%",
    betterDirection: "up",
    description: "Apple 健康同步的血氧饱和度",
    defaultSourceUnit: "%",
    referenceLow: 95,
    referenceHigh: 100,
    referenceRange: "95 - 100 %",
    normalizer: "percentage"
  },
  respiratoryRate: {
    metricCode: "activity.respiratory_rate",
    metricName: "呼吸频率",
    category: "activity",
    aliases: ["呼吸频率", "respiratoryRate"],
    canonicalUnit: "count/min",
    betterDirection: "neutral",
    description: "Apple 健康同步的呼吸频率",
    defaultSourceUnit: "count/min",
    referenceLow: 12,
    referenceHigh: 20,
    referenceRange: "12 - 20 count/min",
    normalizer: "heart_rate"
  }
};

function isHealthKitMetricKind(value: string): value is HealthKitMetricKind {
  return value in healthKitMappings;
}

function normalizeHealthKitSyncPayload(
  payload: HealthKitSyncRequestPayload | HealthKitSyncRequestWirePayload
): HealthKitSyncRequestPayload {
  if (!payload || !Array.isArray(payload.samples)) {
    throw new Error("HealthKit sync payload must include a samples array.");
  }

  const rawSamples = payload.samples as HealthKitSyncSampleWireInput[];

  return {
    samples: rawSamples.map((sample, index) => {
      if (!sample || typeof sample !== "object") {
        throw new Error(`Invalid HealthKit sample at index ${index}.`);
      }

      const sampleTime =
        sample.sampleTime ??
        sample.sample_time ??
        sample.sampleDate ??
        sample.sample_date ??
        sample.recordedAt ??
        sample.recorded_at;
      const sourceLabel = sample.sourceLabel ?? sample.source_label;
      const value =
        typeof sample.value === "string" && sample.value.trim().length > 0
          ? Number(sample.value)
          : sample.value;

      if (typeof sample.kind !== "string" || !isHealthKitMetricKind(sample.kind)) {
        throw new Error(`Invalid HealthKit sample kind at index ${index}.`);
      }

      if (typeof value !== "number" || !Number.isFinite(value)) {
        throw new Error(`Invalid HealthKit sample value at index ${index}.`);
      }

      if (typeof sample.unit !== "string" || sample.unit.trim().length === 0) {
        throw new Error(`Invalid HealthKit sample unit at index ${index}.`);
      }

      if (typeof sampleTime !== "string" || sampleTime.trim().length === 0) {
        throw new Error(`Invalid HealthKit sample time at index ${index}.`);
      }

      return {
        kind: sample.kind,
        value,
        unit: sample.unit,
        sampleTime,
        sourceLabel
      };
    })
  };
}

function normalizeSampleTime(value: string): string {
  const trimmed = value.trim();

  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return `${trimmed}T08:00:00+08:00`;
  }

  if (/^\d{4}-\d{2}-\d{2}T/.test(trimmed)) {
    return trimmed.includes("+") || trimmed.endsWith("Z") ? trimmed : `${trimmed}+08:00`;
  }

  throw new Error(`Invalid sample time: ${value}`);
}

export function syncHealthKitSamples(
  payload: HealthKitSyncRequestPayload | HealthKitSyncRequestWirePayload,
  database: DatabaseSync = getDatabase(),
  userId: string = "user-self"
): HealthKitSyncResult {
  const normalizedPayload = normalizeHealthKitSyncPayload(payload);
  const dataSourceId = ensureDataSource(database, userId, {
    sourceType: "apple_health",
    sourceName: "Apple 健康同步",
    ingestChannel: "healthkit",
    notes: "ios healthkit sync"
  });
  const baseNotes = makeTaskNoteEntries([
    ["sync_source", "apple_health"],
    ["sample_count", String(normalizedPayload.samples.length)]
  ]);
  const importTaskId = createImportTask(
    database,
    { userId },
    {
      dataSourceId,
      taskType: "healthkit_sync",
      sourceType: "apple_health",
      notes: baseNotes
    }
  );
  const warnings: Array<{ code: string }> = [];
  let successRecords = 0;
  let failedRecords = 0;
  let totalRecords = 0;
  let latestSampleTime: string | undefined;

  for (const mapping of Object.values(healthKitMappings)) {
    ensureMetricDefinition(database, mapping, "apple_health");
  }

  database.exec("BEGIN");

  try {
    normalizedPayload.samples.forEach((sample, index) => {
      totalRecords += 1;
      const rowNumber = index + 1;
      const mapping = healthKitMappings[sample.kind];

      try {
        const sampleTime = normalizeSampleTime(sample.sampleTime);
        const normalized = normalizeMetricValue({
          rawValue: sample.value,
          rawUnit: sample.unit,
          mapping
        });
        const abnormalFlag = computeAbnormalFlag(normalized.normalizedValue, mapping);

        upsertMetricRecord(database, {
          userId,
          dataSourceId,
          importTaskId,
          metricCode: mapping.metricCode,
          metricName: mapping.metricName,
          category: mapping.category,
          rawValue: String(sample.value),
          normalizedValue: normalized.normalizedValue,
          unit: normalized.normalizedUnit,
          referenceRange: buildReferenceRange(mapping),
          abnormalFlag,
          sampleTime,
          sourceType: "apple_health",
          notes: sample.sourceLabel,
          replaceExisting: true
        });
        insertImportRowLog(
          database,
          importTaskId,
          {
            rowNumber,
            status: "imported",
            metricCode: mapping.metricCode,
            sourceField: sample.kind
          },
          {
            kind: sample.kind,
            unit: sample.unit,
            sample_time: sample.sampleTime
          }
        );
        successRecords += 1;
        latestSampleTime =
          !latestSampleTime || sampleTime > latestSampleTime ? sampleTime : latestSampleTime;
      } catch (error) {
        failedRecords += 1;
        warnings.push({ code: "sync_failed" });
        insertImportRowLog(
          database,
          importTaskId,
          {
            rowNumber,
            status: "failed",
            metricCode: mapping.metricCode,
            sourceField: sample.kind,
            errorMessage: error instanceof Error ? error.message : "healthkit sync failed"
          },
          {
            kind: sample.kind,
            unit: sample.unit,
            sample_time: sample.sampleTime
          }
        );
      }
    });

    database.exec("COMMIT");

    const taskStatus =
      failedRecords > 0 ? (successRecords > 0 ? "completed_with_errors" : "failed") : "completed";
    finalizeImportTask(
      database,
      importTaskId,
      taskStatus,
      totalRecords,
      successRecords,
      failedRecords,
      appendTaskNotes(baseNotes, buildTaskNotes(warnings as never[], taskStatus === "failed" ? "healthkit sync failed" : undefined))
    );

    return {
      importTaskId,
      taskStatus,
      totalRecords,
      successRecords,
      failedRecords,
      syncedKinds: [...new Set(normalizedPayload.samples.map((sample) => sample.kind))],
      latestSampleTime
    };
  } catch (error) {
    database.exec("ROLLBACK");
    finalizeImportTask(
      database,
      importTaskId,
      "failed",
      totalRecords,
      successRecords,
      failedRecords,
      appendTaskNotes(baseNotes, `fatal_reason=${error instanceof Error ? error.message : "healthkit sync failed"}`)
    );
    throw error;
  }
}
