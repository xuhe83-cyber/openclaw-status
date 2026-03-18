#!/bin/bash
# 定时更新状态表盘并推送到 GitHub Pages
# 每 30 秒运行一次

WORKSPACE="$HOME/.openclaw/workspace"
DASHBOARD_DIR="$WORKSPACE/status-dashboard"

cd "$DASHBOARD_DIR"

# 生成最新数据
./generate-json.sh

# 提交并推送
git add status-data.json
git commit -m "Auto-update: $(date '+%Y-%m-%d %H:%M:%S')" --quiet 2>/dev/null || true
git push origin main --quiet 2>/dev/null || echo "Push failed, will retry next cycle"

# 更新 index.html 中的访问地址提示
sed -i '' 's|https://clawh.github.io/openclaw-status/|https://xuhe83-cyber.github.io/openclaw-status/|g' index.html 2>/dev/null || true

echo "✅ Dashboard updated at $(date '+%H:%M:%S')"
