#!/bin/bash
set -e

# ============================================================
# VitalCommand 一键部署脚本
# 用法: ./deploy/deploy.sh [user@host]
# 示例: ./deploy/deploy.sh xmly@10.8.245.185
# ============================================================

TARGET=${1:-"xmly@10.8.245.185"}
REMOTE_DIR="/opt/vital-command"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "╔══════════════════════════════════════════╗"
echo "║   VitalCommand 一键部署                  ║"
echo "║   目标: $TARGET:$REMOTE_DIR"
echo "╚══════════════════════════════════════════╝"
echo ""

# ---- Step 1: Build ----
echo "▶ [1/5] 构建 Next.js standalone..."
PATH="/opt/homebrew/opt/node@22/bin:$PATH" npm run build
echo "  ✅ 构建完成"

# ---- Step 2: Test SSH ----
echo ""
echo "▶ [2/5] 测试 SSH 连接..."
ssh -o ConnectTimeout=5 -o BatchMode=yes "$TARGET" "echo '  ✅ SSH 连接成功'" 2>/dev/null || {
    echo "  ❌ 无法连接到 $TARGET"
    echo "  请确保："
    echo "    1. 目标机已开机且在同一网段"
    echo "    2. 已配置 SSH 密钥（ssh-copy-id $TARGET）"
    echo "    3. 目标机已安装 Node.js 22+"
    echo ""
    echo "  手动部署步骤："
    echo "    scp -r .next/standalone/ $TARGET:$REMOTE_DIR/"
    echo "    scp -r .next/static/ $TARGET:$REMOTE_DIR/.next/static/"
    echo "    scp -r migrations/ $TARGET:$REMOTE_DIR/migrations/"
    echo "    scp deploy/.env.production $TARGET:$REMOTE_DIR/.env"
    echo "    ssh $TARGET 'cd $REMOTE_DIR && node server.js'"
    exit 1
}

# ---- Step 3: Setup remote directory ----
echo ""
echo "▶ [3/5] 初始化远程目录..."
ssh "$TARGET" "sudo mkdir -p $REMOTE_DIR/data $REMOTE_DIR/.next/static $REMOTE_DIR/migrations && sudo chown -R \$(whoami) $REMOTE_DIR"
echo "  ✅ 目录就绪"

# ---- Step 4: Sync files ----
echo ""
echo "▶ [4/5] 同步文件到远程..."
rsync -az --delete .next/standalone/ "$TARGET:$REMOTE_DIR/"
rsync -az --delete .next/static/ "$TARGET:$REMOTE_DIR/.next/static/"
rsync -az --delete migrations/ "$TARGET:$REMOTE_DIR/migrations/"

# Sync .env if exists locally (or create a template)
if [ -f deploy/.env.production ]; then
    rsync -az deploy/.env.production "$TARGET:$REMOTE_DIR/.env"
elif [ -f .env ]; then
    echo "  ⚠ 使用本地 .env（建议创建 deploy/.env.production）"
    rsync -az .env "$TARGET:$REMOTE_DIR/.env"
fi

# Sync systemd service
ssh "$TARGET" "sudo cp /dev/stdin /etc/systemd/system/vital-command.service" < deploy/vital-command.service
echo "  ✅ 文件同步完成"

# ---- Step 5: Restart service ----
echo ""
echo "▶ [5/5] 重启服务..."
ssh "$TARGET" "sudo systemctl daemon-reload && sudo systemctl enable vital-command && sudo systemctl restart vital-command && sleep 2 && sudo systemctl status vital-command --no-pager -l"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✅ 部署完成!                           ║"
echo "║   服务地址: http://${TARGET##*@}:3000     ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "常用命令："
echo "  ssh $TARGET 'sudo systemctl status vital-command'   # 查看状态"
echo "  ssh $TARGET 'sudo journalctl -u vital-command -f'   # 查看日志"
echo "  ssh $TARGET 'sudo systemctl restart vital-command'  # 重启服务"
