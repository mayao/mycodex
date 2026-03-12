import assert from "node:assert/strict";
import test from "node:test";

import {
  sanitizeDimensionAnalyses,
  sanitizeHealthSummary,
  sanitizeOverviewDigest
} from "./user-facing-copy";

test("sanitizer removes developer prompt copy from summaries", () => {
  const summary = sanitizeHealthSummary({
    provider: "mock",
    model: "mock-health-summary-v1",
    prompt: {
      templateId: "health-summary",
      version: "v2",
      systemPrompt: "internal",
      userPrompt: "internal"
    },
    output: {
      period_kind: "day",
      headline: "这套首页现在不再只给一个泛泛结论，体脂率仍需继续关注。",
      most_important_changes: [
        "系统提示：输出必须是合法 JSON。",
        "体脂率仍高于参考范围。"
      ],
      possible_reasons: [
        "开发提示：删除这句。",
        "恢复时间偏短。"
      ],
      priority_actions: [
        "Prompt: hide this line.",
        "先把睡眠时长拉近 7 小时。"
      ],
      continue_observing: [
        "userPrompt: hidden",
        "继续观察血脂和体脂率联动变化。"
      ],
      disclaimer: "回答仅用于健康管理和数据解读。"
    }
  });

  assert.equal(summary.output.headline, "体脂率仍需继续关注");
  assert.deepEqual(summary.output.most_important_changes, ["体脂率仍高于参考范围"]);
  assert.deepEqual(summary.output.possible_reasons, ["恢复时间偏短"]);
  assert.deepEqual(summary.output.priority_actions, ["先把睡眠时长拉近 7 小时"]);
  assert.deepEqual(summary.output.continue_observing, ["继续观察血脂和体脂率联动变化"]);
});

test("sanitizer keeps health conclusions while stripping meta clauses", () => {
  const digest = sanitizeOverviewDigest({
    headline: "这份首页现在不再只给一个泛泛结论，近期恢复偏短需要继续关注。",
    summary: "开发提示：删掉这句，近期体脂率和睡眠恢复仍需持续关注。",
    goodSignals: ["体重继续下降。"],
    needsAttention: ["Prompt: remove", "体脂率仍高于参考范围。"],
    longTermRisks: ["Lp(a) 适合按长周期跟踪。"],
    actionPlan: ["系统提示：remove", "继续保留训练节奏。"]
  });
  const analyses = sanitizeDimensionAnalyses([
    {
      key: "integrated",
      kicker: "AI",
      title: "综合",
      summary: "这套首页现在不再只给一个泛泛结论，而是提示恢复偏短。",
      goodSignals: ["体重继续下降。"],
      needsAttention: ["开发提示：删掉", "恢复时间偏短。"],
      longTermRisks: ["Lp(a) 更适合长期观察。"],
      actionPlan: ["Prompt: remove", "先把睡眠拉近 7 小时。"],
      metrics: [
        {
          label: "恢复",
          value: "6.3 h",
          detail: "系统提示：隐藏。恢复时间偏短。",
          tone: "attention"
        }
      ]
    }
  ]);

  assert.equal(digest.headline, "近期恢复偏短需要继续关注");
  assert.equal(digest.summary, "近期体脂率和睡眠恢复仍需持续关注");
  assert.deepEqual(digest.needsAttention, ["体脂率仍高于参考范围"]);
  assert.deepEqual(digest.actionPlan, ["继续保留训练节奏"]);
  assert.equal(analyses[0]?.summary, "提示恢复偏短");
  assert.deepEqual(analyses[0]?.needsAttention, ["恢复时间偏短"]);
  assert.deepEqual(analyses[0]?.actionPlan, ["先把睡眠拉近 7 小时"]);
  assert.equal(analyses[0]?.metrics[0]?.detail, "恢复时间偏短");
});
