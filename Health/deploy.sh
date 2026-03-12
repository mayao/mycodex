#!/bin/bash
set -e

# ============================================================
# Vital Command — 一键部署脚本
# 用法:
#   方式1 (直接运行):  bash deploy.sh
#   方式2 (Docker):    bash deploy.sh docker
# ============================================================

MODE=${1:-direct}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="/tmp/health-deploy"

echo "📦 正在构建项目..."
cd "$SCRIPT_DIR"
npm run build

echo "📁 正在打包 standalone 输出..."
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"
cp -R .next/standalone/* "$DEPLOY_DIR/"
mkdir -p "$DEPLOY_DIR/.next/static"
cp -R .next/static/* "$DEPLOY_DIR/.next/static/"
[ -d public ] && cp -R public "$DEPLOY_DIR/public"
cp -R migrations "$DEPLOY_DIR/migrations"
mkdir -p "$DEPLOY_DIR/data"

if [ "$MODE" = "docker" ]; then
  echo "🐳 正在构建 Docker 镜像..."
  docker build -t vital-command:latest .
  echo ""
  echo "✅ Docker 镜像已就绪！启动方式:"
  echo ""
  echo "  docker run -d \\"
  echo "    --name vital-command \\"
  echo "    --restart unless-stopped \\"
  echo "    -p 3000:3000 \\"
  echo "    -v vital-command-data:/app/data \\"
  echo "    -e HEALTH_AUTH_ENABLED=true \\"
  echo "    -e HEALTH_JWT_SECRET=your-secret-at-least-16-chars \\"
  echo "    -e HEALTH_LLM_PROVIDER=anthropic \\"
  echo "    -e HEALTH_LLM_API_KEY=your-api-key \\"
  echo "    vital-command:latest"
  echo ""
  echo "  推送到云端:"
  echo "    docker tag vital-command:latest your-registry/vital-command:latest"
  echo "    docker push your-registry/vital-command:latest"
else
  # 打包成 tar.gz 方便传输
  echo "📦 正在打包为 tar.gz..."
  cd /tmp
  tar -czf vital-command-deploy.tar.gz -C health-deploy .
  SIZE=$(du -h /tmp/vital-command-deploy.tar.gz | awk '{print $1}')
  echo ""
  echo "✅ 部署包已就绪: /tmp/vital-command-deploy.tar.gz ($SIZE)"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "在目标机器上部署:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  # 1. 传输到目标机器"
  echo "  scp /tmp/vital-command-deploy.tar.gz user@server:/opt/"
  echo ""
  echo "  # 2. 在目标机器上解压"
  echo "  ssh user@server"
  echo "  mkdir -p /opt/vital-command && cd /opt/vital-command"
  echo "  tar -xzf /opt/vital-command-deploy.tar.gz"
  echo ""
  echo "  # 3. 创建 .env 配置"
  echo "  cat > .env << EOF"
  echo "HEALTH_AUTH_ENABLED=true"
  echo "HEALTH_JWT_SECRET=your-secret-at-least-16-chars"
  echo "HEALTH_LLM_PROVIDER=anthropic"
  echo "HEALTH_LLM_MODEL=claude-sonnet-4-20250514"
  echo "HEALTH_LLM_API_KEY=your-api-key"
  echo "EOF"
  echo ""
  echo "  # 4. 安装 Node.js 22+ 并启动"
  echo "  node server.js"
  echo ""
fi
