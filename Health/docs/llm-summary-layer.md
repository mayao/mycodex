# 阶段 5: 结构化 LLM 洞察层

## 核心边界

LLM 层只能读取结构化输入：

- `structured_insights`
- `metric_summaries`
- `summary_focus`
- `period`

它**不能直接读取原始数据库**，也不直接接触原始导入文件。

## Prompt 模板

模板 ID：

- `health-summary`

版本：

- `v1`

系统提示词核心约束：

- 只能使用结构化 insights 和 metric summaries
- 不做诊断
- 不制造恐慌
- 证据不足时明确说明
- 输出固定 JSON

用户提示词会包含：

- 周期信息
- 结构化 JSON 输入
- 输出 JSON 契约

实现位置：

- [prompt-templates.ts](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/src/server/llm/prompt-templates.ts)

## 输出结构

- `headline`
- `most_important_changes`
- `possible_reasons`
- `priority_actions`
- `continue_observing`
- `disclaimer`

## Prompt Versioning

建议按以下方式管理：

1. 用 `templateId + version` 唯一标识 prompt。
2. 任何会影响输出风格、字段或约束的修改都升版本。
3. 报告快照中记录 `prompt.version`，便于回溯同一期报告是由哪一版 prompt 生成。
4. 不覆盖旧版本模板，保留旧模板以支持 A/B 对比和回放。

## 避免幻觉与过度推断

当前实现的控制手段：

1. LLM 输入源只来自结构化规则层，不直接暴露原始表格。
2. Prompt 明确要求“只使用给定 JSON 中的事实”。
3. 输出要求固定 JSON 结构，减少自由发挥空间。
4. 使用 schema 校验模型输出格式。
5. Mock provider 与真实 provider 走同一输出契约。

## Provider

当前支持：

- `mock`
- `openai-compatible`

默认使用 `mock`，真实 provider 通过环境变量切换。
