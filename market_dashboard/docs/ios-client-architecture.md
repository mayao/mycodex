# iOS 客户端架构

## 目标

为个人投资系统新增独立 iPhone 客户端，同时保持：

- Web 与 iOS 的 UI 代码彻底分离。
- 结单解析、组合聚合、个股研究、上传替换仍由 Python 服务层统一产出。
- 手机端做适配，不做第二套分析引擎。

## 分层

### 1. 共享能力层

继续使用现有 `market_dashboard/` 后端：

- `statement_parser.py`
- `portfolio_analytics.py`
- `statement_sources.py`
- `market_context.py`
- `app.py`

这是唯一的数据和分析真相源。

### 2. 移动端适配层

新增：

- `mobile_api.py`
- `/api/mobile/dashboard`
- `/api/mobile/stock-detail`
- `/api/mobile/upload-statement`

职责：

- 把桌面端宽屏 payload 压缩成适合手机的信息层级
- 保留账户、持仓、风险、动作、上传等核心能力
- 不复制分析逻辑，只重组展示模型

### 3. iOS shared core

`ios/PortfolioWorkbenchMobileCore/`

职责：

- Swift models 对齐移动端 JSON
- `PortfolioWorkbenchAPIClient`
- multipart 上传表单构造
- 单独可测试

### 4. iOS UI 层

`ios/PortfolioWorkbenchIOS/`

四个主要场景：

- `总览`
  - 净资产、集中度、风险旗标、动作中心、宏观主题、头部持仓
- `持仓`
  - 搜索、排序、持仓卡片、个股详情下钻
- `账户`
  - 券商账户、结单接入状态、PDF 上传替换、最近交易、衍生品敞口
- `设置`
  - 服务地址、移动端边界、参考资料

## 视觉方向

参考了 IBKR、长桥、富途、老虎这类券商移动端的共性：

- 单列高密度卡片流
- 快速识别的状态 badge
- 账户 / 持仓 / 风险分区清晰
- 把复杂表格改写成手机可扫读的分层信息块

同时保留当前工作台已有的深色 command-center 语言：

- 深海军蓝背景
- 青色 / 青绿色为主强调色
- 金色做关注项
- 红色做风险提示

## 当前限制

- 这个仓库环境未必带完整 Xcode，因此 SwiftUI 真机/模拟器视觉验证可能需要你本机执行。
- 已完成 shared core 测试与服务侧 payload 适配，但完整 iOS app 编译依赖 XcodeGen + Xcode。
- 当前仍然依赖本地 Python 服务运行，不是纯离线本地数据库 App。
