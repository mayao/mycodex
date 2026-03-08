# 阶段 4: 规则分析引擎

本阶段只构建规则驱动的结构化分析层，不让 LLM 直接读取原始表格。

## 输入层

规则引擎只读取统一 schema 中的 `metric_record` 与 `metric_definition`：

- `metric_code`
- `normalized_value`
- `unit`
- `abnormal_flag`
- `sample_time`
- `reference_range`

这意味着不同来源的数据会先经过导入标准化，再进入分析。

## 当前支持

### 趋势分析

- 上升 / 下降 / 稳定
- 最近一次 vs 历史均值
- 环比（最近一次 vs 约 30 天前）
- 同比（最近一次 vs 约 365 天前）

### 异常分析

- 最近一次超参考范围
- 连续异常
- 临界值预警

### 联动观察

- 体脂变化 vs 运动量变化
- 体脂变化 vs LDL / TG 变化
- 运动频率 vs 体重变化

## 输出

`generateStructuredInsights()` 输出结构化 JSON：

- `metric_summaries`
- `insights`

每条 insight 至少包含：

- `title`
- `severity`
- `evidence`
- `possible_reason`
- `suggested_action`
- `disclaimer`

## 当前边界

- 仍然是规则层，不是医疗诊断
- 不做药物建议
- 不做自由文本推理
- 不直接消费 PDF / 图片 / OCR 原始数据
