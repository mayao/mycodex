import assert from "node:assert/strict";
import test from "node:test";

import { NON_DIAGNOSTIC_DISCLAIMER } from "../../data/mock/seed-data";
import type { LatestMetric } from "../domain/types";
import { evaluateDashboardRules } from "./rules";

test("rules return non-diagnostic alerts and positive signals", () => {
  const latestMetrics: Record<string, LatestMetric | undefined> = {
    "lipid.lpa": {
      metricCode: "lipid.lpa",
      label: "脂蛋白(a)",
      shortLabel: "Lp(a)",
      value: 61.6,
      unit: "mg/dL",
      recordedAt: "2026-02-11T09:32:17+08:00",
      setKind: "lipid_panel",
      setTitle: "血脂专项复查 2026-02-11"
    },
    "lipid.ldl_c": {
      metricCode: "lipid.ldl_c",
      label: "低密度脂蛋白胆固醇",
      shortLabel: "LDL-C",
      value: 3.62,
      unit: "mmol/L",
      recordedAt: "2026-01-04T10:16:49+08:00",
      setKind: "lipid_panel",
      setTitle: "血脂专项复查 2026-01-04"
    }
  };

  const items = evaluateDashboardRules({
    latestMetrics,
    trends: {
      bodyComposition: [
        { date: "2025-11-23", bodyFat: 24.1, skeletalMuscle: 43.2 },
        { date: "2026-03-06", bodyFat: 22.5, skeletalMuscle: 44.1 }
      ],
      lipid: [],
      activity: [
        { date: "2026-03-01", exerciseMinutes: 51 },
        { date: "2026-03-02", exerciseMinutes: 48 },
        { date: "2026-03-03", exerciseMinutes: 50 },
        { date: "2026-03-04", exerciseMinutes: 46 },
        { date: "2026-03-05", exerciseMinutes: 49 },
        { date: "2026-03-06", exerciseMinutes: 52 },
        { date: "2026-03-07", exerciseMinutes: 54 },
        { date: "2026-03-08", exerciseMinutes: 47 }
      ],
      sleep: [
        { date: "2026-03-02", asleepMinutes: 360 },
        { date: "2026-03-03", asleepMinutes: 355 },
        { date: "2026-03-04", asleepMinutes: 370 },
        { date: "2026-03-05", asleepMinutes: 361 },
        { date: "2026-03-06", asleepMinutes: 365 },
        { date: "2026-03-07", asleepMinutes: 349 },
        { date: "2026-03-08", asleepMinutes: 371 }
      ]
    }
  });

  assert.ok(items.some((item) => item.title.includes("Lp(a)")));
  assert.ok(items.some((item) => item.severity === "positive"));
  assert.ok(items.every((item) => item.disclaimer === NON_DIAGNOSTIC_DISCLAIMER));
});
