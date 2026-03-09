# 个人健康管理和经营系统

一个面向单用户、local-first 的健康数据管理与经营系统原型。当前版本已经覆盖：

- 统一数据导入与标准化
- 规则驱动的结构化分析层
- 基于结构化 insights 的 LLM 洞察层
- dashboard 首页
- 周报 / 月报页面与 `report_snapshot` 落库
- 隐私、安全与接口占位

> 非医疗诊断：本项目输出仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断，不给出处方药建议。

## 当前能力

### 阶段 3: 导入与标准化

支持：

- 体检 Excel / CSV
- 血液检查 Excel / CSV
- 体脂秤 CSV
- 运动 CSV

能力：

- 字段映射层
- 单位标准化
- 异常标记
- 导入任务日志
- 失败行追踪

参考文档：

- [docs/import-standardization.md](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/docs/import-standardization.md)

### 阶段 4: 规则分析引擎

规则层只读取标准化后的统一指标，不直接读取原始表格。当前支持：

- 趋势分析
- 异常分析
- 联动观察
- 结构化 insights JSON 输出

参考文档：

- [docs/rule-analysis-engine.md](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/docs/rule-analysis-engine.md)

### 阶段 5: LLM 洞察层

LLM 输入只来自结构化 insights。当前支持：

- 日摘要
- 周报
- 月报
- Prompt 模板保留
- Mock provider
- OpenAI-compatible 接口占位

参考文档：

- [docs/llm-summary-layer.md](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/docs/llm-summary-layer.md)

### 阶段 6 / 7: 首页与报告页

首页包含：

- 健康总览卡片
- 本期关键提醒
- 血脂趋势图
- 体重 / 体脂趋势图
- 运动趋势图
- 待关注事项
- 最新健康洞察

报告页包含：

- 周报历史
- 月报历史
- 报告详情页
- `report_snapshot` 存储

### 阶段 8: 隐私与安全

当前已加入：

- 敏感字段识别与导入审计脱敏
- 环境变量方案
- 安全错误响应与安全日志
- 数据导出 / 删除接口占位
- `.env.local` / SQLite 忽略规则

参考文档：

- [docs/privacy-security.md](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/docs/privacy-security.md)

## 技术栈

| 层 | 选型 | 说明 |
| --- | --- | --- |
| 前端 | Next.js App Router + React 19 + TypeScript | 页面、API、服务层在一个工程里收敛 |
| 后端 | Server Components + Route Handlers | 先保持单体结构，降低复杂度 |
| 数据库 | SQLite（`node:sqlite`） | 本地优先，默认不出本机 |
| 图表 | Recharts | 承载趋势图与后续报表 |
| 测试 | Node test runner + `tsx` | 适合规则层与服务层 |
| 校验 | Zod | 用于 LLM 输出与环境变量校验 |

## 目录结构

```text
.
├── data/                          # 本地 SQLite 文件
├── docs/                          # 导入、规则、LLM、隐私文档
├── migrations/                    # 统一健康 schema 迁移
├── samples/import/                # 导入样例与模板
├── scripts/                       # 数据库检查、导入演示等脚本
└── src/
    ├── app/                       # 首页、报告页和 API 路由
    ├── components/                # dashboard / report 组件
    └── server/
        ├── config/                # 环境变量
        ├── db/                    # schema / seed / sqlite 初始化
        ├── domain/                # 页面与摘要类型
        ├── importers/             # 导入器、映射、日志
        ├── insights/              # 规则分析引擎
        ├── llm/                   # prompt 模板与 provider
        ├── repositories/          # 统一数据查询
        └── services/              # 首页、报告和摘要聚合服务
```

## 本地运行

### 环境要求

- Node.js 22.x LTS
- npm 10+
- 运行环境支持 `node:sqlite`

说明：

- 当前项目已验证 `Node 22`。
- 在 macOS 上直接使用 `Node 25` 启动 `Next.js` / `ESLint`，可能会因为读取 `/proc/self/cgroup` 出现 `EPERM`，导致服务无法启动。
- 仓库根目录提供了 `.nvmrc`，可直接切到 22 版本。

### 安装

```bash
npm install
```

如果本机通过 Homebrew 安装了 `node@22`，也可以直接这样运行：

```bash
PATH="/opt/homebrew/opt/node@22/bin:$PATH" npm install
```

### 启动开发环境

```bash
npm run dev
```

如果当前默认 `node` 不是 22.x，请显式指定：

```bash
PATH="/opt/homebrew/opt/node@22/bin:$PATH" npm run dev
```

打开 [http://localhost:3000](http://localhost:3000)。

首次运行会自动：

1. 创建 `data/health-system.sqlite`
2. 初始化 legacy schema
3. 注入 mock 数据
4. 执行 unified schema 迁移

## 常用命令

```bash
npm run dev
npm run lint
npm run typecheck
npm run test
npm run build
npm run db:inspect
npm run import:demo
```

## LLM 配置

默认：

- `HEALTH_LLM_PROVIDER=mock`

可切换到 OpenAI-compatible：

```bash
HEALTH_LLM_PROVIDER=openai-compatible
HEALTH_LLM_BASE_URL=https://api.openai.com/v1
HEALTH_LLM_MODEL=gpt-4.1-mini
HEALTH_LLM_API_KEY=...
```

`.env.example` 已提供字段模板。

隐私相关环境变量：

```bash
HEALTH_IMPORT_AUDIT_MODE=redacted
HEALTH_ALLOW_LOCAL_EXPORTS=0
HEALTH_ALLOW_LOCAL_DELETE=0
HEALTH_LOG_LEVEL=error
```

## 样例数据

导入样例：

- [samples/import/annual_exam_sample.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/annual_exam_sample.csv)
- [samples/import/blood_test_sample.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/blood_test_sample.csv)
- [samples/import/body_scale_sample.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/body_scale_sample.csv)
- [samples/import/activity_sample.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/activity_sample.csv)
- [samples/import/activity_invalid_sample.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/activity_invalid_sample.csv)

导入模板：

- [samples/import/templates/annual_exam_template.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/templates/annual_exam_template.csv)
- [samples/import/templates/blood_test_template.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/templates/blood_test_template.csv)
- [samples/import/templates/body_scale_template.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/templates/body_scale_template.csv)
- [samples/import/templates/activity_template.csv](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/samples/import/templates/activity_template.csv)

## 隐私与安全

- SQLite 文件默认只保存在本地 `data/` 目录。
- 导入文件内容不直接入库；仅保存结构化指标、任务元数据和脱敏后的导入审计摘要。
- `import_row_log.raw_payload_json` 为兼容旧表结构保留，但当前只保存脱敏标签或关闭审计后的统一占位。
- 默认前端 API 不直接返回原始导入 payload。
- API 错误响应已做安全收口，不直接回传底层异常；服务端日志只记录安全上下文和错误 ID。
- 历史导入行日志会通过迁移清理旧版原始 payload。
- 已预留导出和删除接口：
  - `POST /api/privacy/export`
  - `POST /api/privacy/delete`

## 当前仍未接入

- PDF / OCR 直接导入
- Apple Health XML
- Garmin / Strava 原始导出
- 真实 LLM 线上联调验证
- PDF 报告导出
