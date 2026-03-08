# 阶段 8: 隐私、安全与日志

## 敏感字段

本项目中的敏感字段主要包括：

- 身份标识：`user_id`、姓名 / 昵称、邮箱、手机号
- 人口学信息：出生年份、年龄、性别、地址
- 健康数据：血糖、血脂、体重、体脂、心率、步数等原始值与异常状态
- 健康事件时间：采样日期、测量时间、导入时间
- 自由文本：备注、说明、医生意见、运动上下文
- 文件元数据：来源文件名、路径、导入任务标识

## 导入文件存储策略

当前策略：

1. 导入后只在 `metric_record` 中保存标准化指标，不保存完整原文件内容。
2. `import_task.source_file` 只保存文件名基线信息，不保存完整本地路径。
3. `import_row_log.raw_payload_json` 沿用旧列名，但当前只保存脱敏字段标签，或在关闭审计模式时保存统一占位摘要。
4. 新迁移会清理旧版 `import_row_log` 中可能残留的原始 payload。
5. 默认不在前端 API 中直接返回原始导入 payload。
6. `.sqlite` 数据文件与 `.env.local` 均加入 `.gitignore`。

## 错误与日志

当前约束：

1. API 统一返回安全错误消息，不暴露底层异常细节，并返回独立错误 ID。
2. 服务端错误日志仅记录安全上下文、错误类型和时间，不打印原始导入值、LLM key 或自由文本备注。
3. 占位隐私接口不返回真实数据，只返回能力边界、请求作用域和本地数据规模摘要。
4. demo / inspect 脚本默认输出聚合信息，不再打印原始导入 payload、完整文件路径或健康指标明文样本。

## 环境变量管理

建议使用：

- `.env.local`
- `.env.example`

当前预留：

- `HEALTH_LLM_PROVIDER`
- `HEALTH_LLM_MODEL`
- `HEALTH_LLM_BASE_URL`
- `HEALTH_LLM_API_KEY`
- `HEALTH_IMPORT_AUDIT_MODE`
- `HEALTH_ALLOW_LOCAL_EXPORTS`
- `HEALTH_ALLOW_LOCAL_DELETE`
- `HEALTH_LOG_LEVEL`

推荐本地策略：

1. 把密钥只写在 `.env.local`，不要放进脚本或命令历史。
2. 默认保持 `HEALTH_IMPORT_AUDIT_MODE=redacted`；如果本机属于更严格场景，可改为 `disabled`。
3. 在真正实现导出 / 删除前，保持 `HEALTH_ALLOW_LOCAL_EXPORTS=0` 与 `HEALTH_ALLOW_LOCAL_DELETE=0`。
4. `HEALTH_LOG_LEVEL=error` 即可，避免开发时产生冗余敏感上下文。

## 接口占位

已预留：

- `POST /api/privacy/export`
- `POST /api/privacy/delete`

后续可扩展为：

- 导出结构化指标
- 导出报告快照
- 按数据源删除
- 按导入任务删除
- 按用户全量删除

当前占位请求示例：

```json
{
  "scope": "imports",
  "format": "json",
  "includeAuditLogs": false
}
```

```json
{
  "scope": "imports",
  "importTaskId": "import-task::...",
  "confirm": false
}
```
