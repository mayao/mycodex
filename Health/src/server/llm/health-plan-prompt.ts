import { z } from "zod";

/**
 * Schema for LLM-generated health plan suggestions.
 */
export const healthPlanSuggestionSchema = z.object({
  suggestions: z.array(
    z.object({
      dimension: z.enum(["exercise", "diet", "sleep", "checkup"]),
      title: z.string().min(1),
      description: z.string().min(1),
      target_metric_code: z.string().nullable().optional(),
      target_value: z.number().nullable().optional(),
      target_unit: z.string().nullable().optional(),
      frequency: z.enum(["daily", "weekly", "once"]),
      time_hint: z.string().nullable().optional(),
      priority: z.number().int().min(1).max(5)
    })
  )
});

export type HealthPlanSuggestionOutput = z.infer<typeof healthPlanSuggestionSchema>;

/**
 * Available metric codes the LLM can reference for auto-completion tracking.
 */
const TRACKABLE_METRICS = [
  { code: "activity.steps", name: "步数", unit: "count" },
  { code: "activity.active_kcal", name: "活动消耗", unit: "kcal" },
  { code: "activity.exercise_minutes", name: "运动时长", unit: "min" },
  { code: "sleep.asleep_minutes", name: "睡眠时长", unit: "min" },
  { code: "body.weight", name: "体重", unit: "kg" },
  { code: "body.body_fat_pct", name: "体脂率", unit: "%" },
  { code: "body.bmi", name: "BMI", unit: "kg/m²" },
  { code: "activity.distance_km", name: "步行+跑步距离", unit: "km" },
  { code: "diet.calories_intake_kcal", name: "饮食热量", unit: "kcal" },
  { code: "diet.meal_upload_count", name: "饮食记录次数", unit: "count" }
];

interface MetricSummary {
  metric_code: string;
  metric_name: string;
  avg_value: number | null;
  latest_value: number | null;
  unit: string;
  count: number;
}

export function buildHealthPlanSystemPrompt(): string {
  return [
    "你是 HealthAI App 的健康计划顾问。",
    "你的任务是根据用户最近的健康数据，从四个维度（运动、饮食、睡眠、体检）各生成 1-2 条具体可执行的健康建议。",
    "",
    "要求：",
    "1. 建议必须具体、可量化、可执行，避免空泛的「多运动」「注意饮食」。",
    "2. 如果数据中有对应的可追踪指标，请设置 target_metric_code 和 target_value 以便自动追踪完成情况。",
    "3. 每条建议的 description 应包含：为什么建议这么做（基于数据）、具体怎么做、预期效果。",
    "4. time_hint 用于提醒时间，格式如 \"07:00\" 或 \"morning\" / \"evening\"。",
    "5. priority 1-5，5 最紧急。",
    "6. 建议总数控制在 4-8 条。",
    "7. 如果某个维度数据不足，也要给出通用但具体的建议。",
    "",
    `可追踪指标列表：\n${JSON.stringify(TRACKABLE_METRICS, null, 2)}`,
    "",
    '请严格按照以下 JSON 格式输出，不要添加 markdown 标记或额外文字：',
    '{ "suggestions": [ { "dimension": "exercise", "title": "...", "description": "...", "target_metric_code": "steps", "target_value": 8000, "target_unit": "steps", "frequency": "daily", "time_hint": "07:00", "priority": 3 } ] }'
  ].join("\n");
}

export function buildHealthPlanUserPrompt(metrics: MetricSummary[]): string {
  if (metrics.length === 0) {
    return "用户暂无最近健康数据。请基于一般健康建议，从四个维度各生成 1-2 条具体建议。";
  }

  const dataLines = metrics.map((m) => {
    const parts = [`${m.metric_name} (${m.metric_code})`];
    if (m.latest_value != null) parts.push(`最新值: ${m.latest_value} ${m.unit}`);
    if (m.avg_value != null) parts.push(`7日均值: ${m.avg_value.toFixed(1)} ${m.unit}`);
    parts.push(`记录数: ${m.count}`);
    return `- ${parts.join(", ")}`;
  });

  return [
    "以下是用户最近 7 天的健康数据摘要：",
    "",
    ...dataLines,
    "",
    "请根据以上数据，从运动(exercise)、饮食(diet)、睡眠(sleep)、体检(checkup)四个维度各生成 1-2 条具体可执行的健康建议。"
  ].join("\n");
}
