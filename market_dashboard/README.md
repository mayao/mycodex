# Personal Portfolio Workbench

## Features
- Reads your real broker statements from Tiger, Interactive Brokers, Futu, and Longbridge.
- Aggregates true holdings, recent trades, financing pressure, and derivative / FCN exposure across accounts.
- Shows portfolio views by broker, market, and investment theme.
- Adds a deeper Chinese strategy brief oriented around real position sizing, concentration, leverage, and execution discipline.
- Adds a more detailed single-stock fundamental layer covering business model, earnings drivers, valuation anchors, catalysts, and risk points.
- Supports uploading a fresh statement from the UI to replace a monitored account source without editing Python config.
- Uses file-signature caching, so replacing a statement file and clicking refresh is enough to rebuild the dashboard.
- Provides an offline `--check` path that validates the local portfolio payload without depending on external market APIs.

## Run
```bash
cd market_dashboard
python3 app.py
```

Open: `http://127.0.0.1:8008`

说明：

- 如果本机默认结单 PDF 不在了，服务会优先回退到已有缓存快照。
- 如果既没有本地结单、也没有缓存或上传记录，工作台会以空态启动，等待首次导入。

## Show On Phone
```bash
cd market_dashboard
./scripts/start_on_phone.sh
```

默认会把服务绑定到局域网并打印手机可访问地址。也可以直接运行：

```bash
python3 app.py --public
```

## Configure Server-Side AI Keys

如果你希望 API Key 跟着项目服务文件走，而不是每台服务器单独配环境变量，可以直接写项目内配置文件：

```bash
cd market_dashboard
python3 scripts/configure_ai_service.py
```

说明：

- 实际配置文件默认写到 `market_dashboard/config/service_ai_config.json`
- 文件会被后端自动读取，App 端可以只负责切换 provider 和模型 ID
- Kimi 支持两种预设：
  - `moonshot`：`https://api.moonshot.cn/v1` + `moonshot-v1-8k`
  - `kimi_coding`：`https://api.kimi.com/coding/v1` + `kimi-for-coding`
- 为了避免误提交，真实配置文件已加入 `.gitignore`
- 仓库里保留了示例文件：`market_dashboard/config/service_ai_config.example.json`

## Deploy Elsewhere

如果后续要给其他机器、真机或者云端环境使用，这个 Python 后端需要单独运行和部署。

最小部署说明见 [docs/deployment.md](docs/deployment.md)。

## Validate
```bash
cd market_dashboard
python3 app.py --check
```

## iPhone Client

仓库里已经新增独立的 iOS 客户端源码：

```bash
cd market_dashboard/ios
```

特点：

- Web 与 iOS UI 分开维护
- 后端分析与结单上传能力继续共用 `market_dashboard/` Python 服务
- 移动端接口：
  - `GET /api/mobile/dashboard`
  - `GET /api/mobile/stock-detail?symbol=...`
  - `POST /api/mobile/upload-statement`

工程说明见 [ios/README.md](ios/README.md)。

如果你要直接安装 iOS 客户端：

- 真机安装前，先在 Xcode 登录 Apple ID，然后运行 `TEAM_ID=你的TeamID ./scripts/install_on_personal_iphone.sh`
- 如果只是先在本机完成安装联调，直接运行 `./scripts/install_on_simulator.sh`

## Update workflow
1. Open the page and use `上传新结单` to replace the PDF for a specific account.
2. The dashboard writes the uploaded file into `market_dashboard/uploads/` and immediately rebuilds the statement cache.
3. Keep using `刷新行情与宏观` when you want to pull the latest price, trend, and macro summaries from external APIs and news search.
