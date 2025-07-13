#!/bin/bash
# GitHub API 工具函数
# 这个文件包含通用的GitHub API调用和队列操作函数

# AES 加密/解密函数
# ENCRYPTION_KEY 由 workflow 通过 ${{ secrets.ENCRYPTION_KEY }} 传入环境变量

# 加密函数：将 JSON 数据加密为 base64 字符串
encrypt_params() {
  local json_data="$1"
  local encryption_key="${ENCRYPTION_KEY}"
  
  if [ -z "$json_data" ]; then
    echo "❌ No data to encrypt"
    return 1
  fi
  
  if [ -z "$encryption_key" ]; then
    echo "❌ ENCRYPTION_KEY not set"
    return 1
  fi
  
  local iv=$(openssl rand -hex 16)
  local encrypted=$(echo -n "$json_data" | openssl enc -aes-256-cbc -iv "$iv" -K "$encryption_key" -base64 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "❌ Encryption failed"
    return 1
  fi
  echo "${iv}:${encrypted}"
}

# 解密函数：将加密的 base64 字符串解密为 JSON 数据
decrypt_params() {
  local encrypted_data="$1"
  local encryption_key="${ENCRYPTION_KEY}"
  
  if [ -z "$encrypted_data" ]; then
    echo "❌ No data to decrypt"
    return 1
  fi
  
  if [ -z "$encryption_key" ]; then
    echo "❌ ENCRYPTION_KEY not set"
    return 1
  fi
  
  local iv=$(echo "$encrypted_data" | cut -d: -f1)
  local encrypted=$(echo "$encrypted_data" | cut -d: -f2-)
  if [ -z "$iv" ] || [ -z "$encrypted" ]; then
    echo "❌ Invalid encrypted data format"
    return 1
  fi
  local decrypted=$(echo "$encrypted" | openssl enc -aes-256-cbc -d -iv "$iv" -K "$encryption_key" -base64 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "❌ Decryption failed"
    return 1
  fi
  echo "$decrypted"
}

# 生成新的加密密钥（用于初始化）
generate_encryption_key() {
  openssl rand -hex 32
}

# 通用函数：从队列管理issue中提取JSON数据（支持加密）
extract_queue_json() {
  local issue_content="$1"
  local decrypt_encrypted="${2:-false}"
  
  # 提取JSON数据
  local json_data=$(echo "$issue_content" | jq -r '.body' | grep -oP '```json\s*\K[^{]*\{.*\}' | head -1)
  
  if [ "$decrypt_encrypted" = "true" ]; then
    # 检查是否包含加密参数
    local encrypted_params=$(echo "$json_data" | jq -r '.encrypted_params // empty')
    
    if [ -n "$encrypted_params" ]; then
      echo "🔐 Found encrypted parameters, decrypting..."
      
      # 解密参数
      local decrypted_params=$(decrypt_params "$encrypted_params" "${ENCRYPTION_KEY}")
      if [ $? -ne 0 ]; then
        echo "❌ Failed to decrypt parameters"
        return 1
      fi
      
      # 将解密后的参数合并到JSON中
      local decrypted_json=$(echo "$decrypted_params" | jq -c .)
      json_data=$(echo "$json_data" | jq --argjson params "$decrypted_json" '. + $params | del(.encrypted_params)')
    fi
  fi
  
  echo "$json_data"
}

# 通用函数：验证JSON格式
validate_json() {
  local json_data="$1"
  local context="$2"
  
  if [ -z "$json_data" ]; then
    echo "❌ Failed to extract $context JSON, aborting."
    exit 1
  fi
  
  if ! echo "$json_data" | jq . > /dev/null 2>&1; then
    echo "❌ Invalid JSON format in $context data, aborting."
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
    echo "❌ Queue manager issue #$queue_issue_number not found"
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
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$queue_issue_number" \
    -d "$(jq -n --arg body "$body" '{"body": $body}')")
  
  # 验证更新是否成功
  if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
    echo "✅ Queue update successful"
    return 0
  else
    echo "❌ Queue update failed"
    return 1
  fi
}

# 通用函数：添加issue评论
add_issue_comment() {
  local issue_number="$1"
  local comment="$2"
  
  curl -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/comments" \
    -d "$(jq -n --arg body "$comment" '{"body": $body}')"
}

# 通用函数：重试机制
retry_operation() {
  local max_retries="${1:-5}"
  local retry_delay="${2:-10}"
  local operation_name="$3"
  shift 3
  
  for attempt in $(seq 1 $max_retries); do
    echo "Attempt $attempt of $max_retries for $operation_name..."
    
    if "$@"; then
      echo "✅ $operation_name successful on attempt $attempt"
      return 0
    else
      echo "❌ $operation_name failed on attempt $attempt"
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

# 通用函数：检查IP地址是否为私有IP
check_private_ip() {
  local input="$1"
  local ip="$input"
  
  # 移除协议前缀
  ip="${ip#http://}"
  ip="${ip#https://}"
  
  # 移除端口号（如果有）
  ip=$(echo "$ip" | cut -d: -f1)
  
  echo "Checking IP: $ip (from: $input)"
  
  # 检查10.0.0.0/8
  if [[ "$ip" =~ ^10\. ]]; then
    echo "✅ 10.x.x.x private IP detected"
    return 0
  fi
  
  # 检查172.16.0.0/12
  if [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
    echo "✅ 172.16-31.x.x private IP detected"
    return 0
  fi
  
  # 检查192.168.0.0/16
  if [[ "$ip" =~ ^192\.168\. ]]; then
    echo "✅ 192.168.x.x private IP detected"
    return 0
  fi
  
  echo "❌ Public IP or domain detected: $ip"
  return 1
}

# 通用函数：验证服务器参数格式
validate_server_parameters() {
  local rendezvous_server="$1"
  local api_server="$2"
  local email="$3"
  
  # 检查是否为有效的IP或域名格式
  is_valid_ip() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]+)?$ ]]
  }
  
  is_valid_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(:[0-9]+)?$ ]]
  }
  
  is_valid_url() {
    local url="$1"
    url="${url#http://}"
    url="${url#https://}"
    is_valid_ip "$url" || is_valid_domain "$url"
  }
  
  is_email() {
    [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
  }
  
  # 调试输出
  echo "Validating parameters:"
  echo "RENDEZVOUS_SERVER: $rendezvous_server"
  echo "API_SERVER: $api_server"
  echo "EMAIL: $email"
  
  local auto_reject_reason=""
  
  # 检查rendezvous_server格式
  if ! is_valid_ip "$rendezvous_server" && ! is_valid_domain "$rendezvous_server"; then
    auto_reject_reason="${auto_reject_reason}• rendezvous_server 格式无效: $rendezvous_server\n"
    echo "❌ rendezvous_server format invalid"
  else
    echo "✅ rendezvous_server format valid"
  fi
  
  # 检查api_server格式
  if ! is_valid_url "$api_server"; then
    auto_reject_reason="${auto_reject_reason}• api_server 格式无效: $api_server\n"
    echo "❌ api_server format invalid"
  else
    echo "✅ api_server format valid"
  fi
  
  # 检查email（如果提供）
  if [ -n "$email" ] && ! is_email "$email"; then
    auto_reject_reason="${auto_reject_reason}• email 格式非法: $email\n"
    echo "❌ email validation failed"
  else
    echo "✅ email validation passed"
  fi
  
  # 去掉最后多余的空行
  auto_reject_reason=$(echo "$auto_reject_reason" | sed '/^$/d')
  
  if [ -n "$auto_reject_reason" ]; then
    echo "自动拒绝原因：$auto_reject_reason"
    echo "$auto_reject_reason"
    return 1
  else
    echo "✅ All parameter validations passed"
    return 0
  fi
}

