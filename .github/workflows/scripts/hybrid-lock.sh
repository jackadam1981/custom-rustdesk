#!/bin/bash
# hybrid-lock.sh: 混合锁工具脚本
# 提供乐观锁和悲观锁的底层实现
# 被 queue-manager.sh 调用，不直接处理队列逻辑

# 加载调试工具
source .github/workflows/scripts/debug-utils.sh

# 锁配置参数
LOCK_MAX_RETRIES=3
LOCK_RETRY_DELAY=1
LOCK_MAX_WAIT_TIME=7200  # 2小时
LOCK_CHECK_INTERVAL=30   # 30秒
LOCK_TIMEOUT_HOURS=2     # 锁超时时间

# 乐观锁实现
optimistic_lock_acquire() {
    local resource_id="$1"
    local current_version="$2"
    local new_data="$3"
    local update_function="$4"
    
    debug "log" "Attempting optimistic lock acquisition for resource: $resource_id"
    
    for attempt in $(seq 1 $LOCK_MAX_RETRIES); do
        debug "log" "Optimistic lock attempt $attempt of $LOCK_MAX_RETRIES"
        
        # 调用更新函数，传入版本号进行版本检查
        if $update_function "$resource_id" "$current_version" "$new_data"; then
            debug "success" "Optimistic lock acquired successfully on attempt $attempt"
            return 0
        fi
        
        # 如果更新失败，等待后重试
        if [ "$attempt" -lt "$LOCK_MAX_RETRIES" ]; then
            debug "log" "Optimistic lock failed, retrying in $LOCK_RETRY_DELAY seconds..."
            sleep "$LOCK_RETRY_DELAY"
        fi
    done
    
    debug "error" "Failed to acquire optimistic lock after $LOCK_MAX_RETRIES attempts"
    return 1
}

# 悲观锁实现
pessimistic_lock_acquire() {
    local resource_id="$1"
    local lock_key="$2"
    local acquire_function="$3"
    local release_function="$4"
    
    debug "log" "Attempting pessimistic lock acquisition for resource: $resource_id, key: $lock_key"
    
    local start_time=$(date +%s)
    
    while [ $(($(date +%s) - start_time)) -lt $LOCK_MAX_WAIT_TIME ]; do
        # 尝试获取锁
        if $acquire_function "$resource_id" "$lock_key"; then
            debug "success" "Pessimistic lock acquired successfully"
            return 0
        fi
        
        # 检查是否已经持有锁
        if $acquire_function "$resource_id" "$lock_key" "check"; then
            debug "log" "Already holding pessimistic lock"
                    return 0
        fi
        
        debug "log" "Pessimistic lock not available, waiting $LOCK_CHECK_INTERVAL seconds..."
        sleep "$LOCK_CHECK_INTERVAL"
    done
    
    debug "error" "Timeout waiting for pessimistic lock"
    return 1
}

# 悲观锁释放
pessimistic_lock_release() {
    local resource_id="$1"
    local lock_key="$2"
    local release_function="$3"
    
    debug "log" "Releasing pessimistic lock for resource: $resource_id, key: $lock_key"
    
    if $release_function "$resource_id" "$lock_key"; then
        debug "success" "Pessimistic lock released successfully"
            return 0
    else
        debug "error" "Failed to release pessimistic lock"
        return 1
    fi
}

