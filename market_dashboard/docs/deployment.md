# MyInvAI / Portfolio Workbench 部署说明

## 结论

如果后续要在其他机器或者云端提供给 iPhone App 使用，当前的 Python 后端需要单独运行并对外提供 HTTP 服务。

原因：

- iOS 客户端只负责 UI 和上传交互。
- 持仓聚合、结单解析、移动端 payload 适配、AI 对话上下文都在 `market_dashboard/` 服务里。
- App 当前依赖这些接口：
  - `GET /api/mobile/dashboard`
  - `GET /api/mobile/dashboard-ai`
  - `GET /api/mobile/stock-detail`
  - `GET /api/mobile/stock-detail-ai`
  - `GET /api/mobile/import-center`
  - `POST /api/mobile/upload-statement`
  - `POST /api/mobile/ai-chat`

所以：

- 同一台 Mac 本地联调：可以直接源码运行，不一定要打包。
- 换到其他机器：推荐至少容器化，避免依赖路径和 Python 环境漂移。
- 上云：需要把后端作为独立服务部署，并为持久化文件准备卷或对象存储。

## 当前后端的状态边界

- 已支持“默认 owner 结单文件缺失时自动降级”。
- 如果本机旧缓存还在，会回退到缓存快照。
- 如果既没有默认结单，也没有缓存或上传数据，服务会正常启动，但 owner 工作台会显示首屏空态，等待首次导入。
- `POST /api/mobile/auth/dev/owner` 只允许当前 Mac 的回环地址访问，不能当成云端正式登录方案。

## 推荐部署方案

### 方案 A：另一台 Mac / Linux 机器直跑源码

适合：

- 内网使用
- 临时演示
- 单人维护

启动：

```bash
cd market_dashboard
python3 app.py --host 0.0.0.0 --port 8008
```

iPhone / iOS 设置页里填：

```text
http://你的服务器IP:8008/
```

要求：

- 该机器能运行 Python 3。
- `market_dashboard/.deps` 目录随代码一起带过去。
- 要持久化 `uploads/`、`cache/`、`user_store.json`、`uploaded_statement_sources.json`。

### 方案 B：Docker 容器部署

适合：

- 其他开发机
- NAS
- 云主机
- 后续接入反向代理、TLS、域名

构建镜像：

```bash
cd market_dashboard
docker build -t myinvai-backend .
```

运行容器：

```bash
docker run -d \
  --name myinvai-backend \
  -p 8008:8008 \
  -v "$(pwd)/uploads:/app/uploads" \
  -v "$(pwd)/cache:/app/cache" \
  -v "$(pwd)/user_store.json:/app/user_store.json" \
  -v "$(pwd)/uploaded_statement_sources.json:/app/uploaded_statement_sources.json" \
  myinvai-backend
```

说明：

- `uploads/` 保存用户上传 PDF。
- `cache/` 保存 statement fallback 和中间缓存。
- `user_store.json` 保存手机号/微信开发态用户与 session。
- `uploaded_statement_sources.json` 保存“哪个用户的哪个账户当前绑定哪份上传结单”。

如果这些不持久化，容器重启后用户会话和导入记录会丢失。

### 方案 C：云端正式服务

推荐拓扑：

1. 一个容器化 Python API 服务
2. 一个反向代理或 LB
3. HTTPS 域名
4. 持久化卷或对象存储

建议：

- 先把 `uploads/` 和 `cache/` 迁到持久卷。
- 如果后续多实例部署，再把 `user_store.json` / `uploaded_statement_sources.json` 迁到数据库。
- 真正上线前，把手机号验证码、微信 OAuth、token 存储改成正式实现。

## iOS 端如何切换环境

当前 iOS 客户端已经支持按服务地址切换环境。

本地模拟器：

```text
http://127.0.0.1:8008/
```

同局域网真机：

```text
http://你的Mac局域网IP:8008/
```

云端：

```text
https://api.your-domain.com/
```

## 现在是否必须打包部署后端

分情况：

- 只在当前这台 Mac 上开发和看模拟器：不必须，直接 `python3 app.py` 就够。
- 要让别的机器、真机、或云端环境访问：需要。至少要把当前后端作为一个独立可运行服务带过去。
- 要对外长期提供能力：建议直接走容器化部署，而不是要求每台机器手工装 Python 环境。

## 后续建议

按优先级：

1. 先保持当前文件型存储，但用 Docker 固化运行环境。
2. 为 `uploads/` 和 `cache/` 配置稳定的持久卷。
3. 再把用户、session、上传映射迁到数据库。
4. 最后再补正式短信、微信 OAuth、券商 token 托管和自动同步任务。
