#!/bin/bash
# 队列管理脚本 - 伪面向对象模式
# 这个文件包含所有队列操作功能，采用简单的伪面向对象设计
# 主要用于被 CustomBuildRustdesk.yml 工作流调用
# 整合了混合锁机制（乐观锁 + 悲观锁）

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/encryption-utils.sh
source .github/workflows/scripts/issue-templates.sh

# 队列管理器 - 伪面向对象实现
# 使用全局变量存储实例状态

# 私有属性（全局变量）
_QUEUE_MANAGER_ISSUE_NUMBER=""
_QUEUE_MANAGER_QUEUE_DATA=""
_QUEUE_MANAGER_CURRENT_TIME=""

# 混合锁配置参数
_QUEUE_MANAGER_MAX_RETRIES=3
_QUEUE_MANAGER_RETRY_DELAY=1
_QUEUE_MANAGER_MAX_WAIT_TIME=7200  # 2小时 - 构建锁获取超时
_QUEUE_MANAGER_CHECK_INTERVAL=30   # 30秒 - 检查间隔
_QUEUE_MANAGER_LOCK_TIMEOUT_HOURS=2      # 构建锁超时时间（2小时）
_QUEUE_MANAGER_QUEUE_TIMEOUT_HOURS=6     # 队列锁超时时间（6小时）

# 构造函数
queue_manager_init() {
    local issue_number="${1:-1}"
    _QUEUE_MANAGER_ISSUE_NUMBER="$issue_number"
    _QUEUE_MANAGER_CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    debug "log" "Initializing queue manager with issue #$_QUEUE_MANAGER_ISSUE_NUMBER"
    queue_manager_load_data
}

# 私有方法：加载队列数据
queue_manager_load_data() {
    debug "log" "Loading queue data for issue #$_QUEUE_MANAGER_ISSUE_NUMBER"
    
    local queue_manager_content=$(queue_manager_get_content "$_QUEUE_MANAGER_ISSUE_NUMBER")
    if [ $? -ne 0 ]; then
        debug "error" "Failed to get queue manager content"
        return 1
    fi
    
    debug "log" "Queue manager content received"
    
    _QUEUE_MANAGER_QUEUE_DATA=$(queue_manager_extract_json "$queue_manager_content")
    debug "log" "Queue data loaded successfully: $_QUEUE_MANAGER_QUEUE_DATA"
}

