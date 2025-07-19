#!/bin/bash
# hybrid-lock.sh: 混合锁策略实现
# 排队阶段：乐观锁（快速重试）
# 构建阶段：悲观锁（确保独占）

# 加载调试工具
source .github/workflows/scripts/debug-utils.sh
# 加载模板工具
source .github/workflows/scripts/issue-templates.sh

# 配置参数
MAX_QUEUE_RETRIES=3
QUEUE_RETRY_DELAY=1
MAX_BUILD_WAIT_TIME=7200  # 2小时
BUILD_CHECK_INTERVAL=30   # 30秒
LOCK_TIMEOUT_HOURS=2      # 锁超时时间

# 通用函数：从队列管理issue中提取JSON数据
extract_queue_json() {
    local issue_content="$1"
    
    # 兼容性更好的提取方法，提取 ```json ... ``` 之间的内容
    local json_data=$(echo "$issue_content" | jq -r '.body' | sed -n '/```json/,/```/p' | sed '1d;$d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 验证JSON格式
    if [ -n "$json_data" ] && echo "$json_data" | jq . > /dev/null 2>&1; then
        local result=$(echo "$json_data" | jq -c .)
        echo "$result"
    else
        local result='{"queue":[],"run_id":null,"version":1}'
        echo "$result"
    fi
}

# 通用函数：获取队列管理issue内容
get_queue_manager_content() {
    local issue_number="$1"
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number")
    
    if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
        echo "Queue manager issue not found"
        return 1
    fi
    
    echo "$response"
}

# 通用函数：更新队列管理issue
update_queue_issue() {
    local issue_number="$1"
    local body="$2"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$body" '{"body": $body}')
    
    # 使用GitHub API更新issue
    local response=$(curl -s -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        echo "$response"
        return 0
    else
        echo "Failed to update queue issue"
        return 1
    fi
}

# 通用函数：使用混合锁模板更新队列管理issue
update_queue_issue_with_hybrid_lock() {
    local issue_number="$1"
    local queue_data="$2"
    local optimistic_lock_status="$3"
    local pessimistic_lock_status="$4"
    local current_build="${5:-无}"
    local lock_holder="${6:-无}"
    
    # 获取当前时间
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 提取版本号
    local version=$(echo "$queue_data" | jq -r '.version // 1')
    
    # 生成混合锁状态模板
    local body=$(generate_hybrid_lock_status_body "$current_time" "$queue_data" "$version" "$optimistic_lock_status" "$pessimistic_lock_status" "$current_build" "$lock_holder")
    
    # 更新issue
    update_queue_issue "$issue_number" "$body"
}

# 清理队列项（移除过期或无效的项）
clean_queue_items() {
    local queue_data="$1"
    local current_time="$2"
    
    # 移除超过6小时的队列项
    local cleaned_queue=$(echo "$queue_data" | jq --arg current_time "$current_time" '
        .queue = (.queue | map(select(
            # 保留workflow_dispatch类型（手动触发）
            .trigger_type == "workflow_dispatch" or
            # 检查issue类型是否在6小时内
            (.trigger_type == "issue" and 
             (($current_time | fromdateiso8601) - (.join_time | fromdateiso8601)) < 21600)
        )))
    ')
    
    echo "$cleaned_queue"
}

# 乐观锁队列加入
join_queue_optimistic() {
    local build_id="$1"
    local trigger_type="$2"
    local trigger_data="$3"
    local queue_limit="$4"
    
    debug "log" "Starting optimistic lock queue join process..."
    
    # 清理队列
    local queue_manager_issue="1"
    local queue_manager_content=$(get_queue_manager_content "$queue_manager_issue")
    if [ $? -ne 0 ]; then
        debug "error" "Failed to get queue manager content"
        return 1
    fi
    
    local queue_data=$(extract_queue_json "$queue_manager_content")
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 清理过期项
    local cleaned_queue_data=$(clean_queue_items "$queue_data" "$current_time")
    
    # 更新队列（清理后）
    local update_response=$(update_queue_issue_with_hybrid_lock "$queue_manager_issue" "$cleaned_queue_data" "空闲 🔓" "空闲 🔓")
    if [ $? -ne 0 ]; then
        debug "error" "Failed to update queue after cleanup"
        return 1
    fi
    
    # 尝试加入队列（最多重试3次）
    for attempt in $(seq 1 $MAX_QUEUE_RETRIES); do
        debug "log" "队列加入尝试 $attempt of $MAX_QUEUE_RETRIES"
        
        # 获取最新队列状态
        local latest_content=$(get_queue_manager_content "$queue_manager_issue")
        local latest_queue_data=$(extract_queue_json "$latest_content")
        
        # 检查队列长度
        local current_queue_length=$(echo "$latest_queue_data" | jq '.queue | length // 0')
        
        if [ "$current_queue_length" -ge "$queue_limit" ]; then
            debug "error" "Queue is full ($current_queue_length/$queue_limit)"
            return 1
        fi
        
        # 检查是否已在队列中
        local already_in_queue=$(echo "$latest_queue_data" | jq --arg build_id "$build_id" '.queue | map(select(.build_id == $build_id)) | length')
        if [ "$already_in_queue" -gt 0 ]; then
            debug "log" "Already in queue"
            return 0
        fi
        
        # 解析触发数据
        local parsed_trigger_data=$(echo "$trigger_data" | jq -c . 2>/dev/null || echo "{}")
        
        # 提取构建信息
        local tag=$(echo "$parsed_trigger_data" | jq -r '.tag // empty')
        local customer=$(echo "$parsed_trigger_data" | jq -r '.customer // empty')
        local slogan=$(echo "$parsed_trigger_data" | jq -r '.slogan // empty')
        
        # 创建新队列项
        local new_queue_item=$(jq -c -n \
            --arg build_id "$build_id" \
            --arg build_title "Custom Rustdesk Build" \
            --arg trigger_type "$trigger_type" \
            --arg tag "$tag" \
            --arg customer "$customer" \
            --arg customer_link "" \
            --arg slogan "$slogan" \
            --arg join_time "$current_time" \
            '{build_id: $build_id, build_title: $build_title, trigger_type: $trigger_type, tag: $tag, customer: $customer, customer_link: $customer_link, slogan: $slogan, join_time: $join_time}')
        
        # 添加新项到队列
        local new_queue_data=$(echo "$latest_queue_data" | jq --argjson new_item "$new_queue_item" '
            .queue += [$new_item] |
            .version = (.version // 0) + 1
        ')
        
        # 更新队列（乐观锁）
        local update_response=$(update_queue_issue_with_hybrid_lock "$queue_manager_issue" "$new_queue_data" "占用 🔒" "空闲 🔓")
        
        if [ $? -eq 0 ]; then
            debug "success" "Successfully joined queue at position $((current_queue_length + 1))"
            
            # 发送乐观锁通知
            local notification=$(cat <<EOF
## 🔄 乐观锁操作通知

**操作类型：** 加入队列
**构建ID：** $build_id
**队列位置：** $((current_queue_length + 1))
**操作时间：** $(date '+%Y-%m-%d %H:%M:%S')
**重试次数：** $attempt

**状态：** 乐观锁操作完成
**说明：** 使用快速重试机制，减少等待时间
EOF
)
            echo "$notification"
            return 0
        fi
        
        # 如果更新失败，等待后重试
        if [ "$attempt" -lt "$MAX_QUEUE_RETRIES" ]; then
            sleep "$QUEUE_RETRY_DELAY"
        fi
    done
    
    debug "error" "Failed to join queue after $MAX_QUEUE_RETRIES attempts"
    return 1
}

# 悲观锁获取构建权限
acquire_build_lock_pessimistic() {
    local build_id="$1"
    local queue_limit="$2"
    
    debug "log" "Starting pessimistic lock acquisition..."
    
    local start_time=$(date +%s)
    local queue_manager_issue="1"
    
    while [ $(($(date +%s) - start_time)) -lt $MAX_BUILD_WAIT_TIME ]; do
        # 获取队列状态
        local queue_content=$(get_queue_manager_content "$queue_manager_issue")
        if [ $? -ne 0 ]; then
            debug "error" "Failed to get queue content"
            return 1
        fi
        
        local queue_data=$(extract_queue_json "$queue_content")
        
        # 检查是否已在队列中
        local in_queue=$(echo "$queue_data" | jq --arg build_id "$build_id" '.queue | map(select(.build_id == $build_id)) | length')
        if [ "$in_queue" -eq 0 ]; then
            debug "error" "Not in queue anymore"
            return 1
        fi
        
        # 检查是否轮到我们构建
        local current_run_id=$(echo "$queue_data" | jq -r '.run_id // null')
        local queue_position=$(echo "$queue_data" | jq --arg build_id "$build_id" '.queue | map(.build_id) | index($build_id) // -1')
        
        if [ "$current_run_id" = "null" ] && [ "$queue_position" -eq 0 ]; then
            # 尝试获取构建锁
            local updated_queue_data=$(echo "$queue_data" | jq --arg build_id "$build_id" '
                .run_id = $build_id |
                .version = (.version // 0) + 1
            ')
            
            local update_response=$(update_queue_issue_with_hybrid_lock "$queue_manager_issue" "$updated_queue_data" "占用 🔒" "占用 🔒" "$build_id" "$build_id")
            
            if [ $? -eq 0 ]; then
                debug "success" "Successfully acquired build lock"
                return 0
            fi
        elif [ "$current_run_id" = "$build_id" ]; then
            debug "log" "Already have build lock"
            return 0
        else
            debug "log" "Waiting for turn... Position: $((queue_position + 1)), Current: $current_run_id"
        fi
        
        sleep "$BUILD_CHECK_INTERVAL"
    done
    
    debug "error" "Timeout waiting for build lock"
    return 1
}

# 释放构建锁
release_build_lock() {
    local build_id="$1"
    
    debug "log" "Releasing build lock..."
    
    local queue_manager_issue="1"
    local queue_content=$(get_queue_manager_content "$queue_manager_issue")
    if [ $? -ne 0 ]; then
        debug "error" "Failed to get queue content for lock release"
        return 1
    fi
    
    local queue_data=$(extract_queue_json "$queue_content")
    
    # 从队列中移除当前构建
    local updated_queue_data=$(echo "$queue_data" | jq --arg build_id "$build_id" '
        .queue = (.queue | map(select(.build_id != $build_id))) |
        .run_id = null |
        .version = (.version // 0) + 1
    ')
    
    local update_response=$(update_queue_issue_with_hybrid_lock "$queue_manager_issue" "$updated_queue_data" "占用 🔒" "空闲 🔓")
    
    if [ $? -eq 0 ]; then
        debug "success" "Successfully released build lock"
        return 0
    else
        debug "error" "Failed to release build lock"
        return 1
    fi
}

# 检查锁超时
check_lock_timeout() {
    local queue_data="$1"
    
    if [ -z "$queue_data" ] || ! echo "$queue_data" | jq . > /dev/null 2>&1; then
        echo "Invalid queue data during timeout check"
        return 1
    fi
    
    local current_lock_run_id=$(echo "$queue_data" | jq -r '.run_id // null')
    local current_queue=$(echo "$queue_data" | jq -r '.queue // []')
    
    if [ "$current_lock_run_id" != "null" ]; then
        # 查找锁持有者的加入时间
        local lock_join_time=$(echo "$current_queue" | \
            jq -r --arg run_id "$current_lock_run_id" \
            '.[] | select(.build_id == $run_id) | .join_time // empty' 2>/dev/null || echo "")
        
        if [ -n "$lock_join_time" ]; then
            local join_timestamp=$(date -d "$lock_join_time" +%s 2>/dev/null || echo "0")
            local current_timestamp=$(date +%s)
            local lock_duration_hours=$(( (current_timestamp - join_timestamp) / 3600 ))
            
            if [ "$lock_duration_hours" -ge "$LOCK_TIMEOUT_HOURS" ]; then
                echo "Lock timeout detected: ${lock_duration_hours} hours"
                return 0  # 需要清理
            fi
        fi
    fi
    
    return 1  # 不需要清理
}

# 重置队列为默认状态
reset_queue_to_default() {
    local queue_issue_number="$1"
    local reason="$2"
    
    echo "Resetting queue to default state: $reason"
    
    local default_queue_data='{"version": 1, "run_id": null, "queue": []}'
    
    # 使用混合锁模板重置队列
    local update_response=$(update_queue_issue_with_hybrid_lock "$queue_issue_number" "$default_queue_data" "空闲 🔓" "空闲 🔓")
    
    if echo "$update_response" | jq -e '.id' > /dev/null 2>&1; then
        echo "Queue reset successfully"
        return 0
    else
        echo "Queue reset failed"
        return 1
    fi
}

# 主混合锁函数
main_hybrid_lock() {
    local action="$1"
    local build_id="$2"
    local trigger_type="$3"
    local trigger_data="$4"
    local queue_limit="${5:-5}"
    
    echo "Starting hybrid lock strategy"
    
    case "$action" in
        "join_queue")
            echo "执行乐观锁队列加入"
            join_queue_optimistic "$build_id" "$trigger_type" "$trigger_data" "$queue_limit"
            ;;
        "acquire_lock")
            echo "执行悲观锁获取"
            acquire_build_lock_pessimistic "$build_id" "$queue_limit"
            ;;
        "release_lock")
            echo "执行悲观锁释放"
            release_build_lock "$build_id"
            ;;
        "check_timeout")
            echo "执行锁超时检查"
            local queue_content=$(get_queue_manager_content "1")
            if [ $? -eq 0 ]; then
                local queue_data=$(extract_queue_json "$queue_content")
                check_lock_timeout "$queue_data"
            fi
            ;;
        "reset_queue")
            echo "执行队列重置"
            local reason="${6:-手动重置}"
            reset_queue_to_default "1" "$reason"
            ;;
        *)
            echo "Unknown action: $action"
            return 1
            ;;
    esac
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 2 ]; then
        echo "Usage: $0 <action> <build_id> [trigger_type] [trigger_data] [queue_limit] [reason]"
        echo "Actions: join_queue, acquire_lock, release_lock, check_timeout, reset_queue"
        exit 1
    fi
    
    main_hybrid_lock "$@"
fi 