# 锁超时检查
check_lock_timeout() {
    local lock_data="$1"
    local timeout_hours="${2:-$LOCK_TIMEOUT_HOURS}"
    
    if [ -z "$lock_data" ] || ! echo "$lock_data" | jq . > /dev/null 2>&1; then
        debug "error" "Invalid lock data during timeout check"
        return 1
    fi
    
    local lock_timestamp=$(echo "$lock_data" | jq -r '.lock_timestamp // empty')
    local lock_holder=$(echo "$lock_data" | jq -r '.lock_holder // empty')
    
    if [ -n "$lock_timestamp" ] && [ -n "$lock_holder" ]; then
        local lock_time=$(date -d "$lock_timestamp" +%s 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local lock_duration_hours=$(( (current_time - lock_time) / 3600 ))
        
        if [ "$lock_duration_hours" -ge "$timeout_hours" ]; then
            debug "warning" "Lock timeout detected: ${lock_duration_hours} hours for holder: $lock_holder"
            return 0  # 需要清理
        fi
    fi
    
    return 1  # 不需要清理
}

# 版本冲突检测
check_version_conflict() {
    local expected_version="$1"
    local actual_version="$2"
    
    if [ "$expected_version" != "$actual_version" ]; then
        debug "warning" "Version conflict detected: expected $expected_version, got $actual_version"
        return 0  # 有冲突
    fi
    
    return 1  # 无冲突
}

# 锁状态验证
validate_lock_state() {
    local lock_data="$1"
    local expected_state="$2"
    
    if [ -z "$lock_data" ] || ! echo "$lock_data" | jq . > /dev/null 2>&1; then
        debug "error" "Invalid lock data for state validation"
        return 1
    fi
    
    local current_state=$(echo "$lock_data" | jq -r '.lock_state // empty')
    
    if [ "$current_state" = "$expected_state" ]; then
        debug "log" "Lock state validation passed: $current_state"
        return 0
    else
        debug "warning" "Lock state validation failed: expected $expected_state, got $current_state"
        return 1
    fi
}

# 锁信息生成
generate_lock_info() {
    local lock_holder="$1"
    local lock_type="$2"
    local resource_id="$3"
    
    local lock_info=$(jq -c -n \
        --arg holder "$lock_holder" \
        --arg type "$lock_type" \
        --arg resource "$resource_id" \
        --arg timestamp "$(date '+%Y-%m-%d %H:%M:%S')" \
        '{lock_holder: $holder, lock_type: $type, resource_id: $resource, lock_timestamp: $timestamp}')
    
    echo "$lock_info"
}

# 锁统计信息
get_lock_statistics() {
    local lock_data="$1"
    
    if [ -z "$lock_data" ] || ! echo "$lock_data" | jq . > /dev/null 2>&1; then
        echo "Invalid lock data"
        return 1
    fi
    
    local total_locks=$(echo "$lock_data" | jq '.locks | length // 0')
    local optimistic_locks=$(echo "$lock_data" | jq '.locks | map(select(.lock_type == "optimistic")) | length // 0')
    local pessimistic_locks=$(echo "$lock_data" | jq '.locks | map(select(.lock_type == "pessimistic")) | length // 0')
    
    echo "锁统计信息:"
    echo "  总锁数量: $total_locks"
    echo "  乐观锁: $optimistic_locks"
    echo "  悲观锁: $pessimistic_locks"
}

# 锁清理
cleanup_expired_locks() {
    local lock_data="$1"
    local timeout_hours="${2:-$LOCK_TIMEOUT_HOURS}"
    
    if [ -z "$lock_data" ] || ! echo "$lock_data" | jq . > /dev/null 2>&1; then
        debug "error" "Invalid lock data for cleanup"
        return 1
    fi
    
    local current_time=$(date +%s)
    local cleaned_locks=$(echo "$lock_data" | jq --arg current_time "$current_time" --arg timeout_hours "$timeout_hours" '
        .locks = (.locks | map(select(
            # 保留未超时的锁
            (($current_time | tonumber) - (.lock_timestamp | fromdateiso8601)) < ($timeout_hours | tonumber) * 3600
        )))
    ')
    
    echo "$cleaned_locks"
}

# 主混合锁工具函数
hybrid_lock_tool() {
    local operation="$1"
    shift
    
    case "$operation" in
        "optimistic_acquire")
            local resource_id="$1"
            local current_version="$2"
            local new_data="$3"
            local update_function="$4"
            optimistic_lock_acquire "$resource_id" "$current_version" "$new_data" "$update_function"
            ;;
        "pessimistic_acquire")
            local resource_id="$1"
            local lock_key="$2"
            local acquire_function="$3"
            local release_function="$4"
            pessimistic_lock_acquire "$resource_id" "$lock_key" "$acquire_function" "$release_function"
            ;;
        "pessimistic_release")
            local resource_id="$1"
            local lock_key="$2"
            local release_function="$3"
            pessimistic_lock_release "$resource_id" "$lock_key" "$release_function"
            ;;
        "check_timeout")
            local lock_data="$1"
            local timeout_hours="${2:-$LOCK_TIMEOUT_HOURS}"
            check_lock_timeout "$lock_data" "$timeout_hours"
            ;;
        "check_version")
            local expected_version="$1"
            local actual_version="$2"
            check_version_conflict "$expected_version" "$actual_version"
            ;;
        "validate_state")
            local lock_data="$1"
            local expected_state="$2"
            validate_lock_state "$lock_data" "$expected_state"
            ;;
        "generate_info")
            local lock_holder="$1"
            local lock_type="$2"
            local resource_id="$3"
            generate_lock_info "$lock_holder" "$lock_type" "$resource_id"
            ;;
        "get_stats")
            local lock_data="$1"
            get_lock_statistics "$lock_data"
            ;;
        "cleanup")
            local lock_data="$1"
            local timeout_hours="${2:-$LOCK_TIMEOUT_HOURS}"
            cleanup_expired_locks "$lock_data" "$timeout_hours"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
}
