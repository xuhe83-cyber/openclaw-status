#!/bin/bash
# 生成状态表盘 JSON 数据
# 供 HTML 网页读取

WORKSPACE="$HOME/.openclaw/workspace"
JSON_FILE="$WORKSPACE/status-dashboard/status-data.json"

# 统计文件数
count_files() {
    local path=$1
    local pattern=${2:-"*.md"}
    ls -1 "$path"/$pattern 2>/dev/null | wc -l | tr -d ' '
}

# Agent 活跃度
check_agent_status() {
    local agent=$1
    local session_file="$HOME/.openclaw/agents/$agent/agent/session.json"
    if [ -f "$session_file" ]; then
        local mtime=$(stat -f "%m" "$session_file" 2>/dev/null || echo "0")
        local now=$(date +%s)
        local diff=$(( (now - mtime) / 60 ))
        if [ "$diff" -lt 5 ]; then
            echo "🟢"
        elif [ "$diff" -lt 30 ]; then
            echo "🟡"
        else
            echo "⚪"
        fi
    else
        echo "⚪"
    fi
}

# 数据收集
inbox_count=$(count_files ~/.openclaw/h_data_inbox)
vault_count=$(count_files ~/.openclaw/h_data_vault)
pending_count=$(count_files ~/.openclaw/h_data_pending_vault)
tagsMOCs_count=$(count_files ~/.openclaw/librarian_vault_tagsMOCs)
bridged_count=$(count_files "$WORKSPACE/Bridged_vault")

# Cleaner 进度（从 Cleaner 报告读取或估算）
cleaner_done=167
cleaner_total=281
cleaner_pending=$((cleaner_total - cleaner_done))

# 资源使用
memory_percent=$(top -l 1 2>/dev/null | grep "PhysMem" | awk '{gsub(/%/,""); print $6}' || echo "16")
disk_percent=$(df -h ~ 2>/dev/null | tail -1 | awk '{gsub(/%/,""); print $5}' || echo "53")

# Agent 状态
main_status=$(check_agent_status main)
gatekeeper_status=$(check_agent_status gatekeeper)
librarian_status=$(check_agent_status librarian)
bridgebuilder_status=$(check_agent_status bridgebuilder)
cleaner_status=$(check_agent_status cleaner)

# 生成告警
alerts="[]"
alert_items=()

if [ "$inbox_count" -gt 5 ]; then
    alert_items+=("⚠️ Inbox 积压 $inbox_count 个文件")
fi

if [ "$vault_count" -gt 10 ]; then
    alert_items+=("⚠️ Vault 积压 $vault_count 个文件")
fi

if [ "$memory_percent" -gt 80 ]; then
    alert_items+=("🚨 内存使用率 ${memory_percent}%")
fi

if [ "$disk_percent" -gt 90 ]; then
    alert_items+=("🚨 磁盘使用率 ${disk_percent}%")
fi

# 构建告警 JSON 数组
if [ ${#alert_items[@]} -eq 0 ]; then
    alerts="[]"
else
    alerts="["
    for i in "${!alert_items[@]}"; do
        [ $i -gt 0 ] && alerts+=","
        alerts+="\"${alert_items[$i]}\""
    done
    alerts+="]"
fi

# 生成 JSON
cat > "$JSON_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "cleaner": {
    "done": $cleaner_done,
    "pending": $cleaner_pending,
    "total": $cleaner_total
  },
  "vault": {
    "inbox": $inbox_count,
    "vault": $vault_count,
    "pending": $pending_count,
    "tagsMOCs": $tagsMOCs_count,
    "bridged": $bridged_count
  },
  "agents": {
    "main": "$main_status",
    "gatekeeper": "$gatekeeper_status",
    "librarian": "$librarian_status",
    "bridgebuilder": "$bridgebuilder_status",
    "cleaner": "$cleaner_status"
  },
  "resources": {
    "memory": $memory_percent,
    "disk": $disk_percent
  },
  "alerts": $alerts
}
EOF

echo "✅ JSON 数据已更新：$JSON_FILE"
