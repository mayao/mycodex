# iOS 客户端架构

## 目标

在不复制业务逻辑的前提下新增 iPhone 客户端：

- Web 与 iOS 的 UI 代码完全分开。
- 底层能力继续复用当前 `Health/` 后端服务、仓库层和 SQLite 数据。
- 手机端只做移动交互编排、展示压缩和文件选取。

## 代码分层

### 1. 共享能力层

仍然使用现有 Node / Next.js 工程：

- `src/server/services/health-home-service.ts`
- `src/server/services/report-service.ts`
- `src/server/importers/*`
- `src/server/privacy/privacy-service.ts`
- `src/server/repositories/*`
- `src/server/db/*`
- `src/app/api/*`

这层仍然是唯一的数据聚合与规则生成入口。

### 2. 移动端共享适配层

`ios/VitalCommandMobileCore/`

职责：

- 定义与后端 JSON 对齐的 Swift 模型
- 封装 `GET /api/dashboard`
- 封装 `GET /api/reports`
- 封装 `GET /api/reports/[snapshotId]`
- 封装 `POST /api/imports`
- 兼容 `POST /api/privacy/export` 和 `POST /api/privacy/delete` 当前的 `501 placeholder` 响应

### 3. iOS 界面层

`ios/VitalCommandIOS/`

按手机端场景拆分：

- `Home`
  - 聚合总览文案、关键指标、来源状态、当前提醒、最近报告
- `Trends`
  - 独立展示血脂、体成分、运动、恢复趋势
- `Reports`
  - 周报 / 月报切换与详情页
- `DataHub`
  - 文件导入、隐私导出占位、隐私删除占位
- `Settings`
  - 服务地址配置

## 为什么这样拆

### 保持能力一致

如果把规则分析、报告生成、导入标准化再在 Swift 里重写一份，会直接造成双实现漂移。当前方案把这些能力继续保留在 TypeScript 服务层，iOS 只消费已经结构化好的 API 数据。

### 保持 UI 独立

Web 端的多列 dashboard、宽屏图表和大段说明不适合手机端。iOS 客户端用了以下调整：

- 首页只保留最高频信息，改成卡片流
- 趋势图拆到单独 tab
- 报告切成列表页 + 详情页
- 上传、导出、删除集中到数据页
- 设置页单独处理服务地址和真机联调提示

## 数据流

### 首页

1. iOS 调 `GET /api/dashboard`
2. Next.js route 调 `getHealthHomePageData()`
3. service 聚合 overview、trend、latest report、import options
4. iOS 渲染为总览卡片和提醒列表

### 报告

1. iOS 调 `GET /api/reports`
2. 选择某条记录后调 `GET /api/reports/[snapshotId]`
3. iOS 进入详情页展示摘要和结构化 insights

### 导入

1. 用户在 iPhone 上通过 `fileImporter` 选择文件
2. iOS 组装 multipart 表单发到 `POST /api/imports`
3. 后端复用现有 importer registry、reader、standardization 流程
4. iOS 显示导入任务结果和失败数量

## 运行要求

### 本地后端

继续沿用现有 Web 启动方式：

```bash
cd Health
npm install
npm run dev
```

### iOS 客户端

需要完整 Xcode。当前仓库里提供的是 Swift 源码和 `project.yml`，可以通过 XcodeGen 生成工程。

## 当前限制

- 这个仓库环境没有完整 Xcode，所以本次未做 iOS UI 编译验证。
- 真机连开发机需要手动填写 Mac 的局域网地址。
- 隐私导出 / 删除在后端仍是 placeholder，iOS 端已兼容但不会真正执行导出或删除。
