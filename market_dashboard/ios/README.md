# Portfolio Workbench iOS

这个目录放的是个人投资系统的独立 iPhone 客户端源码。

原则：

- Web 与 iOS 的界面代码完全分开。
- 底层分析、结单解析、上传替换逻辑继续复用 `market_dashboard/` 的 Python 服务层。
- iOS 端只做移动端交互、信息压缩、单票下钻和文件选择上传。

## 目录

- `PortfolioWorkbenchMobileCore/`
  - Swift models、API client、multipart 上传封装。
  - 可以单独跑 `swift test`。
- `PortfolioWorkbenchIOS/`
  - SwiftUI iPhone 界面源码。
  - 四个 tab: `总览`、`持仓`、`账户`、`设置`。
- `project.yml`
  - XcodeGen 工程定义，用于本地生成 `.xcodeproj`。

## 生成工程

```bash
cd market_dashboard/ios
brew install xcodegen
xcodegen generate
open PortfolioWorkbenchIOS.xcodeproj
```

## 启动后端

```bash
cd market_dashboard
python3 app.py
```

默认 Web / iOS 共用同一个本地服务：`http://127.0.0.1:8008`

如果要直接在手机浏览器里打开，或给真机 iPhone 提供后端服务，推荐这样启动：

```bash
cd market_dashboard
./scripts/start_on_phone.sh
```

它会把服务绑定到 `0.0.0.0`，并打印当前 Mac 的局域网访问地址。

真机联调时，在 iOS 的设置页填写运行 Python 服务那台 Mac 的局域网地址，例如：

```text
http://192.168.1.10:8008/
```

## 当前移动端接口

- `GET /api/mobile/dashboard`
- `GET /api/mobile/stock-detail?symbol=...`
- `POST /api/mobile/upload-statement`

这些接口都只是移动端适配层，核心分析仍然来自 `portfolio_analytics.py`。

## 个人手机最简安装方案

如果你只是想装到自己的 iPhone 上，不需要对外发布，最简单的是：

1. 在 Xcode 里登录你的 Apple ID  
   `Xcode > Settings > Accounts`
2. 用 USB 连上 iPhone，并在手机上点 `信任`
3. 如果系统提示，打开 iPhone 的 `Developer Mode`
4. 跑预检：

```bash
cd market_dashboard/ios
./scripts/ios_preflight.sh
```

5. 在 Xcode 登录你的 Apple ID 后，拿到你的 `TEAM_ID`，直接安装：

```bash
cd market_dashboard/ios
./scripts/install_on_personal_iphone.sh
```

说明：

- 这条路径不需要 App Store，也不需要 TestFlight。
- 脚本默认会使用 `project.yml` 中配置好的 `DEVELOPMENT_TEAM`；如果你想临时覆盖，仍然可以传 `TEAM_ID=你的TeamID`。
- 脚本会自动尝试发现当前 Mac 的局域网地址，并把它写入 App 的默认服务地址。
- 如果你想手动指定，也可以传 `SERVER_URL=http://你的局域网IP:8008/`。
- 如果你用的是免费的 Personal Team，App 一般需要定期重新签名安装。
- 如果你是付费 Apple Developer，安装稳定性会更好，也更适合后续 Archive / TestFlight。
- 如果脚本提示 `No Xcode Apple account configured.`，说明当前 Mac 上的 Xcode 还没登录 Apple ID，这一步必须先在 Xcode 里完成。

## 模拟器安装

如果你只是想先把 iOS 客户端跑起来，不等真机签名，可以直接装到模拟器：

```bash
cd market_dashboard/ios
./scripts/install_on_simulator.sh
```

说明：

- 模拟器默认写入 `http://127.0.0.1:8008/`，适合和本机 Python 服务直接联调。
- 如果你想指定其他地址，也可以传 `SERVER_URL=http://.../`。
