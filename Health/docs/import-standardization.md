# 阶段 3: 数据导入与标准化

本阶段只做导入与标准化，不扩展 dashboard、规则配置化或医疗判断。

## 当前支持的导入类型

1. 体检 Excel / CSV
2. 血液检查 Excel / CSV
3. 体脂秤 CSV
4. 运动 CSV

## 导入链路

### 1. 读取表格

统一使用 `xlsx` 读取：

- `.csv`
- `.xlsx`
- `.xls`

默认读取第一个工作表。

### 2. 字段映射层

每类 importer 都有自己的 `ImporterSpec`，包含：

- `sampleTimeAliases`
- `noteAliases`
- `contextAliases`
- `fieldMappings`

`fieldMappings` 负责把来源表头映射到统一指标，例如：

- `总胆固醇(mg/dL)` -> `lipid.total_cholesterol`
- `体脂率(%)` -> `body.body_fat_pct`
- `时长(s)` -> `activity.exercise_minutes`

### 3. 单位标准化

当前已实现的标准化包括：

- `mg/dL -> mmol/L`
  - 总胆固醇 / HDL-C / LDL-C
- `mg/dL -> mmol/L`
  - 甘油三酯
- `mg/dL -> mmol/L`
  - 血糖
- `mg/dL -> umol/L`
  - 肌酐
- `s -> min`
  - 运动时长
- `m -> km`
  - 运动距离
- `g -> kg`
  - 体重
- `cal -> kcal`
  - 能量

### 4. 异常标记

按字段映射中的参考区间计算：

- 小于下限 -> `low`
- 大于上限 -> `high`
- 落在区间内 -> `normal`
- 无参考范围 -> `unknown`

### 5. 导入日志与失败追踪

新增表：

- `import_row_log`

用于逐条记录：

- 第几行
- 哪个字段
- 哪个指标
- 导入成功 / 失败
- 失败原因
- 脱敏后的字段标签摘要

`import_task` 继续保存任务级摘要：

- `total_records`
- `success_records`
- `failed_records`
- `task_status`

## 示例导入文件

位于：

- [samples/import/annual_exam_sample.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/annual_exam_sample.csv)
- [samples/import/blood_test_sample.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/blood_test_sample.csv)
- [samples/import/body_scale_sample.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/body_scale_sample.csv)
- [samples/import/activity_sample.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/activity_sample.csv)
- [samples/import/activity_invalid_sample.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/activity_invalid_sample.csv)

模板文件位于：

- [samples/import/templates/annual_exam_template.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/templates/annual_exam_template.csv)
- [samples/import/templates/blood_test_template.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/templates/blood_test_template.csv)
- [samples/import/templates/body_scale_template.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/templates/body_scale_template.csv)
- [samples/import/templates/activity_template.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/templates/activity_template.csv)

## 导入结果接口

`importHealthData()` 现在会返回：

- 任务级结果：`taskStatus`、`totalRecords`、`successRecords`、`failedRecords`
- 字段映射告警：`warnings`
- 行级处理摘要：`logSummary`

失败和跳过的行会写入 `import_row_log`，并保留与任务关联的脱敏字段摘要，可通过导入任务 ID 回查。
其中 `raw_payload_json` 是兼容旧表结构保留的列名，当前保存的是脱敏后的字段标签，或在 `HEALTH_IMPORT_AUDIT_MODE=disabled` 时保存统一占位摘要。
默认前端 API 与运行日志不会直接返回完整原始 payload。

## 当前不支持的数据格式

- PDF 直接导入
- 图片 OCR 导入
- Apple Health XML
- Garmin / Strava 原始导出
- JSON API 实时同步
- 多工作表合并导入
- 带合并单元格和复杂表头的 Excel

## 下一步扩展方向

### 睡眠

新增 `sleep.*` 指标映射即可，例如：

- `sleep.asleep_minutes`
- `sleep.deep_minutes`
- `sleep.rem_minutes`

### 饮食

建议增加 `meal_log` 原始事件表，再把日聚合写回 `metric_record`：

- `diet.calories`
- `diet.protein_g`
- `diet.fiber_g`

### 药物

建议增加 `medication_log` 原始事件表，再把依从性或周期汇总写回统一指标层：

- `medication.days_on_plan`
- `medication.adherence_pct`
