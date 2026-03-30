import type { DatabaseSync } from "node:sqlite";

export type ImporterKey =
  | "annual_exam"
  | "blood_test"
  | "body_scale"
  | "activity"
  | "genetic"
  | "diet";

export type UnifiedMetricCategory =
  | "body_composition"
  | "lipid"
  | "activity"
  | "sleep"
  | "lab"
  | "diet";

export type ImportRowStatus = "imported" | "failed" | "skipped";
export type ImportTaskStatus =
  | "running"
  | "completed"
  | "completed_with_errors"
  | "failed";

export interface ImportFieldMapping {
  metricCode: string;
  metricName: string;
  category: UnifiedMetricCategory;
  aliases: string[];
  canonicalUnit: string;
  betterDirection: "up" | "down" | "neutral";
  description: string;
  defaultSourceUnit?: string;
  referenceLow?: number;
  referenceHigh?: number;
  referenceRange?: string;
  normalizer:
    | "identity"
    | "weight"
    | "height"
    | "cholesterol"
    | "triglycerides"
    | "glucose"
    | "creatinine"
    | "duration"
    | "distance"
    | "energy"
    | "percentage"
    | "heart_rate";
}

export interface ImporterSpec {
  key: ImporterKey;
  sourceType: string;
  sourceName: string;
  taskType: string;
  sampleTimeAliases: string[];
  noteAliases: string[];
  contextAliases?: string[];
  fieldMappings: ImportFieldMapping[];
}

export interface TabularReadResult {
  filePath: string;
  sheetName: string;
  headers: string[];
  rows: Array<Record<string, string>>;
}

export interface MappedHeader {
  header: string;
  headerUnit?: string;
  mapping: ImportFieldMapping;
}

export interface ImportRequest {
  importerKey: ImporterKey;
  userId: string;
  filePath: string;
  importTaskId?: string;
  dataSourceId?: string;
  sourceFileName?: string;
  taskNotes?: string;
}

export interface ImportWarning {
  code: "unmapped_header" | "unmapped_row" | "empty_file" | "no_mapped_headers";
  message: string;
  header?: string;
  rowNumber?: number;
}

export interface ImportRowResult {
  rowNumber: number;
  status: ImportRowStatus;
  metricCode?: string;
  sourceField?: string;
  errorMessage?: string;
}

export interface ImportExecutionResult {
  importTaskId: string;
  importerKey: ImporterKey;
  filePath: string;
  taskStatus: ImportTaskStatus;
  totalRecords: number;
  successRecords: number;
  failedRecords: number;
  logSummary: ImportRowResult[];
  warnings: ImportWarning[];
}

export interface ImportFailureTrace {
  rowNumber: number;
  metricCode?: string;
  sourceField?: string;
  errorMessage: string;
  rawPayload: Record<string, string>;
}

export interface ImportLogEntry {
  rowNumber: number;
  rowStatus: ImportRowStatus;
  metricCode?: string;
  sourceField?: string;
  errorMessage?: string;
  rawPayload: Record<string, string>;
  createdAt: string;
}

export interface Importer {
  key: ImporterKey;
  spec: ImporterSpec;
  import: (database: DatabaseSync, request: ImportRequest) => ImportExecutionResult;
}
