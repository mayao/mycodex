#!/bin/bash
set -euo pipefail

# ============================================================
# Portfolio Workbench 一键部署脚本
# 用法: ./deploy/deploy.sh [user@host]
# 示例: ./deploy/deploy.sh Apple@10.8.144.16
# ============================================================

TARGET=${1:-"Apple@10.8.144.16"}
PREFERRED_REMOTE_DIR="/opt/portfolio-workbench"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "╔══════════════════════════════════════════╗"
echo "║   Portfolio Workbench 一键部署           ║"
echo "║   目标: $TARGET"
echo "╚══════════════════════════════════════════╝"
echo ""

# ---- Step 1: Test SSH ----
echo "▶ [1/5] 测试 SSH 连接..."
ssh -o ConnectTimeout=5 -o BatchMode=yes "$TARGET" "echo '  ✅ SSH 连接成功'" 2>/dev/null || {
    echo "  ❌ 无法连接到 $TARGET"
    echo "  请确保："
    echo "    1. 目标机已开机且网络可达"
    echo "    2. 已配置 SSH 密钥（ssh-copy-id $TARGET）"
    echo "    3. 目标机已安装 Python 3.9+"
    exit 1
}

REMOTE_HOME="$(ssh "$TARGET" 'printf %s "$HOME"')"
FALLBACK_REMOTE_DIR="$REMOTE_HOME/Projects/MyCodex/market_dashboard"
DEPLOY_MODE="systemd"
REMOTE_DIR="$PREFERRED_REMOTE_DIR"
if ! ssh "$TARGET" "sudo -n true >/dev/null 2>&1"; then
    DEPLOY_MODE="user"
    REMOTE_DIR="$FALLBACK_REMOTE_DIR"
fi

echo "  ✅ 部署模式: $DEPLOY_MODE"
echo "  ✅ 远端目录: $REMOTE_DIR"

# ---- Step 2: Setup remote directory ----
echo ""
echo "▶ [2/5] 初始化远程目录..."
if [ "$DEPLOY_MODE" = "systemd" ]; then
    ssh "$TARGET" "sudo mkdir -p $REMOTE_DIR/uploads $REMOTE_DIR/cache $REMOTE_DIR/output $REMOTE_DIR/config \
        && sudo chown -R \$(whoami) $REMOTE_DIR"
else
    ssh "$TARGET" "mkdir -p $REMOTE_DIR/uploads $REMOTE_DIR/cache $REMOTE_DIR/output $REMOTE_DIR/config"
fi
echo "  ✅ 目录就绪"

# ---- Step 3: Sync source files ----
echo ""
echo "▶ [3/5] 同步源文件到远程..."
rsync -az --delete \
    --exclude='uploads/' \
    --exclude='cache/' \
    --exclude='output/' \
    --exclude='daily_analysis_cache.json' \
    --exclude='statement_cache.json' \
    --exclude='user_store.json' \
    --exclude='uploaded_statement_sources.json' \
    --exclude='config/service_ai_config.json' \
    --exclude='config/service_ai_config.local.json' \
    --exclude='ios/' \
    --exclude='.deps/pypdfium2_raw/' \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    --exclude='.git/' \
    "$PROJECT_DIR/" "$TARGET:$REMOTE_DIR/"
echo "  ✅ 源文件同步完成"

# ---- Step 4: Sync AI config (keys stay local, deploy as config.json) ----
echo ""
echo "▶ [4/5] 同步 AI 配置..."
AI_CONFIG_SRC=""
if [ -f "$PROJECT_DIR/config/service_ai_config.local.json" ]; then
    AI_CONFIG_SRC="$PROJECT_DIR/config/service_ai_config.local.json"
elif [ -f "$PROJECT_DIR/config/service_ai_config.json" ]; then
    AI_CONFIG_SRC="$PROJECT_DIR/config/service_ai_config.json"
fi

if [ -n "$AI_CONFIG_SRC" ]; then
    if [ "$DEPLOY_MODE" = "systemd" ]; then
        rsync -az "$AI_CONFIG_SRC" "$TARGET:$REMOTE_DIR/config/service_ai_config.json"
        ssh "$TARGET" "chmod 600 $REMOTE_DIR/config/service_ai_config.json"
    else
        rsync -az "$AI_CONFIG_SRC" "$TARGET:$REMOTE_DIR/config/service_ai_config.local.json"
        ssh "$TARGET" "chmod 600 $REMOTE_DIR/config/service_ai_config.local.json"
    fi
    echo "  ✅ AI 配置已同步"
else
    echo "  ⚠ 未找到 AI 配置文件，跳过（服务将以 mock 模式运行）"
fi

# ---- Step 5: Restart service ----
echo ""
echo "▶ [5/5] 重启远端服务..."
if [ "$DEPLOY_MODE" = "systemd" ]; then
    ssh "$TARGET" "sudo cp /dev/stdin /etc/systemd/system/portfolio-workbench.service" \
        < "$SCRIPT_DIR/portfolio-workbench.service"
    ssh "$TARGET" "sudo systemctl daemon-reload \
        && sudo systemctl enable portfolio-workbench \
        && sudo systemctl restart portfolio-workbench \
        && sleep 2 \
        && sudo systemctl status portfolio-workbench --no-pager -l"
else
    ssh "$TARGET" "cd $REMOTE_DIR && ./scripts/restart_background_service.sh"
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✅ 部署完成!                           ║"
echo "║   服务地址: http://${TARGET##*@}:8008     ║"
echo "╚══════════════════════════════════════════╝"
echo ""
if [ "$DEPLOY_MODE" = "systemd" ]; then
    echo "常用命令："
    echo "  ssh $TARGET 'sudo systemctl status portfolio-workbench'   # 查看状态"
    echo "  ssh $TARGET 'sudo journalctl -u portfolio-workbench -f'   # 查看日志"
    echo "  ssh $TARGET 'sudo systemctl restart portfolio-workbench'  # 重启"
else
    echo "常用命令："
    echo "  ssh $TARGET 'cd $REMOTE_DIR && ./scripts/restart_background_service.sh'  # 重启"
    echo "  ssh $TARGET 'tail -n 80 $REMOTE_DIR/output/invest-backend.stderr.log'    # 错误日志"
fi
