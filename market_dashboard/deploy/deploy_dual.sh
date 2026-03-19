#!/bin/bash
set -euo pipefail

# ============================================================
# Portfolio Workbench 双机部署脚本
# - 本机：重启本地后台服务（默认 10.8.x.x:8008）
# - 远端：通过 deploy.sh 发布到指定主机（默认 10.8.144.16:8008）
#
# 用法:
#   ./deploy/deploy_dual.sh
#   ./deploy/deploy_dual.sh Apple@10.8.144.16
# ============================================================

REMOTE_TARGET=${1:-"Apple@10.8.144.16"}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════╗"
echo "║   Portfolio Workbench 双机部署           ║"
echo "║   本机 + 远端: $REMOTE_TARGET"
echo "╚══════════════════════════════════════════╝"
echo ""

echo "▶ [1/2] 重启本机服务..."
"$PROJECT_DIR/scripts/restart_background_service.sh"

echo ""
echo "▶ [2/2] 部署远端服务..."
"$SCRIPT_DIR/deploy.sh" "$REMOTE_TARGET"

echo ""
echo "✅ 双机部署完成"
