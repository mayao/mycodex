#!/usr/bin/env bash
# migrate_to_projects.sh
# 将 MyCodex 项目从 iCloud 迁移到 /Users/xmly/Projects
#
# 用法：
#   bash ~/Library/Mobile\ Documents/com~apple~CloudDocs/MyCodex/scripts/migrate_to_projects.sh
# 或在 iCloud 目录内运行后，从新目录继续工作。

set -euo pipefail

OLD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/MyCodex"
NEW_DIR="$HOME/Projects/MyCodex"

echo "==> 迁移 MyCodex 项目"
echo "    源目录: $OLD_DIR"
echo "    目标目录: $NEW_DIR"
echo ""

# 1. 检查源目录存在
if [ ! -d "$OLD_DIR" ]; then
  echo "❌ 源目录不存在: $OLD_DIR"
  exit 1
fi

# 2. 创建目标父目录
mkdir -p "$HOME/Projects"

# 3. 如果目标目录已存在则跳过克隆
if [ -d "$NEW_DIR/.git" ]; then
  echo "✅ 目标目录已存在且是 git 仓库，跳过克隆。"
else
  echo "==> 从远程 git 仓库克隆项目..."
  REMOTE_URL=$(git -C "$OLD_DIR" remote get-url origin)
  echo "    Remote: $REMOTE_URL"
  git clone "$REMOTE_URL" "$NEW_DIR"
fi

# 4. 切换到目标目录，拉取最新代码
cd "$NEW_DIR"
echo "==> 拉取最新代码..."
git fetch --all
git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
git pull

# 5. 复制 uploads 目录（已上传的结单 PDF）
UPLOADS_SRC="$OLD_DIR/market_dashboard/uploads"
UPLOADS_DST="$NEW_DIR/market_dashboard/uploads"
if [ -d "$UPLOADS_SRC" ]; then
  echo "==> 复制 uploads 目录..."
  rsync -av --progress "$UPLOADS_SRC/" "$UPLOADS_DST/"
else
  echo "ℹ️  无 uploads 目录，跳过。"
fi

# 6. 复制 Health uploads（如有）
HEALTH_UPLOADS_SRC="$OLD_DIR/Health/uploads"
HEALTH_UPLOADS_DST="$NEW_DIR/Health/uploads"
if [ -d "$HEALTH_UPLOADS_SRC" ]; then
  echo "==> 复制 Health/uploads 目录..."
  rsync -av --progress "$HEALTH_UPLOADS_SRC/" "$HEALTH_UPLOADS_DST/"
fi

# 7. 提示安装依赖
echo ""
echo "==> 迁移完成！"
echo ""
echo "后续步骤："
echo "  cd \"$NEW_DIR\""
echo ""
echo "  # 启动 market_dashboard："
echo "  cd market_dashboard && python3 app.py"
echo ""
echo "  # 启动 Health（Next.js）："
echo "  cd Health && npm install && npm run dev"
echo ""
echo "注意：statement_sources.py 中的结单 PDF（科技平权-投资）仍在 iCloud，"
echo "路径不变。如需改用本地副本，请手动更新 market_dashboard/statement_sources.py 中的路径。"
