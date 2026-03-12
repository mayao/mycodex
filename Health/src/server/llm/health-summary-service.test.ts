import assert from "node:assert/strict";
import test from "node:test";

import { seedDatabase } from "../db/seed";
import { createInMemoryDatabase } from "../db/sqlite";
import { runPendingMigrations } from "../db/migration-runner";
import { generateStructuredInsights } from "../insights/structured-rule-engine";
import {
  buildHealthSummarySourceInput,
  generateHealthSummaryFromStructuredInsights
} from "./health-summary-service";
import { MockHealthSummaryProvider } from "./providers";

test("health summary prompt input is derived from structured insights only", () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);

  const structured = generateStructuredInsights(database, "user-self");
  const input = buildHealthSummarySourceInput(structured, {
    kind: "week",
    label: "2026-03-02 至 2026-03-08 周报",
    start: "2026-03-02",
    end: "2026-03-08",
    asOf: "2026-03-08T23:59:59+08:00"
  });

  assert.ok(input.structured_insights.length > 0);
  assert.ok(input.metric_summaries.length > 0);
  assert.ok(!("database" in input));
});

test("mock health summary returns required sections and prompt metadata", async () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);

  const structured = generateStructuredInsights(database, "user-self");
  const result = await generateHealthSummaryFromStructuredInsights(structured, {
    kind: "month",
    label: "2026-02-08 至 2026-03-08 月报",
    start: "2026-02-08",
    end: "2026-03-08",
    asOf: "2026-03-08T23:59:59+08:00"
  });

  assert.equal(result.provider, "mock");
  assert.equal(result.prompt.templateId, "health-summary");
  assert.equal(result.prompt.version, "v2");
  assert.ok(result.output.headline.length > 0);
  assert.ok(result.output.priority_actions.length > 0);
  assert.ok(result.output.disclaimer.includes("非医疗诊断"));
});

test("week summaries keep low-severity insights that happen early in the local day", async () => {
  const result = await generateHealthSummaryFromStructuredInsights(
    {
      generated_at: "2026-03-08T12:00:00+08:00",
      user_id: "user-self",
      metric_summaries: [
        {
          metric_code: "body.weight",
          metric_name: "体重",
          category: "body",
          unit: "kg",
          sample_count: 1,
          latest_value: 80.2,
          latest_sample_time: "2026-03-03T01:00:00+08:00",
          abnormal_flag: "normal"
        }
      ],
      insights: [
        {
          id: "trend-boundary-weight",
          kind: "trend",
          title: "体重 在本周起始日凌晨出现回落",
          severity: "low",
          evidence: {
            summary: "体重在 2026-03-03 01:00 出现轻度回落。",
            metrics: [
              {
                metric_code: "body.weight",
                metric_name: "体重",
                unit: "kg",
                latest_value: 80.2,
                latest_sample_time: "2026-03-03T01:00:00+08:00",
                sample_count: 1,
                abnormal_flag: "normal",
                related_record_ids: ["record::boundary-weight"]
              }
            ]
          },
          possible_reason: "最近训练与饮食执行较稳定。",
          suggested_action: "继续按周观察体重和体脂联动。",
          disclaimer: "非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断。"
        }
      ]
    },
    {
      kind: "week",
      label: "2026-03-03 至 2026-03-08 周报",
      start: "2026-03-03",
      end: "2026-03-08",
      asOf: "2026-03-08T23:59:59+08:00"
    },
    new MockHealthSummaryProvider()
  );

  assert.match(result.output.headline, /^2026-03-03 至 2026-03-08 周报重点关注体重/);
  assert.ok(
    result.output.most_important_changes.some((item) => item.includes("体重 在本周起始日凌晨出现回落"))
  );
});
