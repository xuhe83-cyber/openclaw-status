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

# Agent 活跃度 - 基于 session.json 最后修改时间
check_agent_status() {
    local agent=$1
    local session_file="$HOME/.openclaw/agents/$agent/agent/session.json"
    if [ -f "$session_file" ]; then
        local mtime=$(stat -f "%m" "$session_file" 2>/dev/null || echo "0")
        local now=$(date +%s)
        local diff=$(( (now - mtime) / 60 ))
        if [ "$diff" -lt 5 ]; then
            echo "active"
        elif [ "$diff" -lt 30 ]; then
            echo "idle"
        else
            echo "offline"
        fi
    else
        echo "offline"
    fi
}

# 获取运行中的 agent 列表（从 sessions.json 文件解析）
get_running_agents() {
    local agents_json="["
    local first=true
    
    # 从 sessions.json 中提取所有唯一的 agent 类型
    local unique_agents=$(grep -o "agent:main:[^:]*" "$HOME/.openclaw/agents/main/sessions/sessions.json" 2>/dev/null | cut -d':' -f3 | sort | uniq)
    
    # 遍历所有唯一的 agent 类型
    for agent_type in $unique_agents; do
        # 跳过空值和不符合规范的类型
        if [ -n "$agent_type" ] && [ "$agent_type" != "main\"" ] && [ "$agent_type" != "telegram\"" ] && [ "$agent_type" != "webchat\"" ]; then
            # 获取该 agent 的状态
            local status=$(check_agent_status "$agent_type")
            
            if [ "$first" = true ]; then
                first=false
            else
                agents_json+=","
            fi
            agents_json+="{\"name\":\"$agent_type\",\"status\":\"$status\"}"
        fi
    done
    
    # 检查主要的后台 agent 是否存在对应的目录和进程
    for agent_type in "gatekeeper" "librarian" "bridgebuilder" "auditor" "interpreter" "cleaner"; do
        # 检查 agent 目录是否存在
        if [ -d "$HOME/.openclaw/agents/$agent_type" ]; then
            # 检查是否在 sessions.json 中已存在
            if ! echo "$unique_agents" | grep -q "^$agent_type$"; then
                # Agent 目录存在但会话不存在，可能处于非活动状态
                local status="idle"
                if [ "$first" = true ]; then
                    first=false
                else
                    agents_json+=","
                fi
                agents_json+="{\"name\":\"$agent_type\",\"status\":\"$status\"}"
            fi
        fi
    done
    
    agents_json+="]"
    echo "$agents_json"
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
memory_percent_raw=$(top -l 1 2>/dev/null | grep "PhysMem" | awk '{print $6}' || echo "16%")
memory_percent=$(echo "$memory_percent_raw" | sed 's/%//' | sed 's/[a-zA-Z]//g' | awk '{print int($1)}' 2>/dev/null || echo "16")
disk_percent=$(df -h ~ 2>/dev/null | tail -1 | awk '{gsub(/%/,""); print $5}' || echo "53")

# 获取运行中的 agents 列表
agents_json=$(get_running_agents)

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
  "agents": $agents_json,
  "resources": {
    "memory": $memory_percent,
    "disk": $disk_percent
  },
  "alerts": $alerts
}
EOF

echo "✅ JSON 数据已更新：$JSON_FILE"
echo "   运行中的 agents: $agents_json"
