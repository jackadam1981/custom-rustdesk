#!/bin/bash
# 队列管理脚本
# 这个文件包含所有队列操作功能
# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/encryption-utils.sh
source .github/workflows/scripts/issue-templates.sh

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

# 通用函数：从队列管理issue中提取JSON数据
extract_queue_json() {
  local issue_content="$1"
  
  # 提取 ```json ... ``` 代码块
  local json_data=$(echo "$issue_content" | jq -r '.body' | sed -n '/```json/,/```/p' | sed '1d;$d')
  json_data=$(echo "$json_data" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  
  # 验证JSON格式并返回
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
    debug "error" "Failed to update queue issue"
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

# 清理队列数据
cleanup_queue_data() {
  local queue_issue_number="$1"
  local cleanup_reason_text="$2"
  local current_version="$3"
  local queue_data="$4"
  shift 4
  local invalid_issues=("$@")
  
  debug "log" "Cleaning up queue data..."
  
  # 开始清理数据
  local cleaned_queue_data=$(echo "$queue_data" | \
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
  local final_queue_length=$(echo "$cleaned_queue_data" | jq '.queue | length // 0')
  
  debug "log" "Queue cleanup completed. Final queue length: $final_queue_length"
  
  # 更新队列管理issue
  local update_response=$(update_queue_issue_with_hybrid_lock "$queue_issue_number" "$cleaned_queue_data" "空闲 🔓" "空闲 🔓")
  
  if [ $? -eq 0 ]; then
    debug "success" "Queue cleanup successful"
    return 0
  else
    debug "error" "Queue cleanup failed"
    return 1
  fi
}

# 重置队列为默认状态
reset_queue_to_default() {
  local queue_issue_number="$1"
  local reason="$2"
  
  debug "log" "Resetting queue to default state: $reason"
  
  local now=$(date '+%Y-%m-%d %H:%M:%S')
  local reset_queue_data='{"version": 1, "run_id": null, "queue": []}'
  
  # 生成重置记录
  local reset_body=$(generate_queue_reset_record "$now" "$reason" "$reset_queue_data")
  
  # 更新issue
  if update_queue_issue "$queue_issue_number" "$reset_body"; then
    debug "success" "Queue reset successful"
    return 0
  else
    debug "error" "Queue reset failed"
    return 1
  fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ $# -lt 2 ]; then
    echo "Usage: $0 <operation> <issue_number> [parameters...]"
    echo "Operations: cleanup, reset"
    exit 1
  fi
  
  local operation="$1"
  local issue_number="$2"
  shift 2
  
  case "$operation" in
    "cleanup")
      cleanup_queue_data "$issue_number" "$@"
      ;;
    "reset")
      local reason="${1:-手动重置}"
      reset_queue_to_default "$issue_number" "$reason"
      ;;
    *)
      echo "Unknown operation: $operation"
      exit 1
      ;;
  esac
fi 
