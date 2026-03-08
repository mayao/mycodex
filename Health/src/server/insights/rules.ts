import {
  NON_DIAGNOSTIC_DISCLAIMER
} from "../../data/mock/seed-data";
import type {
  DashboardAttentionItem,
  RuleInput,
  TrendPoint
} from "../domain/types";

function averageLast(points: TrendPoint[], key: string, count: number): number | undefined {
  const values = points
    .map((point) => point[key])
    .filter((value): value is number => typeof value === "number")
    .slice(-count);

  if (values.length === 0) {
    return undefined;
  }

  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function delta(points: TrendPoint[], key: string): number | undefined {
  const values = points
    .map((point) => point[key])
    .filter((value): value is number => typeof value === "number");

  if (values.length < 2) {
    return undefined;
  }

  return values.at(-1)! - values[0];
}

export function evaluateDashboardRules(input: RuleInput): DashboardAttentionItem[] {
  const items: DashboardAttentionItem[] = [];

  const latestLpa = input.latestMetrics["lipid.lpa"];
  if (latestLpa && latestLpa.value > 30) {
    items.push({
      id: "rule-lpa-high",
      severity: "attention",
      title: "Lp(a) 仍处长期待关注区间",
      summary: `最近一次 Lp(a) 为 ${latestLpa.value.toFixed(
        1
      )} mg/dL，高于样例参考阈值 30 mg/dL。适合作为长期背景风险标签持续跟踪，而不是只看一次结果。`,
      source: latestLpa.setTitle,
      disclaimer: NON_DIAGNOSTIC_DISCLAIMER
    });
  }

  const latestLdl = input.latestMetrics["lipid.ldl_c"];
  if (latestLdl && latestLdl.value >= 3.4) {
    items.push({
      id: "rule-ldl-watch",
      severity: "watch",
      title: "LDL-C 进入待关注区间",
      summary: `最近一次 LDL-C 为 ${latestLdl.value.toFixed(
        2
      )} mmol/L，建议继续与体重、饮食和运动变化联动观察。`,
      source: latestLdl.setTitle,
      disclaimer: NON_DIAGNOSTIC_DISCLAIMER
    });
  }

  const averageSleep = averageLast(input.trends.sleep, "asleepMinutes", 7);
  if (averageSleep && averageSleep < 420) {
    items.push({
      id: "rule-sleep-short",
      severity: "watch",
      title: "近 7 天平均睡眠时间偏少",
      summary: `近 7 天平均睡眠约 ${(averageSleep / 60).toFixed(
        1
      )} 小时，后续可优先把睡眠恢复作为体脂与训练效果的解释变量。`,
      source: "Apple Health 睡眠",
      disclaimer: NON_DIAGNOSTIC_DISCLAIMER
    });
  }

  const bodyFatDelta = delta(input.trends.bodyComposition, "bodyFat");
  const muscleDelta = delta(input.trends.bodyComposition, "skeletalMuscle");
  if (
    typeof bodyFatDelta === "number" &&
    typeof muscleDelta === "number" &&
    bodyFatDelta <= -1 &&
    muscleDelta >= 0
  ) {
    items.push({
      id: "rule-body-positive",
      severity: "positive",
      title: "体脂下降且骨骼肌率保持稳定",
      summary: `体脂率相对首个样本下降 ${Math.abs(bodyFatDelta).toFixed(
        1
      )} 个百分点，同时骨骼肌率未下降，说明当前减重质量较好。`,
      source: "体脂秤趋势",
      disclaimer: NON_DIAGNOSTIC_DISCLAIMER
    });
  }

  const exerciseAverage = averageLast(input.trends.activity, "exerciseMinutes", 14);
  if (exerciseAverage && exerciseAverage >= 45) {
    items.push({
      id: "rule-activity-positive",
      severity: "positive",
      title: "近期运动执行度较稳定",
      summary: `近 14 天平均训练约 ${exerciseAverage.toFixed(
        0
      )} 分钟，可继续把运动与血脂复查结果做联动分析。`,
      source: "Apple Health 活动",
      disclaimer: NON_DIAGNOSTIC_DISCLAIMER
    });
  }

  return items;
}
