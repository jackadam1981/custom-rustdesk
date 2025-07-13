#!/bin/bash

# 混合锁策略实�?# 排队阶段：乐观锁（快速重试）
# 构建阶段：悲观锁（确保独占）

# 配置参数
MAX_QUEUE_RETRIES=3
QUEUE_RETRY_DELAY=1
MAX_BUILD_WAIT_TIME=7200  # 2小时
BUILD_CHECK_INTERVAL=30   # 30�?LOCK_TIMEOUT_HOURS=2      # 锁超时时�?
# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 通用函数：从队列管理issue中提取JSON数据
extract_queue_json() {
    local issue_content="$1"
    echo "$issue_content" | jq -r '.body' | grep -oP '```json\s*\K[^{]*\{.*\}' | head -1
}

# 通用函数：获取队列管理issue内容
get_queue_manager_content() {
    local issue_number="$1"
    curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number"
}

# 通用函数：更新队列管理issue
update_queue_issue() {
    local issue_number="$1"
    local body="$2"
    
    curl -s -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number" \
        -d "$(jq -n --arg body "$body" '{"body": $body}')"
}

# 通用函数：更新队列管理issue（使用混合锁模板�?update_queue_issue_with_hybrid_lock() {
    local issue_number="$1"
    local queue_data="$2"
    local optimistic_lock_status="$3"
    local pessimistic_lock_status="$4"
    local current_build="${5:-无}"
    local lock_holder="${6:-无}"
    
    # 获取当前版本
    local version=$(echo "$queue_data" | jq -r '.version // 1')
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 使用混合锁模板生成正�?    source .github/workflows/scripts/issue-templates.sh
    local body=$(generate_hybrid_lock_status_body "$current_time" "$queue_data" "$version" "$optimistic_lock_status" "$pessimistic_lock_status" "$current_build" "$lock_holder")
    
    # 更新issue
    update_queue_issue "$issue_number" "$body"
}

