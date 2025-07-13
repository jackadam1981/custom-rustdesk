#!/bin/bash
# 队列管理脚本
# 这个文件包含所有队列操作功�?
# 加载依赖脚本
source .github/workflows/scripts/encryption-utils.sh
source .github/workflows/scripts/issue-templates.sh

# 通用函数：重试机制
retry_operation() {
  local max_retries="${1:-5}"
  local retry_delay="${2:-10}"
  local operation_name="$3"
  shift 3
  
  for attempt in $(seq 1 $max_retries); do
    echo "Attempt $attempt of $max_retries for $operation_name..."
    
    if "$@"; then
      echo "$operation_name successful on attempt $attempt"
      return 0
    else
      echo "$operation_name failed on attempt $attempt"
      if [ "$attempt" -lt "$max_retries" ]; then
        echo "Retrying in $retry_delay seconds..."
        sleep $retry_delay
      else
        echo "Max retries reached for $operation_name"
        return 1
      fi
    fi
  done
}

# 通用函数：从队列管理issue中提取JSON数据
extract_queue_json() {
  local issue_content="$1"
  
  # 提取 ```json ... ``` 代码块
  local json_data=$(echo "$issue_content" | jq -r '.body' | sed -n '/```json/,/```/p' | sed '1d;$d')
  json_data=$(echo "$json_data" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  
  # 验证JSON格式并返回
  if [ -n "$json_data" ] && echo "$json_data" | jq . > /dev/null 2>&1; then
    echo "$json_data" | jq -c .
  else
    echo '{"queue":[],"run_id":null,"version":1}'
  fi
}

# 通用函数：验证JSON格式
validate_json() {
  local json_data="$1"
  local context="$2"
  
  if [ -z "$json_data" ]; then
    echo "Failed to extract $context JSON, aborting."
    exit 1
  fi
  
  if ! echo "$json_data" | jq . > /dev/null 2>&1; then
    echo "Invalid JSON format in $context data, aborting."
    exit 1
  fi
  
  # 强制单行JSON
  echo "$json_data" | jq -c .
}

# 通用函数：获取队列管理issue内容
get_queue_manager_content() {
  local queue_issue_number="${1:-1}"
  
  local content=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$queue_issue_number")
  
  # 检查issue是否存在
  if echo "$content" | jq -e '.message' | grep -q "Not Found"; then
    echo "Queue manager issue #$queue_issue_number not found"
    exit 1
  fi
  
  echo "$content"
}

# 通用函数：更新队列管理issue
update_queue_issue() {
  local queue_issue_number="${1:-1}"
  local body="$2"
  local response=$(curl -s -X PATCH \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -d "{\"body\":\"$body\"}" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$queue_issue_number")
  
  if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
    echo "Failed to update issue #$queue_issue_number"
    return 1
  fi
  
  echo "Issue #$queue_issue_number updated successfully"
  return 0
}

# 通用函数：添加issue评论
add_issue_comment() {
  local issue_number="$1"
  local comment="$2"
  
  local response=$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -d "{\"body\":\"$comment\"}" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/comments")
  
  if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
    echo "Failed to add comment to issue #$issue_number"
    return 1
  fi
  
  echo "Comment added to issue #$issue_number"
  return 0
}

# 通用函数：仅 issue 触发时添加 issue 评论
add_issue_comment_if_issue_trigger() {
  local trigger_type="$1"
  local issue_number="$2"
  local comment="$3"
  
  if [ "$trigger_type" = "issue" ]; then
    add_issue_comment "$issue_number" "$comment"
  else
    echo "⚠️ Not an issue trigger, skipping comment"
  fi
}

# 重置队列到默认状态
reset_queue_to_default() {
  local queue_issue_number="${1:-1}"
  local reason="${2:-队列重置}"
  
  echo "Resetting queue to default state..."
  
  # 创建默认队列数据
  local reset_queue_data='{"queue":[],"run_id":null,"version":1}'
  local now=$(date '+%Y-%m-%d %H:%M:%S')
  
  # 生成重置记录
  local reset_body=$(generate_queue_reset_record "$now" "$reason" "$reset_queue_data")
  
  # 更新issue
  if update_queue_issue "$queue_issue_number" "$reset_body"; then
    echo "Queue reset successful"
    return 0
  else
    echo "Queue reset failed"
    return 1
  fi
}

# 清理队列数据
cleanup_queue_data() {
  local queue_issue_number="$1"
  local cleanup_reason_text="$2"
  local current_version="$3"
  local queue_data="$4"
  shift 4
  local invalid_issues=("$@")
  
  echo "Cleaning up queue data..."
  
  # 开始清理数�?  local cleaned_queue_data=$(echo "$queue_data" | \
    jq --arg new_version "$((current_version + 1))" '
    # 移除重复项
    .queue = (.queue | group_by(.build_id) | map(.[0]))
    # 重置异常项
    | .run_id = null
    | .version = ($new_version | tonumber)
  ')
  
  # 移除无效issue
  if [ ${#invalid_issues[@]} -gt 0 ]; then
    for invalid_issue in "${invalid_issues[@]}"; do
      cleaned_queue_data=$(echo "$cleaned_queue_data" | \
        jq --arg build_id "$invalid_issue" \
        '.queue = (.queue | map(select(.build_id != $build_id)))')
    done
  fi

  # 检查 workflow_dispatch 类型 run 是否已结束
  local expired_runs=()
  local queue_json=$(echo "$cleaned_queue_data" | jq -c '.queue')
  for run_id in $(echo "$queue_json" | jq -r '.[] | select(.trigger_type == "workflow_dispatch") | .build_id'); do
    local run_response=$(curl -s \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$run_id")
    if echo "$run_response" | jq -e '.message' | grep -q "Not Found"; then
      expired_runs+=("$run_id")
    else
      local run_status=$(echo "$run_response" | jq -r '.status // "unknown"')
      if [ "$run_status" = "completed" ] || [ "$run_status" = "cancelled" ] || [ "$run_status" = "failure" ] || [ "$run_status" = "skipped" ]; then
        expired_runs+=("$run_id")
      fi
    fi
  done
  
  # 移除已结束、无效的 workflow_dispatch 队列项
  if [ ${#expired_runs[@]} -gt 0 ]; then
    for expired_run in "${expired_runs[@]}"; do
      cleaned_queue_data=$(echo "$cleaned_queue_data" | jq --arg run_id "$expired_run" '.queue = (.queue | map(select(.build_id != $run_id)))')
    done
  fi
  
  # 计算清理后的队列数量
  local cleaned_total_count=$(echo "$cleaned_queue_data" | jq '.queue | length // 0')
  local cleaned_issue_count=$(echo "$cleaned_queue_data" | jq '.queue | map(select(.trigger_type == "issue")) | length // 0')
  local cleaned_workflow_count=$(echo "$cleaned_queue_data" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0')
  
  # 更新队列管理issue
  local current_time=$(date '+%Y-%m-%d %H:%M:%S')
  local current_version=$(echo "$cleaned_queue_data" | jq -r '.version')
  local cleaned_queue_data_single=$(echo "$cleaned_queue_data" | jq -c .)
  
  # 生成清理记录
  local updated_body=$(generate_queue_cleanup_record "$current_time" "$current_version" "$cleaned_total_count" "$cleaned_issue_count" "$cleaned_workflow_count" "$cleanup_reason_text" "$cleaned_queue_data_single")
  
  # 尝试更新队列管理issue
  if update_queue_issue "$queue_issue_number" "$updated_body"; then
    echo "Queue data cleanup successful"
    return 0
  else
    echo "Queue data cleanup failed"
    return 1
  fi
}

# 更新队列管理 issue 正文
update_queue_issue_body() {
    local queue_issue_number="$1"
    local queue_data="$2"
    local version="$3"
    
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local lock_status="空闲 🔓"
    local current_build="无"
    local lock_holder="无"
    
    # 检查是否有 run_id
    local run_id=$(echo "$queue_data" | jq -r '.run_id // null')
    if [ "$run_id" != "null" ]; then
        lock_status="占用 🔒"
        current_build="Custom Rustdesk Build"
        lock_holder="$run_id"
    fi
    
    # 生成正文
    local body=$(generate_queue_management_body "$current_time" "$queue_data" "$lock_status" "$current_build" "$lock_holder" "$version")
    
    # 更新 issue
    update_queue_issue "$queue_issue_number" "$body"
}

# 执行队列清理
perform_queue_cleanup() {
    local queue_issue_number="$1"
    local queue_data="$2"
    local version="$3"
    
    local queue=$(echo "$queue_data" | jq -r '.queue // []')
    local run_id=$(echo "$queue_data" | jq -r '.run_id // null')
    
    local need_cleanup=false
    local cleanup_reasons=()
    
    # 检查锁超时
    if [ "$run_id" != "null" ]; then
        local lock_join_time=$(echo "$queue" | \
            jq -r --arg run_id "$run_id" \
            '.[] | select(.issue_number == $run_id) | .join_time // empty' 2>/dev/null || echo "")
        
        if [ -n "$lock_join_time" ]; then
            local join_timestamp=$(date -d "$lock_join_time" +%s 2>/dev/null || echo "0")
            local current_timestamp=$(date +%s)
            local lock_duration_hours=$(( (current_timestamp - join_timestamp) / 3600 ))
            
            if [ "$lock_duration_hours" -ge 2 ]; then
                need_cleanup=true
                cleanup_reasons+=("锁超时：已占用 {lock_duration_hours} 小时")
            fi
        else
            need_cleanup=true
            cleanup_reasons+=("锁异常：找不到锁持有时间")
        fi
    fi
    
    # 检查重复项
    if [ "$(echo "$queue" | jq -r 'type')" = "array" ]; then
        local duplicate_items=$(echo "$queue" | \
            jq -r 'group_by(.issue_number) | .[] | select(length > 1) | .[0].issue_number' 2>/dev/null || echo "")
        
        if [ -n "$duplicate_items" ]; then
            need_cleanup=true
            cleanup_reasons+=("队列重复：构建项 $duplicate_items 重复")
        fi
    fi
    
    # 检查无效 issue
    if [ "$(echo "$queue" | jq -r 'type')" = "array" ]; then
        local invalid_issues=()
        for issue_number in $(echo "$queue" | jq -r '.[].issue_number'); do
            local issue_response=$(curl -s \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number")
            
            if echo "$issue_response" | jq -e '.message' | grep -q "Not Found"; then
                invalid_issues+=("$issue_number")
            fi
        done
        
        if [ ${#invalid_issues[@]} -gt 0 ]; then
            need_cleanup=true
            cleanup_reasons+=("无效issue ${invalid_issues[*]} 不存在")
        fi
    fi
    
    # 检查已结束的 workflow_dispatch 类型 run
    if [ "$(echo "$queue" | jq -r 'type')" = "array" ]; then
        local expired_runs=()
        for run_id in $(echo "$queue" | jq -r '.[] | select(.trigger_type == "workflow_dispatch") | .issue_number'); do
            local run_response=$(curl -s \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$run_id")
            
            if echo "$run_response" | jq -e '.message' | grep -q "Not Found"; then
                expired_runs+=("$run_id")
            else
                local run_status=$(echo "$run_response" | jq -r '.status // "unknown"')
                if [ "$run_status" = "completed" ] || [ "$run_status" = "cancelled" ] || [ "$run_status" = "failure" ] || [ "$run_status" = "skipped" ]; then
                    expired_runs+=("$run_id")
                fi
            fi
        done
        
        if [ ${#expired_runs[@]} -gt 0 ]; then
            need_cleanup=true
            cleanup_reasons+=("已结束的 workflow_dispatch 类型 run ${expired_runs[*]} 已完结、取消、失败、跳过或不存在")
        fi
    fi
    
    # 执行清理
    if [ "$need_cleanup" = true ]; then
        echo "Performing queue cleanup..."
        echo "Cleanup reasons: ${cleanup_reasons[*]}"
        
        # 生成清理原因文本
        local cleanup_reason_text=$(generate_cleanup_reasons "${cleanup_reasons[@]}")
        
        # 使用工具函数清理队列数据
        cleanup_queue_data "$queue_issue_number" "$cleanup_reason_text" "$version" "$queue_data" "${invalid_issues[@]}" "${expired_runs[@]}"
    else
        echo "No cleanup needed, queue is healthy"
    fi
}

# 加入队列操作（使用混合锁策略）
join_queue() {
    local build_id="$1"
    local trigger_type="$2"
    local trigger_data="$3"
    local queue_limit="$4"
    
    echo "Starting hybrid lock queue join process..."
    
    # 使用混合锁策略的乐观锁加入队�?    source .github/workflows/scripts/hybrid-lock.sh
    main_hybrid_lock "join_queue" "$build_id" "$trigger_type" "$trigger_data" "$queue_limit"
    
    # 检查结果
    if [ "$(echo "$join_success" | tail -1)" = "true" ]; then
        echo "Successfully joined queue using optimistic lock"
        return 0
    else
        echo "Failed to join queue"
        return 1
    fi
}

# 等待队列轮到构建（使用混合锁策略）
wait_for_queue_turn() {
    local build_id="$1"
    local queue_issue_number="$2"
    
    echo "Starting hybrid lock queue wait process..."
    
    # 使用混合锁策略的悲观锁获取构建锁
    source .github/workflows/scripts/hybrid-lock.sh
    main_hybrid_lock "acquire_lock" "$build_id" "$queue_issue_number"
    
    # 检查结果
    if [ "$(echo "$lock_acquired" | tail -1)" = "true" ]; then
        echo "Successfully acquired build lock using pessimistic lock"
        return 0
    else
        echo "Failed to acquire build lock"
        return 1
    fi
} 
