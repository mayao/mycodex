# MyCodex

本地工作目录：`~/Projects/MyCodex`

## 子项目

### market_dashboard — 个人投资组合工作台
- 后端：Python 3，入口 `market_dashboard/app.py`
- 启动：`cd market_dashboard && python3 app.py`（默认 http://127.0.0.1:8008）
- 局域网/手机访问：`python3 app.py --public` 或 `./scripts/start_on_phone.sh`
- 结单来源配置：`market_dashboard/statement_sources.py`
- 已上传结单清单：`market_dashboard/uploaded_statement_sources.json`
- 后台服务 plist：`market_dashboard/scripts/com.mycodex.invest-backend.plist`

### Health — 健康数据追踪
- 前端：Next.js，入口 `Health/`
- 启动：`cd Health && npm install && npm run dev`（默认 http://localhost:3000）
- iOS 客户端：`Health/ios/`

## 路径约定
- 项目根：`/Users/xmly/Projects/MyCodex`
- 外部投资结单 PDF（不在本仓库）：`~/Library/Mobile Documents/com~apple~CloudDocs/科技平权-投资/`
  这些文件仍在 iCloud，`statement_sources.py` 中的默认路径保持不变。

## Claude Code 安装
```bash
npm install -g @anthropic-ai/claude-code
```
