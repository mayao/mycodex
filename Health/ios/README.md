# Vital Command iOS

这个目录放的是独立的 iOS 客户端源码，和 Web 前端分开维护，但继续复用 `Health/` 现有后端 API 与 SQLite 驱动的服务层。

## 目录

- `VitalCommandMobileCore/`
  - 可复用的移动端模型、网络客户端、multipart 上传封装。
  - 可以单独跑 `swift test`。
- `VitalCommandIOS/`
  - SwiftUI iPhone 界面源码。
  - 采用四个 tab: 总览、趋势、报告、数据。
- `project.yml`
  - XcodeGen 工程规格文件，用于生成本地 Xcode 工程。

## 生成工程

先确保本机装了完整 Xcode，然后执行：

```bash
cd Health/ios
brew install xcodegen
xcodegen generate
open VitalCommandIOS.xcodeproj
```

## 服务连接

真机连接开发环境时，`Settings` 里不要填 `localhost`，应填写运行 Next.js 服务的电脑局域网 IP，例如：

```text
http://192.168.1.10:3000/
```

建议直接用局域网模式启动后端：

```bash
cd Health
npm run dev:lan
```

## 当前共享边界

- 共享能力: `src/server/services`、`src/server/repositories`、SQLite 数据、现有 Route Handlers。
- 独立移动端代码: `ios/VitalCommandIOS/`
- 共享移动端适配层: `ios/VitalCommandMobileCore/`

详细说明见 [ios-client-architecture.md](/Users/xmly/Library/Mobile%20Documents/com~apple~CloudDocs/MyCodex/Health/docs/ios-client-architecture.md)。