# 通用函数：重置队列到默认状态
reset_queue_to_default() {
  local queue_issue_number="${1:-1}"
  local reason="${2:-自动重置}"
  
  echo "Resetting queue to default state..."
  echo "Queue issue: #$queue_issue_number"
  echo "Reason: $reason"
  
  # 默认队列数据
  local reset_queue_data='{"queue":[],"run_id":null,"version":1}'
  local now=$(date '+%Y-%m-%d %H:%M:%S')
  
  # 构建重置后的issue内容
  local reset_body="## 构建队列管理

**最后更新时间：** $now

### 当前状态
- **构建锁状态：** 空闲 🔓
- **当前构建：** 无
- **锁持有者：** 无
- **版本：** 1

### 构建队列
- **当前数量：** 0/5
- **Issue触发：** 0/3
- **手动触发：** 0/5

---

### 重置记录
**重置时间：** $now
**重置原因：** $reason

### 队列数据
\`\`\`json
$reset_queue_data
\`\`\`"
  
  # 使用通用函数更新队列issue
  if update_queue_issue "$queue_issue_number" "$reset_body"; then
    echo "✅ Queue reset successful"
    return 0
  else
    echo "❌ Queue reset failed"
    return 1
  fi
}



# 通用函数：清理队列数据
cleanup_queue_data() {
  local queue_issue_number="$1"
  local cleanup_reason_text="$2"
  local current_version="$3"
  local queue_data="$4"
  shift 4
  local invalid_issues=("$@")
  
  echo "Cleaning up queue data..."
  
  # 开始清理数据
  local cleaned_queue_data=$(echo "$queue_data" | \
    jq --arg new_version "$((current_version + 1))" '
    # 移除重复项
    .queue = (.queue | group_by(.build_id) | map(.[0]))
    # 重置异常锁
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
  
  # 计算清理后的队列数量
  local cleaned_total_count=$(echo "$cleaned_queue_data" | jq '.queue | length // 0')
  local cleaned_issue_count=$(echo "$cleaned_queue_data" | jq '.queue | map(select(.trigger_type == "issue")) | length // 0')
  local cleaned_workflow_count=$(echo "$cleaned_queue_data" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0')
  
  echo "Cleaned queue data: $cleaned_queue_data"
  echo "Cleaned counts - Total: $cleaned_total_count, Issue: $cleaned_issue_count, Workflow: $cleaned_workflow_count"
  
  # 更新队列管理issue
  local updated_body="## 构建队列管理

**最后更新时间：** $(date '+%Y-%m-%d %H:%M:%S')

### 当前状态
- **构建锁状态：** 空闲 🔓 (已清理)
- **当前构建：** 无
- **锁持有者：** 无
- **版本：** $(echo "$cleaned_queue_data" | jq -r '.version')

### 构建队列
- **当前数量：** $cleaned_total_count/5
- **Issue触发：** $cleaned_issue_count/3
- **手动触发：** $cleaned_workflow_count/5

---

### 清理记录
**清理时间：** $(date '+%Y-%m-%d %H:%M:%S')
**清理原因：**
$cleanup_reason_text
### 队列数据
\`\`\`json
$cleaned_queue_data
\`\`\`"
  
  # 尝试更新队列管理issue
  if update_queue_issue "$queue_issue_number" "$updated_body"; then
    echo "✅ Queue data cleanup successful"
    echo "Queue cleanup completed successfully!"
    echo "Cleaned total count: $cleaned_total_count"
    echo "Cleaned issue count: $cleaned_issue_count"
    echo "Cleaned workflow count: $cleaned_workflow_count"
    return 0
  else
    echo "❌ Queue data cleanup failed"
    return 1
  fi
}

# 通用函数：更新队列中项目的状态
update_queue_status() {
  local project_name="$1"
  local status="$2"
  local queue_issue_number="${3:-1}"
  
  echo "Updating queue status for project: $project_name"
  echo "New status: $status"
  
  # 获取当前队列数据
  local queue_content=$(get_queue_manager_content "$queue_issue_number")
  local queue_data=$(extract_queue_json "$queue_content")
  local validated_queue_data=$(validate_json "$queue_data" "queue")
  
  # 更新项目状态
  local updated_queue_data=$(echo "$validated_queue_data" | \
    jq --arg project "$project_name" --arg status "$status" '
    .queue = (.queue | map(
      if .build_title == $project then
        . + {"status": $status, "updated_at": now | strftime("%Y-%m-%d %H:%M:%S")}
      else
        .
      end
    ))
  ')
  
  # 如果状态是completed，释放构建锁
  if [ "$status" = "completed" ]; then
    updated_queue_data=$(echo "$updated_queue_data" | jq '.run_id = null')
    echo "Build completed, releasing build lock"
  fi
  
  # 计算更新后的队列数量
  local total_count=$(echo "$updated_queue_data" | jq '.queue | length // 0')
  local issue_count=$(echo "$updated_queue_data" | jq '.queue | map(select(.trigger_type == "issue")) | length // 0')
  local workflow_count=$(echo "$updated_queue_data" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0')
  
  # 构建锁状态
  local lock_status="空闲 🔓"
  local current_build="无"
  local lock_holder="无"
  
  if [ "$(echo "$updated_queue_data" | jq -r '.run_id // "null"')" != "null" ]; then
    lock_status="占用 🔒"
    current_build=$(echo "$updated_queue_data" | jq -r '.queue[] | select(.status == "building") | .build_title // "未知"')
    lock_holder=$(echo "$updated_queue_data" | jq -r '.queue[] | select(.status == "building") | .build_id // "未知"')
  fi
  
  # 更新队列管理issue
  local updated_body="## 构建队列管理

**最后更新时间：** $(date '+%Y-%m-%d %H:%M:%S')

### 当前状态
- **构建锁状态：** $lock_status
- **当前构建：** $current_build
- **锁持有者：** $lock_holder
- **版本：** $(echo "$updated_queue_data" | jq -r '.version')

### 构建队列
- **当前数量：** $total_count/5
- **Issue触发：** $issue_count/3
- **手动触发：** $workflow_count/5

---

### 状态更新记录
**更新时间：** $(date '+%Y-%m-%d %H:%M:%S')
**项目：** $project_name
**新状态：** $status

### 队列数据
\`\`\`json
$updated_queue_data
\`\`\`"
  
  # 更新队列管理issue
  if update_queue_issue "$queue_issue_number" "$updated_body"; then
    echo "✅ Queue status update successful for $project_name"
    return 0
  else
    echo "❌ Queue status update failed for $project_name"
    return 1
  fi
}

# 通用函数：创建包含加密参数的队列数据
create_encrypted_queue_data() {
  local queue_data="$1"
  local sensitive_params="$2"
  
  if [ -z "$queue_data" ]; then
    echo "❌ Queue data not provided"
    return 1
  fi
  
  # 加密敏感参数
  local encrypted_params=""
  if [ -n "$sensitive_params" ]; then
    encrypted_params=$(encrypt_params "$sensitive_params" "${ENCRYPTION_KEY}")
    if [ $? -ne 0 ]; then
      echo "❌ Failed to encrypt parameters"
      return 1
    fi
  fi
  
  # 创建包含加密参数的队列数据
  local final_queue_data
  if [ -n "$encrypted_params" ]; then
    final_queue_data=$(echo "$queue_data" | jq --arg encrypted "$encrypted_params" '. + {"encrypted_params": $encrypted}')
  else
    final_queue_data="$queue_data"
  fi
  
  echo "$final_queue_data"
}

# 通用函数：更新队列issue（支持加密参数）
update_queue_issue_with_encryption() {
  local queue_issue_number="$1"
  local queue_data="$2"
  local sensitive_params="$3"
  local body_template="$4"
  
  # 创建包含加密参数的队列数据
  local encrypted_queue_data=$(create_encrypted_queue_data "$queue_data" "$sensitive_params")
  if [ $? -ne 0 ]; then
    echo "❌ Failed to create encrypted queue data"
    return 1
  fi
  
  # 使用模板创建issue body
  local body=$(echo "$body_template" | sed "s|__QUEUE_DATA__|$encrypted_queue_data|g")
  
  # 更新issue
  if update_queue_issue "$queue_issue_number" "$body"; then
    echo "✅ Queue update with encryption successful"
    return 0
  else
    echo "❌ Queue update with encryption failed"
    return 1
  fi
}