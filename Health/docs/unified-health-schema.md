# 阶段 2: 统一健康数据 Schema 设计说明

本阶段只做统一健康数据 schema 和数据库迁移，不扩展真实导入、周报生成或 LLM 洞察。

## 目标

把不同来源的健康数据统一到同一套指标模型中，支持：

1. 同一指标跨年份对比
2. 同一指标跨来源对比
3. 血脂、体脂、运动三大类的统一查询与趋势分析
4. 后续平滑扩展到睡眠、饮食、药物

## 设计原则

### 1. 指标定义和指标事实分离

- `metric_definition` 管“这个指标是什么”
- `metric_record` 管“这个指标在某个时间、某个来源、某个用户上的一次观测值”

这样做的好处是：

1. 趋势分析只需要按 `metric_code + sample_time` 聚合
2. 多来源导入只需要对齐到统一 `metric_code`
3. 指标解释、单位、参考范围可以沉淀在定义层

### 2. 记录层保留冗余字段

`metric_record` 中重复保存 `metric_name`、`category`、`source_type`，不是范式最优，但对分析查询更友好。后续做周报、联动分析、规则引擎时，可以减少 join 成本。

### 3. 原始值与标准化值同时保留

- `raw_value` 保留来源原文或原始数值
- `normalized_value` 作为统一分析值
- `unit` 默认保存统一分析单位

这样可以兼顾“可追溯”和“可比较”。

## 核心实体

## `metric_definition`

用途：统一维护指标定义。

关键字段：

- `metric_code`: 全局唯一编码，例如 `lipid.ldl_c`
- `metric_name`: 指标名称
- `category`: 指标分类，例如 `lipid`、`body_composition`、`activity`
- `canonical_unit`: 统一分析单位
- `better_direction`: 趋势解释方向
- `reference_range`: 参考范围文本
- `supported_source_types`: 支持的来源类型

## `metric_record`

用途：统一承载所有健康指标事实数据。

必备字段已覆盖：

- `user_id`
- `metric_code`
- `metric_name`
- `category`
- `raw_value`
- `normalized_value`
- `unit`
- `reference_range`
- `abnormal_flag`
- `sample_time`
- `source_type`
- `source_file`
- `notes`

补充字段：

- `data_source_id`
- `import_task_id`
- `created_at`

## `data_source`

用途：描述数据来自哪里，例如体检 PDF、体脂秤 App、Apple Health。

关键字段：

- `source_type`
- `source_name`
- `vendor`
- `ingest_channel`
- `source_file`

## `import_task`

用途：记录一次导入或回填任务，便于后续做导入审计和失败回溯。

关键字段：

- `task_type`
- `task_status`
- `source_type`
- `source_file`
- `started_at`
- `finished_at`
- `total_records`
- `success_records`
- `failed_records`

## `insight_record`

用途：沉淀结构化洞察结果，而不是只在页面临时计算。

关键字段：

- `metric_code`
- `category`
- `insight_type`
- `severity`
- `title`
- `summary`
- `related_record_ids`
- `disclaimer`

## `report_snapshot`

用途：把周报、月报的摘要结果保存成快照，便于归档与回看。

关键字段：

- `report_type`
- `period_start`
- `period_end`
- `summary_json`
- `source_type`

## 为什么能支持跨年份与跨来源对比

因为所有观测最终都会落到：

- 同一个 `metric_code`
- 同一个 `normalized_value`
- 同一个 `sample_time`

例如 `body.weight` 可以同时来自：

1. 历年体检
2. 体脂秤

而 `lipid.ldl_c` 可以同时来自：

1. 年度体检
2. 血脂专项复查

只要导入时映射到同一 `metric_code`，后续对比就是统一查询问题，不再是来源差异问题。

## 当前分类策略

- `lipid`: 血脂相关
- `body_composition`: 体脂、体重、肌肉、BMI
- `activity`: 活动能量、训练分钟、站立时长
- `sleep`: 睡眠相关
- `lab`: 血糖、肾功能、尿酸等其他实验室指标

## 迁移策略

本阶段采用“新表 + 旧表回填”的方式，不直接破坏阶段 1 结构。

### 迁移步骤

1. 保留阶段 1 的旧表
2. 新建统一数据层的 6 张核心表
3. 从旧表回填到新表
4. 追加 `insight_record` 和 `report_snapshot` 的演示数据

优点：

1. 风险低，不影响阶段 1 页面与旧逻辑
2. 可以逐步把查询和规则迁移到新表
3. 未来真实导入时直接写新表即可

## 当前 mock 数据

迁移后 `metric_record` 会生成 170 条以上 mock 记录，覆盖：

- 血脂专项
- 体脂秤
- Apple Health 运动
- Apple Health 睡眠
- 历年体检

因此已经满足“30 条以上 mock 数据”的要求。

## 未来扩展方式

### 扩展到睡眠

新增 metric code 即可，例如：

- `sleep.asleep_minutes`
- `sleep.deep_minutes`
- `sleep.rem_minutes`
- `sleep.sleep_efficiency`

不需要新增事实表，只需新增 `metric_definition` 和导入映射。

### 扩展到饮食

建议用两层：

1. 饮食原始事件表，例如 `meal_log`
2. 聚合后再写入 `metric_record`

例如：

- `diet.calories`
- `diet.protein_g`
- `diet.fiber_g`

### 扩展到药物

药物本身建议单独用事件表记录，例如 `medication_log`，再把需要趋势分析的量化结果写回 `metric_record` 或关联到 `insight_record`。

例如：

- `medication.statin_adherence_pct`
- `medication.days_on_plan`

## 非目标

本阶段不做：

1. 医疗诊断
2. 真实 PDF OCR 或解析器
3. 规则配置化
4. LLM 直接读取原始数据库