# 私有方法：获取队列管理器内容
queue_manager_get_content() {
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

# 私有方法：提取JSON数据
queue_manager_extract_json() {
    local issue_content="$1"
    
    debug "log" "Extracting JSON from issue content..."
    
    # 提取 ```json ... ``` 代码块
    local json_data=$(echo "$issue_content" | jq -r '.body' | sed -n '/```json/,/```/p' | sed '1d;$d')
    json_data=$(echo "$json_data" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    debug "log" "Extracted JSON data: $json_data"
    
    # 如果提取失败，尝试直接查找JSON对象
    if [ -z "$json_data" ]; then
        debug "log" "No JSON code block found, trying to extract JSON object directly..."
        json_data=$(echo "$issue_content" | jq -r '.body' | grep -o '{.*}' | head -1)
        debug "log" "Direct JSON extraction: $json_data"
    fi
    
    # 如果还是失败，尝试更宽松的提取
    if [ -z "$json_data" ]; then
        debug "log" "Direct extraction failed, trying pattern matching..."
        # 查找包含 "version" 和 "queue" 的JSON对象
        json_data=$(echo "$issue_content" | jq -r '.body' | grep -A 50 '"version"' | grep -B 50 '"queue"' | head -20 | tr '\n' ' ' | grep -o '{[^}]*"version"[^}]*"queue"[^}]*}')
        debug "log" "Pattern matching extraction: $json_data"
    fi
    
    # 验证JSON格式并返回
    if [ -n "$json_data" ]; then
        debug "log" "JSON data is not empty, attempting to parse..."
        if echo "$json_data" | jq . > /dev/null 2>&1; then
            local result=$(echo "$json_data" | jq -c .)
            debug "log" "Valid JSON extracted: $result"
            echo "$result"
        else
            debug "error" "JSON parsing failed, using default"
            local result='{"queue":[],"run_id":null,"version":1}'
            echo "$result"
        fi
    else
        debug "error" "JSON data is empty, using default"
        local result='{"queue":[],"run_id":null,"version":1}'
        echo "$result"
    fi
}

# 私有方法：更新队列管理issue
queue_manager_update_issue() {
    local body="$1"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$body" '{"body": $body}')
    
    # 使用GitHub API更新issue
  local response=$(curl -s -X PATCH \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$_QUEUE_MANAGER_ISSUE_NUMBER \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        echo "$response"
        return 0
    else
        debug "error" "Failed to update queue issue"
    return 1
  fi
}

# 私有方法：使用混合锁模板更新队列管理issue
queue_manager_update_with_lock() {
    local queue_data="$1"
    local optimistic_lock_status="$2"
    local pessimistic_lock_status="$3"
    local current_build="${4:-无}"
    local lock_holder="${5:-无}"
    
    # 获取当前时间
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 提取版本号
    local version=$(echo "$queue_data" | jq -r '.version // 1')
    
    # 生成混合锁状态模板
    local body=$(generate_hybrid_lock_status_body "$current_time" "$queue_data" "$version" "$optimistic_lock_status" "$pessimistic_lock_status" "$current_build" "$lock_holder")
    
    # 更新issue
    queue_manager_update_issue "$body"
}

# 公共方法：获取队列状态
queue_manager_get_status() {
    echo "=== 队列状态 ==="
    queue_manager_get_statistics
    echo ""
    queue_manager_show_details
}

# 私有方法：获取统计信息
queue_manager_get_statistics() {
    local queue_length=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '.queue | length // 0')
    local current_run_id=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.run_id // "null"')
    local version=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.version // 1')
    
    # 按类型统计
    local workflow_dispatch_count=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.queue[] | select(.trigger_type == "workflow_dispatch") | .build_id' | wc -l)
    local issue_count=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.queue[] | select(.trigger_type == "issue") | .build_id' | wc -l)
    
    echo "队列统计:"
    echo "  总数量: $queue_length"
    echo "  手动触发: $workflow_dispatch_count"
    echo "  Issue触发: $issue_count"
    echo "  当前运行ID: $current_run_id"
    echo "  版本: $version"
}

# 私有方法：显示详细信息
queue_manager_show_details() {
    echo "队列详细信息:"
    echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq .
    
    echo ""
    echo "队列项列表:"
    local queue_length=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '.queue | length // 0')
    if [ "$queue_length" -gt 0 ]; then
        echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.queue[] | "  - 构建ID: \(.build_id), 类型: \(.trigger_type), 客户: \(.customer), 加入时间: \(.join_time)"'
    else
        echo "  队列为空"
    fi
}

# 公共方法：乐观锁加入队列
queue_manager_join_queue() {
    local build_id="$1"
    local trigger_type="$2"
    local trigger_data="$3"
    local queue_limit="${4:-5}"
    
    echo "=== 乐观锁加入队列 ==="
    debug "log" "Starting optimistic lock queue join process..."
    
    # 清理队列和检查当前锁
    queue_manager_auto_clean_expired
    queue_manager_check_and_clean_current_lock
    queue_manager_clean_completed
    
    # 尝试加入队列（最多重试3次）
    for attempt in $(seq 1 $_QUEUE_MANAGER_MAX_RETRIES); do
        debug "log" "队列加入尝试 $attempt of $_QUEUE_MANAGER_MAX_RETRIES"
        
        # 刷新队列数据
        queue_manager_refresh
        
        # 检查队列长度
        local current_queue_length=$(queue_manager_get_length)
        
        if [ "$current_queue_length" -ge "$queue_limit" ]; then
            debug "error" "Queue is full ($current_queue_length/$queue_limit)"
    return 1
  fi
        
        # 检查是否已在队列中
        local already_in_queue=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" '.queue | map(select(.build_id == $build_id)) | length')
        if [ "$already_in_queue" -gt 0 ]; then
            debug "log" "Already in queue"
            return 0
        fi
        
        # 解析触发数据
        debug "log" "Parsing trigger data: $trigger_data"
        local parsed_trigger_data=$(echo "$trigger_data" | jq -c . 2>/dev/null || echo "{}")
        debug "log" "Parsed trigger data: $parsed_trigger_data"
        
        # 提取构建信息
        debug "log" "Extracting build information..."
        local tag=$(echo "$parsed_trigger_data" | jq -r '.tag // empty')
        local customer=$(echo "$parsed_trigger_data" | jq -r '.customer // empty')
        local slogan=$(echo "$parsed_trigger_data" | jq -r '.slogan // empty')
        
        debug "log" "Extracted build info - tag: '$tag', customer: '$customer', slogan: '$slogan'"
        
        # 创建新队列项
        debug "log" "Creating new queue item..."
        local new_queue_item=$(jq -c -n \
            --arg build_id "$build_id" \
            --arg build_title "Custom Rustdesk Build" \
            --arg trigger_type "$trigger_type" \
            --arg tag "$tag" \
            --arg customer "$customer" \
            --arg customer_link "" \
            --arg slogan "$slogan" \
            --arg join_time "$_QUEUE_MANAGER_CURRENT_TIME" \
            '{build_id: $build_id, build_title: $build_title, trigger_type: $trigger_type, tag: $tag, customer: $customer, customer_link: $customer_link, slogan: $slogan, join_time: $join_time}')
        
        debug "log" "New queue item created: $new_queue_item"
        
        # 添加新项到队列
        debug "log" "Current queue data: $_QUEUE_MANAGER_QUEUE_DATA"
        local new_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --argjson new_item "$new_queue_item" '
            .queue += [$new_item] |
            .version = (.version // 0) + 1
        ')
        
        debug "log" "Updated queue data: $new_queue_data"
        
        # 更新队列（乐观锁）
        local update_response=$(queue_manager_update_with_lock "$new_queue_data" "占用 🔒" "空闲 🔓")
        
        if [ $? -eq 0 ]; then
            debug "success" "Successfully joined queue at position $((current_queue_length + 1))"
            _QUEUE_MANAGER_QUEUE_DATA="$new_queue_data"
            return 0
        fi
        
        # 如果更新失败，等待后重试
        if [ "$attempt" -lt "$_QUEUE_MANAGER_MAX_RETRIES" ]; then
            sleep "$_QUEUE_MANAGER_RETRY_DELAY"
    fi
  done
  
    debug "error" "Failed to join queue after $_QUEUE_MANAGER_MAX_RETRIES attempts"
    return 1
}

# 公共方法：悲观锁获取构建权限
queue_manager_acquire_lock() {
    local build_id="$1"
    local queue_limit="${2:-5}"
    
    echo "=== 悲观锁获取构建权限 ==="
    debug "log" "Starting pessimistic lock acquisition..."
    
    local start_time=$(date +%s)
    
    while [ $(($(date +%s) - start_time)) -lt $_QUEUE_MANAGER_MAX_WAIT_TIME ]; do
        # 刷新队列数据并清理
        queue_manager_refresh
        queue_manager_check_and_clean_current_lock
        queue_manager_clean_completed
        
        # 检查是否已在队列中
        local in_queue=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" '.queue | map(select(.build_id == $build_id)) | length')
        if [ "$in_queue" -eq 0 ]; then
            debug "error" "Not in queue anymore"
            return 1
        fi
        
        # 检查是否轮到我们构建
        local current_run_id=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.run_id // null')
        local queue_position=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" '.queue | map(.build_id) | index($build_id) // -1')
        
        if [ "$current_run_id" = "null" ] && [ "$queue_position" -eq 0 ]; then
            # 尝试获取构建锁
            local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" '
                .run_id = $build_id |
                .version = (.version // 0) + 1
            ')
            
            local update_response=$(queue_manager_update_with_lock "$updated_queue_data" "占用 🔒" "占用 🔒" "$build_id" "$build_id")
            
            if [ $? -eq 0 ]; then
                debug "success" "Successfully acquired build lock"
                _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
                return 0
            fi
        elif [ "$current_run_id" = "$build_id" ]; then
            debug "log" "Already have build lock"
    return 0
  else
            debug "log" "Waiting for turn... Position: $((queue_position + 1)), Current: $current_run_id"
        fi
        
        sleep "$_QUEUE_MANAGER_CHECK_INTERVAL"
    done
    
    debug "error" "Timeout waiting for build lock"
    return 1
}

# 公共方法：释放构建锁
queue_manager_release_lock() {
    local build_id="$1"
    
    echo "=== 释放构建锁 ==="
    debug "log" "Releasing build lock..."
    
    # 刷新队列数据
    queue_manager_refresh
    
    # 从队列中移除当前构建
    local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" '
        .queue = (.queue | map(select(.build_id != $build_id))) |
        .run_id = null |
        .version = (.version // 0) + 1
    ')
    
    local update_response=$(queue_manager_update_with_lock "$updated_queue_data" "占用 🔒" "空闲 🔓")
    
    if [ $? -eq 0 ]; then
        debug "success" "Successfully released build lock"
        _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
        return 0
    else
        debug "error" "Failed to release build lock"
        return 1
    fi
}

# 公共方法：清理已完成的工作流
queue_manager_clean_completed() {
    echo "=== 清理已完成的工作流 ==="
    debug "log" "Checking workflow run statuses..."
    
    # 获取队列中的构建ID列表
    local build_ids=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.queue[]?.build_id // empty')
    
    if [ -z "$build_ids" ]; then
        debug "log" "Queue is empty, nothing to clean"
        return 0
    fi
    
    # 存储需要清理的构建ID
    local builds_to_remove=()
    
    for build_id in $build_ids; do
        debug "log" "Checking build $build_id..."
        
        # 获取工作流运行状态
        local run_status="unknown"
        if [ -n "$GITHUB_TOKEN" ]; then
            local run_response=$(curl -s \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$build_id")
            
            if echo "$run_response" | jq -e '.message' | grep -q "Not Found"; then
                run_status="not_found"
            else
                run_status=$(echo "$run_response" | jq -r '.status // "unknown"')
            fi
        fi
        
        debug "log" "Build $build_id status: $run_status"
        
        # 检查是否需要清理
        case "$run_status" in
            "completed"|"cancelled"|"failure"|"skipped"|"not_found"|"unknown")
                debug "log" "Build $build_id needs cleanup (status: $run_status)"
                builds_to_remove+=("$build_id")
                ;;
            "queued"|"in_progress"|"waiting")
                debug "log" "Build $build_id is still running (status: $run_status)"
                ;;
            *)
                debug "log" "Build $build_id has unknown status: $run_status"
                builds_to_remove+=("$build_id")
                ;;
        esac
    done
    
    # 执行清理操作
    if [ ${#builds_to_remove[@]} -eq 0 ]; then
        debug "log" "No builds need cleanup"
        return 0
    else
        debug "log" "Removing ${#builds_to_remove[@]} completed builds: ${builds_to_remove[*]}"
        
        # 从队列中移除这些构建
        local cleaned_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --argjson builds_to_remove "$(printf '%s\n' "${builds_to_remove[@]}" | jq -R . | jq -s .)" '
            .queue = (.queue | map(select(.build_id as $id | $builds_to_remove | index($id) | not))) |
            .version = (.version // 0) + 1
        ')
        
        # 更新队列
        local update_response=$(queue_manager_update_with_lock "$cleaned_queue_data" "空闲 🔓" "空闲 🔓")
        
        if [ $? -eq 0 ]; then
            debug "success" "Successfully cleaned ${#builds_to_remove[@]} completed builds"
            _QUEUE_MANAGER_QUEUE_DATA="$cleaned_queue_data"
            return 0
        else
            debug "error" "Failed to clean completed builds"
            return 1
        fi
    fi
}

# 公共方法：检查和清理当前持有锁的构建
queue_manager_check_and_clean_current_lock() {
    echo "=== 检查和清理当前持有锁的构建 ==="
    debug "log" "Checking current lock holder..."
    
    local current_run_id=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.run_id // null')
    
    if [ "$current_run_id" = "null" ]; then
        debug "log" "No current lock holder"
        return 0
    fi
    
    debug "log" "Current lock holder: $current_run_id"
    
    # 检查当前持有锁的构建状态
    local run_status="unknown"
    if [ -n "$GITHUB_TOKEN" ]; then
        local run_response=$(curl -s \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$current_run_id")
        
        if echo "$run_response" | jq -e '.message' | grep -q "Not Found"; then
            run_status="not_found"
        else
            run_status=$(echo "$run_response" | jq -r '.status // "unknown"')
        fi
    fi
    
    debug "log" "Current lock holder status: $run_status"
    
    # 检查是否需要释放锁
    case "$run_status" in
        "completed"|"cancelled"|"failure"|"skipped"|"not_found"|"unknown")
            debug "log" "Current lock holder needs cleanup (status: $run_status), releasing lock"
            
            # 释放锁
            local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '
                .run_id = null |
                .version = (.version // 0) + 1
            ')
            
            local update_response=$(queue_manager_update_with_lock "$updated_queue_data" "占用 🔒" "空闲 🔓")
            
            if [ $? -eq 0 ]; then
                debug "success" "Successfully released lock for completed build"
                _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
                return 0
            else
                debug "error" "Failed to release lock for completed build"
                return 1
            fi
            ;;
        "queued"|"in_progress"|"waiting")
            debug "log" "Current lock holder is still running (status: $run_status)"
            
            # 检查构建锁超时
            local build_timeout_seconds=$((_QUEUE_MANAGER_LOCK_TIMEOUT_HOURS * 3600))
            local current_time=$(date +%s)
            
            # 获取构建开始时间（从队列中查找）
            local build_start_time=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$current_run_id" '
                .queue[] | select(.build_id == $build_id) | .join_time
            ')
            
            if [ -n "$build_start_time" ] && [ "$build_start_time" != "null" ]; then
                local build_start_epoch=$(date -d "$build_start_time" +%s 2>/dev/null || echo "0")
                local elapsed_time=$((current_time - build_start_epoch))
                
                if [ "$elapsed_time" -gt "$build_timeout_seconds" ]; then
                    debug "log" "Build lock timeout (${elapsed_time}s > ${build_timeout_seconds}s), releasing lock"
                    
                    # 释放超时的构建锁
                    local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '
                        .run_id = null |
                        .version = (.version // 0) + 1
                    ')
                    
                    local update_response=$(queue_manager_update_with_lock "$updated_queue_data" "占用 🔒" "空闲 🔓")
                    
                    if [ $? -eq 0 ]; then
                        debug "success" "Successfully released timeout build lock"
                        _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
                        return 0
                    else
                        debug "error" "Failed to release timeout build lock"
                        return 1
                    fi
                else
                    debug "log" "Build lock still valid (${elapsed_time}s < ${build_timeout_seconds}s)"
                fi
            fi
            
            return 0
            ;;
        *)
            debug "log" "Current lock holder has unknown status: $run_status, releasing lock"
            
            # 释放锁
            local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '
                .run_id = null |
                .version = (.version // 0) + 1
            ')
            
            local update_response=$(queue_manager_update_with_lock "$updated_queue_data" "占用 🔒" "空闲 🔓")
            
            if [ $? -eq 0 ]; then
                debug "success" "Successfully released lock for unknown status build"
                _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
                return 0
            else
                debug "error" "Failed to release lock for unknown status build"
                return 1
            fi
            ;;
    esac
}

# 公共方法：自动清理过期项
queue_manager_auto_clean_expired() {
    echo "=== 自动清理过期项 ==="
    debug "log" "Cleaning expired queue items (older than $_QUEUE_MANAGER_QUEUE_TIMEOUT_HOURS hours)..."
    
    # 计算超时秒数
    local queue_timeout_seconds=$((_QUEUE_MANAGER_QUEUE_TIMEOUT_HOURS * 3600))
    
    # 移除超过队列超时时间的队列项
    local cleaned_queue=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg current_time "$_QUEUE_MANAGER_CURRENT_TIME" --arg timeout_seconds "$queue_timeout_seconds" '
        .queue = (.queue | map(select(
            # 检查所有类型是否在队列超时时间内
            (($current_time | fromdateiso8601) - (.join_time | fromdateiso8601)) < ($timeout_seconds | tonumber)
        )))
    ')
    
    local update_response=$(queue_manager_update_with_lock "$cleaned_queue" "空闲 🔓" "空闲 🔓")
    if [ $? -eq 0 ]; then
        debug "success" "Auto-clean completed"
        _QUEUE_MANAGER_QUEUE_DATA="$cleaned_queue"
        return 0
    else
        debug "error" "Auto-clean failed"
        return 1
    fi
}

# 公共方法：全面清理队列
queue_manager_full_cleanup() {
    echo "=== 全面清理队列 ==="
    debug "log" "Starting comprehensive queue cleanup..."
    
    local current_version=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.version // 1')
    
    # 开始清理数据
    local cleaned_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | \
        jq --arg new_version "$((current_version + 1))" '
        # 移除重复项
        .queue = (.queue | group_by(.build_id) | map(.[0]))
        # 重置异常项
        | .run_id = null
        | .version = ($new_version | tonumber)
    ')
    
    # 计算清理后的队列数量
    local final_queue_length=$(echo "$cleaned_queue_data" | jq '.queue | length // 0')
    
    debug "log" "Queue cleanup completed. Final queue length: $final_queue_length"
    
    # 更新队列管理issue
    local update_response=$(queue_manager_update_with_lock "$cleaned_queue_data" "空闲 🔓" "空闲 🔓")
    
    if [ $? -eq 0 ]; then
        debug "success" "Queue cleanup successful"
        _QUEUE_MANAGER_QUEUE_DATA="$cleaned_queue_data"
        return 0
    else
        debug "error" "Queue cleanup failed"
        return 1
    fi
}

# 公共方法：重置队列
queue_manager_reset() {
    local reason="${1:-手动重置}"
    echo "=== 重置队列 ==="
    debug "log" "Resetting queue to default state: $reason"
    
    local now=$(date '+%Y-%m-%d %H:%M:%S')
    local reset_queue_data='{"version": 1, "run_id": null, "queue": []}'
    
    # 生成重置记录
    local reset_body=$(generate_queue_reset_record "$now" "$reason" "$reset_queue_data")
    
    # 更新issue
    if queue_manager_update_issue "$reset_body"; then
        debug "success" "Queue reset successful"
        _QUEUE_MANAGER_QUEUE_DATA="$reset_queue_data"
        return 0
    else
        debug "error" "Queue reset failed"
        return 1
    fi
}

# 公共方法：刷新队列数据
queue_manager_refresh() {
    debug "log" "Refreshing queue data..."
    queue_manager_load_data
}

# 公共方法：获取队列数据
queue_manager_get_data() {
    echo "$_QUEUE_MANAGER_QUEUE_DATA"
}

# 公共方法：获取队列长度
queue_manager_get_length() {
    echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '.queue | length // 0'
}

# 公共方法：检查队列是否为空
queue_manager_is_empty() {
    local length=$(queue_manager_get_length)
    if [ "$length" -eq 0 ]; then
        return 0  # 空
    else
        return 1  # 非空
    fi
}

# 通用函数：重试机制
retry_operation() {
    local max_retries="${1:-5}"
    local retry_delay="${2:-10}"
    local operation_name="$3"
    shift 3
    
    for attempt in $(seq 1 $max_retries); do
        debug "log" "Attempt $attempt of $max_retries for $operation_name..."
        
        if "$@"; then
            debug "success" "$operation_name successful on attempt $attempt"
            return 0
        else
            debug "error" "$operation_name failed on attempt $attempt"
            if [ "$attempt" -lt "$max_retries" ]; then
                debug "log" "Retrying in $retry_delay seconds..."
                sleep $retry_delay
            else
                debug "error" "Max retries reached for $operation_name"
                return 1
            fi
        fi
    done
}

# 主队列管理函数 - 供工作流调用
queue_manager() {
    local operation="$1"
    local issue_number="${2:-1}"
    shift 2
    
    # 初始化队列管理器
    queue_manager_init "$issue_number"
    
    case "$operation" in
        "status")
            queue_manager_get_status
            ;;
        "join")
            local build_id="$1"
            local trigger_type="$2"
            local trigger_data="$3"
            local queue_limit="${4:-5}"
            queue_manager_join_queue "$build_id" "$trigger_type" "$trigger_data" "$queue_limit"
            ;;
        "acquire")
            local build_id="$1"
            local queue_limit="${2:-5}"
            queue_manager_acquire_lock "$build_id" "$queue_limit"
            ;;
        "release")
            local build_id="$1"
            queue_manager_release_lock "$build_id"
            ;;
        "clean")
            queue_manager_clean_completed
            ;;
        "cleanup")
            queue_manager_full_cleanup
            ;;
        "check-lock")
            queue_manager_check_and_clean_current_lock
            ;;
        "reset")
            local reason="${1:-手动重置}"
            queue_manager_reset "$reason"
            ;;
        "auto-clean")
            queue_manager_auto_clean_expired
            ;;
        "refresh")
            queue_manager_refresh
            ;;
        "length")
            queue_manager_get_length
            ;;
        "empty")
            if queue_manager_is_empty; then
                echo "true"
            else
                echo "false"
            fi
            ;;
        "data")
            queue_manager_get_data
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
