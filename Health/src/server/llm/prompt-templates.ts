import type { HealthSummaryPromptBundle, HealthSummarySourceInput } from "../domain/health-hub";

export const HEALTH_SUMMARY_TEMPLATE_ID = "health-summary";
export const HEALTH_SUMMARY_TEMPLATE_VERSION = "v2";

const responseContract = `{
  "headline": "string",
  "most_important_changes": ["string"],
  "possible_reasons": ["string"],
  "priority_actions": ["string"],
  "continue_observing": ["string"],
  "disclaimer": "string"
}`;

export function buildHealthSummaryPrompt(
  input: HealthSummarySourceInput
): HealthSummaryPromptBundle {
  const systemPrompt = [
    "你是健康管理产品中的总结层，不做诊断，不制造恐慌。",
    "你只能使用提供的结构化 insights 和 metric summaries。",
    "这些结构化 insights 可能同时包含近期指标、年度体检比较和基因背景维度。",
    "不要编造新的化验值、病史、药物或结论。",
    "如果证据不足，就明确说“现有结构化证据不足以支持进一步判断”。",
    "语气要求：专业、克制、可执行。",
    "输出必须是合法 JSON，并严格满足给定字段。"
  ].join("\n");

  const userPrompt = [
    `任务：基于 ${input.period.label} 的结构化健康 insights，生成一份专业、克制、可执行的健康总结。`,
    "",
    "输出要求：",
    "1. 只使用下方 JSON 中明确给出的事实。",
    "2. 不做诊断，不使用“疾病”“确诊”等措辞。",
    "3. 行动建议要具体，优先写可执行动作。",
    "4. 如果某部分缺少证据，可以留空列表，但不要编造。",
    "",
    "输出 JSON 结构：",
    responseContract,
    "",
    "结构化输入 JSON：",
    JSON.stringify(input, null, 2)
  ].join("\n");

  return {
    templateId: HEALTH_SUMMARY_TEMPLATE_ID,
    version: HEALTH_SUMMARY_TEMPLATE_VERSION,
    systemPrompt,
    userPrompt
  };
}
