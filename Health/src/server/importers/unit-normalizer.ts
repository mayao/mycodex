import { canonicalizeUnit } from "./header-utils";
import type { ImportFieldMapping } from "./types";

interface NormalizeInput {
  rawValue: number;
  rawUnit?: string;
  mapping: ImportFieldMapping;
}

interface NormalizeOutput {
  normalizedValue: number;
  normalizedUnit: string;
}

function round(value: number, digits = 4): number {
  return Number(value.toFixed(digits));
}

export function normalizeMetricValue({
  rawValue,
  rawUnit,
  mapping
}: NormalizeInput): NormalizeOutput {
  const incomingUnit = canonicalizeUnit(rawUnit) ?? mapping.defaultSourceUnit ?? mapping.canonicalUnit;
  const targetUnit = mapping.canonicalUnit;

  if (incomingUnit === targetUnit) {
    return {
      normalizedValue: round(rawValue),
      normalizedUnit: targetUnit
    };
  }

  const converters: Record<string, () => number> = {
    "weight:g->kg": () => rawValue / 1000,
    "weight:lb->kg": () => rawValue * 0.45359237,
    "height:m->cm": () => rawValue * 100,
    "cholesterol:mg/dL->mmol/L": () => rawValue * 0.02586,
    "triglycerides:mg/dL->mmol/L": () => rawValue * 0.01129,
    "glucose:mg/dL->mmol/L": () => rawValue * 0.0555,
    "creatinine:mg/dL->umol/L": () => rawValue * 88.4,
    "duration:s->min": () => rawValue / 60,
    "duration:h->min": () => rawValue * 60,
    "distance:m->km": () => rawValue / 1000,
    "energy:cal->kcal": () => rawValue / 1000
  };

  const key = `${mapping.normalizer}:${incomingUnit}->${targetUnit}`;
  const converter = converters[key];

  if (!converter) {
    throw new Error(`Unsupported unit conversion: ${mapping.metricCode} ${incomingUnit} -> ${targetUnit}`);
  }

  return {
    normalizedValue: round(converter()),
    normalizedUnit: targetUnit
  };
}

export function computeAbnormalFlag(
  value: number,
  mapping: Pick<ImportFieldMapping, "referenceLow" | "referenceHigh">
): "low" | "normal" | "high" | "unknown" {
  if (
    typeof mapping.referenceLow !== "number" &&
    typeof mapping.referenceHigh !== "number"
  ) {
    return "unknown";
  }

  if (typeof mapping.referenceLow === "number" && value < mapping.referenceLow) {
    return "low";
  }

  if (typeof mapping.referenceHigh === "number" && value > mapping.referenceHigh) {
    return "high";
  }

  return "normal";
}