# 乐观锁：尝试加入队列（快速重试）
join_queue_optimistic() {
    local build_id="$1"
    local trigger_type="$2"
    local trigger_data="$3"
    local queue_limit="$4"
    
    log_info "Starting optimistic queue join for build $build_id..."
    
    for attempt in $(seq 1 $MAX_QUEUE_RETRIES); do
        log_info "Queue join attempt $attempt of $MAX_QUEUE_RETRIES"
        
        # 获取最新队列数�?        local queue_manager_content=$(get_queue_manager_content "1")
        local queue_data=$(extract_queue_json "$queue_manager_content")
        
        if [ -z "$queue_data" ] || ! echo "$queue_data" | jq . > /dev/null 2>&1; then
            log_error "Invalid queue data, resetting queue"
            reset_queue_to_default "1" "队列数据无效，重置为默认模板"
            queue_manager_content=$(get_queue_manager_content "1")
            queue_data=$(extract_queue_json "$queue_manager_content")
        fi
        
        # 获取当前版本和状�?        local current_version=$(echo "$queue_data" | jq -r '.version // 1')
        local current_queue=$(echo "$queue_data" | jq -r '.queue // []')
        local queue_length=$(echo "$current_queue" | jq 'length // 0')
        
        # 检查队列限�?        if [ "$queue_length" -ge "$queue_limit" ]; then
            log_error "Queue is full (limit: $queue_limit)"
            echo "join_success=false" >> $GITHUB_OUTPUT
            echo "queue_position=-1" >> $GITHUB_OUTPUT
            return 1
        fi
        
        # 检查是否已在队列中
        local existing_item=$(echo "$current_queue" | jq -r --arg build_id "$build_id" '.[] | select(.build_id == $build_id) | .issue_number // empty')
        if [ -n "$existing_item" ]; then
            local queue_position=$(echo "$current_queue" | jq -r --arg build_id "$build_id" 'index(.[] | select(.build_id == $build_id)) + 1')
            log_warning "Already in queue at position: $queue_position"
            echo "join_success=true" >> $GITHUB_OUTPUT
            echo "queue_position=$queue_position" >> $GITHUB_OUTPUT
            return 0
        fi
        
        # 准备新队列项
        local current_time=$(date '+%Y-%m-%d %H:%M:%S')
        local parsed_trigger_data="$trigger_data"
        if [[ "$trigger_data" == \"*\" ]]; then
            parsed_trigger_data=$(echo "$trigger_data" | jq -r .)
        fi
        
        # 提取构建信息
        local tag=$(echo "$parsed_trigger_data" | jq -r '.tag // empty')
        local customer=$(echo "$parsed_trigger_data" | jq -r '.customer // empty')
        local customer_link=$(echo "$parsed_trigger_data" | jq -r '.customer_link // empty')
        local slogan=$(echo "$parsed_trigger_data" | jq -r '.slogan // empty')
        
        # 创建新队列项
        local new_queue_item=$(jq -c -n \
            --arg build_id "$build_id" \
            --arg build_title "Custom Rustdesk Build" \
            --arg trigger_type "$trigger_type" \
            --arg tag "$tag" \
            --arg customer "$customer" \
            --arg customer_link "$customer_link" \
            --arg slogan "$slogan" \
            --arg join_time "$current_time" \
            '{build_id: $build_id, build_title: $build_title, trigger_type: $trigger_type, tag: $tag, customer: $customer, customer_link: $customer_link, slogan: $slogan, join_time: $join_time}')
        
        # 尝试乐观更新：检查版本号
        local new_queue=$(echo "$current_queue" | jq --argjson new_item "$new_queue_item" '. + [$new_item]')
        local new_queue_data=$(echo "$queue_data" | jq --argjson new_queue "$new_queue" --arg new_version "$((current_version + 1))" '.queue = $new_queue | .version = ($new_version | tonumber)')
        
        # 尝试更新（使用混合锁模板�?        local update_response=$(update_queue_issue_with_hybrid_lock "1" "$new_queue_data" "占用 🔒" "空闲 🔓")
        
        # 验证更新是否成功
        if echo "$update_response" | jq -e '.id' > /dev/null 2>&1; then
            local queue_position=$((queue_length + 1))
            log_success "Successfully joined queue at position $queue_position"
            
            # 生成乐观锁通知
            source .github/workflows/scripts/issue-templates.sh
            local notification=$(generate_optimistic_lock_notification "加入队列" "$build_id" "$queue_position" "$(date '+%Y-%m-%d %H:%M:%S')" "$attempt")
            log_info "Optimistic lock notification: $notification"
            
            echo "join_success=true" >> $GITHUB_OUTPUT
            echo "queue_position=$queue_position" >> $GITHUB_OUTPUT
            return 0
        else
            log_warning "Update failed on attempt $attempt"
            if [ "$attempt" -lt "$MAX_QUEUE_RETRIES" ]; then
                log_info "Retrying in $QUEUE_RETRY_DELAY seconds..."
                sleep $QUEUE_RETRY_DELAY
            fi
        fi
    done
    
    log_error "Failed to join queue after $MAX_QUEUE_RETRIES attempts"
    echo "join_success=false" >> $GITHUB_OUTPUT
    echo "queue_position=-1" >> $GITHUB_OUTPUT
    return 1
}

# 悲观锁：等待并获取构建锁
acquire_build_lock_pessimistic() {
    local build_id="$1"
    local queue_issue_number="$2"
    
    log_info "Starting pessimistic lock acquisition for build $build_id..."
    
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        
        # 检查超�?        if [ "$elapsed_time" -gt "$MAX_BUILD_WAIT_TIME" ]; then
            log_error "Timeout waiting for lock (${MAX_BUILD_WAIT_TIME}s)"
            echo "lock_acquired=false" >> $GITHUB_OUTPUT
            return 1
        fi
        
        # 获取最新队列状�?        local queue_manager_content=$(get_queue_manager_content "$queue_issue_number")
        local queue_data=$(extract_queue_json "$queue_manager_content")
        
        if [ -z "$queue_data" ] || ! echo "$queue_data" | jq . > /dev/null 2>&1; then
            log_error "Invalid queue data"
            echo "lock_acquired=false" >> $GITHUB_OUTPUT
            return 1
        fi
        
        # 检查是否还在队列中
        local current_queue=$(echo "$queue_data" | jq -r '.queue // []')
        local current_queue_position=$(echo "$current_queue" | jq -r --arg build_id "$build_id" 'index(.[] | select(.build_id == $build_id)) + 1')
        
        if [ "$current_queue_position" = "null" ] || [ -z "$current_queue_position" ]; then
            log_error "Build removed from queue"
            echo "lock_acquired=false" >> $GITHUB_OUTPUT
            return 1
        fi
        
        # 检查锁状�?        local current_lock_run_id=$(echo "$queue_data" | jq -r '.run_id // null')
        local current_version=$(echo "$queue_data" | jq -r '.version // 1')
        
        # 检查是否轮到构建（队列第一位且没有锁）
        if [ "$current_queue_position" = "1" ] && [ "$current_lock_run_id" = "null" ]; then
            log_info "It's our turn to build! Attempting to acquire lock..."
            
            # 尝试获取�?            local updated_queue_data=$(echo "$queue_data" | jq --arg run_id "$build_id" --arg new_version "$((current_version + 1))" '.run_id = $run_id | .version = ($new_version | tonumber)')
            
            # 尝试更新（使用混合锁模板�?            local update_response=$(update_queue_issue_with_hybrid_lock "$queue_issue_number" "$updated_queue_data" "空闲 🔓" "占用 🔒" "$build_id" "$build_id")
            
            # 验证更新是否成功
            if echo "$update_response" | jq -e '.id' > /dev/null 2>&1; then
                # 确认锁已被自己持�?                local verify_content=$(get_queue_manager_content "$queue_issue_number")
                local verify_data=$(extract_queue_json "$verify_content")
                local verify_lock_run_id=$(echo "$verify_data" | jq -r '.run_id // null')
                
                if [ "$verify_lock_run_id" = "$build_id" ]; then
                    log_success "Lock acquired successfully by build $build_id"
                    
                    # 生成悲观锁通知
                    source .github/workflows/scripts/issue-templates.sh
                    local wait_duration=$((elapsed_time))
                    local notification=$(generate_pessimistic_lock_notification "获取�? "$build_id" "$wait_duration" "$(date '+%Y-%m-%d %H:%M:%S')" "占用 🔒")
                    log_info "Pessimistic lock notification: $notification"
                    
                    echo "lock_acquired=true" >> $GITHUB_OUTPUT
                    return 0
                else
                    log_warning "Lock acquisition verification failed"
                fi
            else
                log_warning "Lock acquisition update failed"
            fi
        elif [ "$current_lock_run_id" != "null" ] && [ "$current_lock_run_id" != "$build_id" ]; then
            log_info "Another build is running (lock: $current_lock_run_id), waiting..."
        else
            log_info "Waiting in queue position $current_queue_position..."
        fi
        
        # 等待后再次检�?        log_info "Waiting $BUILD_CHECK_INTERVAL seconds before next check..."
        sleep $BUILD_CHECK_INTERVAL
    done
}

# 释放构建�?release_build_lock() {
    local build_id="$1"
    local queue_issue_number="$2"
    
    log_info "Releasing build lock for build $build_id..."
    
    # 获取当前队列状�?    local queue_manager_content=$(get_queue_manager_content "$queue_issue_number")
    local queue_data=$(extract_queue_json "$queue_manager_content")
    
    if [ -z "$queue_data" ] || ! echo "$queue_data" | jq . > /dev/null 2>&1; then
        log_error "Invalid queue data during lock release"
        return 1
    fi
    
    # 检查是否是锁持有�?    local current_lock_run_id=$(echo "$queue_data" | jq -r '.run_id // null')
    local current_version=$(echo "$queue_data" | jq -r '.version // 1')
    
    if [ "$current_lock_run_id" = "$build_id" ]; then
        # 释放�?        local updated_queue_data=$(echo "$queue_data" | jq --arg new_version "$((current_version + 1))" '.run_id = null | .version = ($new_version | tonumber)')
        
        # 尝试更新（使用混合锁模板�?        local update_response=$(update_queue_issue_with_hybrid_lock "$queue_issue_number" "$updated_queue_data" "空闲 🔓" "空闲 🔓")
        
        # 验证更新是否成功
        if echo "$update_response" | jq -e '.id' > /dev/null 2>&1; then
            log_success "Build lock released successfully"
            
            # 生成悲观锁通知
            source .github/workflows/scripts/issue-templates.sh
            local notification=$(generate_pessimistic_lock_notification "释放�? "$build_id" "0" "$(date '+%Y-%m-%d %H:%M:%S')" "空闲 🔓")
            log_info "Pessimistic lock release notification: $notification"
            
            return 0
        else
            log_error "Failed to release lock"
            return 1
        fi
    else
        log_warning "Not lock owner (current: $current_lock_run_id, expected: $build_id), skipping lock release"
        return 0
    fi
}

# 检查锁超时
check_lock_timeout() {
    local queue_issue_number="$1"
    
    log_info "Checking for lock timeout..."
    
    local queue_manager_content=$(get_queue_manager_content "$queue_issue_number")
    local queue_data=$(extract_queue_json "$queue_manager_content")
    
    if [ -z "$queue_data" ] || ! echo "$queue_data" | jq . > /dev/null 2>&1; then
        log_error "Invalid queue data during timeout check"
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
                log_warning "Lock timeout detected: ${lock_duration_hours} hours"
                return 0  # 需要清�?            fi
        fi
    fi
    
    return 1  # 不需要清�?}

# 重置队列为默认状�?reset_queue_to_default() {
    local queue_issue_number="$1"
    local reason="$2"
    
    log_info "Resetting queue to default state: $reason"
    
    local default_queue_data='{"version": 1, "run_id": null, "queue": []}'
    
    # 使用混合锁模板重置队�?    local update_response=$(update_queue_issue_with_hybrid_lock "$queue_issue_number" "$default_queue_data" "空闲 🔓" "空闲 🔓")
    
    if echo "$update_response" | jq -e '.id' > /dev/null 2>&1; then
        log_success "Queue reset successfully"
        
        # 生成重置通知
        source .github/workflows/scripts/issue-templates.sh
        local notification=$(generate_queue_reset_notification "$reason" "$(date '+%Y-%m-%d %H:%M:%S')")
        log_info "Queue reset notification: $notification"
        
        return 0
    else
        log_error "Failed to reset queue"
        return 1
    fi
}

# 主函数：混合锁策�?main_hybrid_lock() {
    local action="$1"
    local build_id="$2"
    local trigger_type="$3"
    local trigger_data="$4"
    local queue_limit="${5:-5}"
    
    case "$action" in
        "join_queue")
            log_info "Executing optimistic queue join"
            join_queue_optimistic "$build_id" "$trigger_type" "$trigger_data" "$queue_limit"
            ;;
        "acquire_lock")
            log_info "Executing pessimistic lock acquisition"
            acquire_build_lock_pessimistic "$build_id" "1"
            ;;
        "release_lock")
            log_info "Executing lock release"
            release_build_lock "$build_id" "1"
            ;;
        "check_timeout")
            log_info "Executing timeout check"
            check_lock_timeout "1"
            ;;
        "reset_queue")
            local reason="${3:-队列重置}"
            log_info "Executing queue reset"
            reset_queue_to_default "1" "$reason"
            ;;
        *)
            log_error "Unknown action: $action"
            echo "Usage: $0 {join_queue|acquire_lock|release_lock|check_timeout|reset_queue}"
            exit 1
            ;;
    esac
}

# 如果直接运行此脚�?if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_hybrid_lock "$@"
fi 
