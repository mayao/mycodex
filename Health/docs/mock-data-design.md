# Mock 数据样例设计

本阶段 mock 数据的目标不是模拟完整真实世界，而是验证下面四件事：

1. `measurement_sets + measurements` 的统一建模是否足够承载体检、专项检验、体脂秤、运动和睡眠。
2. 指标是否同时保留原始值、标准化值、单位、参考范围、异常标记、时间、来源、备注。
3. 趋势图是否能跨来源展示多指标联动。
4. 规则引擎是否能基于结构化数据生成非医疗诊断的提醒。

## 当前样本覆盖

| 数据类型 | 当前样本 | 说明 |
| --- | --- | --- |
| 历年体检 | 2024、2025 各 1 份 | 演示年度趋势整合 |
| 血脂专项 | 2026-01-04、2026-01-19、2026-02-11 | 直接参考你提供的专项检验截图关键指标 |
| 体脂秤 | 2025-11-23 到 2026-03-06 共 5 个节点 | 参考 Fitdays 截图趋势 |
| 运动活动 | 近 14 天日汇总 | Apple Health mock 日数据 |
| 睡眠 | 近 14 天日汇总 | Apple Health mock 日数据 |
| 基因 finding | 2 条 demo finding | 仅验证 schema 扩展性，不代表真实结论 |

## 统一建模样例

### 1. 一次血脂专项复查

```json
{
  "id": "lipid-panel-2026-02-11",
  "sourceId": "source-lipid-panel",
  "kind": "lipid_panel",
  "title": "血脂专项复查 2026-02-11",
  "recordedAt": "2026-02-11T09:32:17+08:00",
  "measurements": [
    {
      "metricCode": "lipid.total_cholesterol",
      "value": 3.45,
      "unit": "mmol/L",
      "abnormalFlag": "normal"
    },
    {
      "metricCode": "lipid.lpa",
      "value": 61.6,
      "unit": "mg/dL",
      "referenceHigh": 30,
      "abnormalFlag": "high"
    }
  ]
}
```

### 2. 一次体脂秤记录

```json
{
  "id": "body-comp-2026-03-06",
  "sourceId": "source-body-scale",
  "kind": "body_composition",
  "title": "体脂秤周统计 2026-03-06",
  "recordedAt": "2026-03-06T08:11:43+08:00",
  "measurements": [
    { "metricCode": "body.weight", "value": 78.9, "unit": "kg" },
    { "metricCode": "body.body_fat_pct", "value": 22.5, "unit": "%" },
    { "metricCode": "body.skeletal_muscle_pct", "value": 44.1, "unit": "%" },
    { "metricCode": "body.visceral_fat_level", "value": 6, "unit": "level" }
  ]
}
```

### 3. 一天的活动汇总

```json
{
  "id": "activity-2026-03-08",
  "sourceId": "source-apple-health",
  "kind": "activity_daily",
  "title": "Apple Health 活动 2026-03-08",
  "recordedAt": "2026-03-08T21:00:00+08:00",
  "measurements": [
    { "metricCode": "activity.active_kcal", "value": 318, "unit": "kcal" },
    { "metricCode": "activity.exercise_minutes", "value": 50, "unit": "min" },
    { "metricCode": "activity.stand_hours", "value": 9, "unit": "h" }
  ]
}
```

### 4. 一天的睡眠汇总

```json
{
  "id": "sleep-2026-03-08",
  "sourceId": "source-apple-health",
  "kind": "sleep_daily",
  "title": "Apple Health 睡眠 2026-03-08",
  "recordedAt": "2026-03-08T10:00:00+08:00",
  "measurements": [
    { "metricCode": "sleep.in_bed_minutes", "value": 445, "unit": "min" },
    { "metricCode": "sleep.asleep_minutes", "value": 371, "unit": "min" }
  ]
}
```

## 为什么不用单独大宽表

因为后续要扩展睡眠、饮食、药物、家族史、基因检测等模块，如果一开始就把所有字段塞进一个宽表，会在导入和扩展阶段迅速失控。首版优先采用：

- `measurement_sets` 表达“一次观测事件”
- `measurements` 表达“事件下的单项指标”
- `metric_catalog` 统一 metric code 与单位

这样做的收益是：

1. 新接一个数据源时，优先做“字段 -> metric code”映射，不必改一堆表结构。
2. 趋势图、规则引擎、提醒系统都可以直接复用统一指标层。
3. 后续真正接 LLM 时，可以先基于规则层摘要，而不是把原始数据库直接喂给模型。

## 下一步 mock 扩展建议

下一阶段接真实导入时，mock 数据建议继续补三类：

1. 体检 PDF 原始字段映射样本：用于校对同义指标名，比如“总胆固醇 / TC / Cholesterol”。
2. 手工录入样本：用于低成本补历史缺口。
3. 异常值样本：用于测试导入时的单位换算和边界处理。
