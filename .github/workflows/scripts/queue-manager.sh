#!/bin/bash
# 队列管理脚本 - 伪面向对象模式
# 这个文件包含所有队列操作功能，采用简单的伪面向对象设计
# 主要用于被 CustomBuildRustdesk.yml 工作流调用
# 整合了混合锁机制（乐观锁 + 悲观锁）

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/encryption-utils.sh
source .github/workflows/scripts/issue-templates.sh

# 通用函数：根据触发类型自动确定 issue_number 和 build_id
# 这个函数可以在所有需要区分触发类型的步骤中使用
queue_manager_determine_ids() {
  local event_data="$1"
  local trigger_data="$2"
  local github_run_id="$3"
  local github_event_name="$4"

  local issue_number=""
  local build_id=""

  if [ "$github_event_name" = "issues" ]; then
        # Issue触发：使用真实的issue编号
    issue_number=$(echo "$event_data" | jq -r '.issue.number // empty')
    if [ -z "$issue_number" ]; then
      debug "error" "无法从event_data中提取issue编号"
      return 1
    fi
        
        # 优先使用trigger_data中的build_id，没有则使用run_id
        build_id=$(echo "$trigger_data" | jq -r '.build_id // empty')
        if [ -z "$build_id" ]; then
            build_id="$github_run_id"
            debug "log" "使用GITHUB_RUN_ID作为build_id: $build_id"
        else
            debug "log" "使用trigger_data中的build_id: $build_id"
        fi
    else
        # 手动触发：使用虚拟issue编号和run_id作为build_id
    issue_number="manual_$github_run_id"
        build_id="$github_run_id"
        debug "log" "手动触发，使用虚拟issue编号: $issue_number, build_id: $build_id"
  fi

  # 输出结果（可以通过eval捕获）
  echo "ISSUE_NUMBER=$issue_number"
  echo "BUILD_ID=$build_id"

    debug "log" "触发类型: $github_event_name, Issue编号: $issue_number, Build ID: $build_id"
  return 0
}

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
_QUEUE_MANAGER_ISSUE_LOCK_TIMEOUT=30     # Issue 锁超时（30秒）
_QUEUE_MANAGER_QUEUE_LOCK_TIMEOUT=300    # 队列锁超时（5分钟）
_QUEUE_MANAGER_BUILD_LOCK_TIMEOUT=7200   # 构建锁超时（2小时）
_QUEUE_MANAGER_QUEUE_TIMEOUT_HOURS=6     # 队列项超时（6小时）

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

  # 在测试环境中，如果GITHUB_TOKEN是测试token，返回模拟数据
  if [ "$GITHUB_TOKEN" = "test_token" ] || [ "$GITHUB_REPOSITORY" = "test/repo" ]; then
    debug "log" "Using test environment, returning mock data"

    # 如果全局队列数据已经存在，使用它；否则使用默认数据
    if [ -n "$_QUEUE_MANAGER_QUEUE_DATA" ]; then
      local current_time=$(date '+%Y-%m-%d %H:%M:%S')
      local queue_length=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '.queue | length // 0')
      local version=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.version // 1')
      local run_id=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.run_id // "null"')

      # 生成模拟响应
      local lock_status="空闲 🔓"
      local current_build="无"
      local lock_holder="无"
      if [ "$run_id" != "null" ]; then
        lock_status="占用 🔒"
        current_build="$run_id"
        lock_holder="$run_id"
      fi

      # 使用printf避免控制字符问题
      local mock_body=$(printf '## 构建队列管理\n\n**最后更新时间：** %s\n\n### 当前状态\n- **构建锁状态：** %s\n- **当前构建：** %s\n- **锁持有者：** %s\n- **版本：** %s\n\n### 混合锁状态\n- **乐观锁（排队）：** 空闲 🔓\n- **悲观锁（构建）：** %s\n\n### 构建队列\n- **当前数量：** %s/5\n- **Issue触发：** 0/3\n- **手动触发：** %s/5\n\n```json\n%s\n```\n\n---' \
        "$current_time" "$lock_status" "$current_build" "$lock_holder" "$version" "$lock_status" "$queue_length" "$queue_length" "$_QUEUE_MANAGER_QUEUE_DATA")

      # 使用jq正确转义JSON
      local mock_response=$(jq -n --arg body "$mock_body" '{"body": $body}')
      echo "$mock_response"
    else
      echo '{"body": "## 构建队列管理\n\n**最后更新时间：** 2025-07-20 10:00:00\n\n### 当前状态\n- **构建锁状态：** 空闲 🔓\n- **当前构建：** 无\n- **锁持有者：** 无\n- **版本：** 1\n\n### 混合锁状态\n- **乐观锁（排队）：** 空闲 🔓\n- **悲观锁（构建）：** 空闲 🔓\n\n### 构建队列\n- **当前数量：** 0/5\n- **Issue触发：** 0/3\n- **手动触发：** 0/5\n\n```json\n{\"queue\":[],\"run_id\":null,\"version\":1}\n```\n\n---"}'
    fi
    return 0
  fi

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

  # 首先尝试从issue body中提取
  local body_content=$(echo "$issue_content" | jq -r '.body // empty')

  if [ -z "$body_content" ]; then
    debug "error" "No body content found in issue"
        echo '{"queue":[],"issue_locked_by":null,"queue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"queue_lock_version":1,"build_lock_version":1,"version":1}'
    return
  fi

  # 尝试多种提取方法
  local json_data=""

  # 方法1：提取 ```json ... ``` 代码块
  json_data=$(echo "$body_content" | sed -n '/```json/,/```/p' | sed '1d;$d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [ -n "$json_data" ]; then
    debug "log" "Found JSON in code block"
  else
    # 方法2：直接查找JSON对象
    debug "log" "No JSON code block found, trying to extract JSON object directly..."
    json_data=$(echo "$body_content" | grep -o '{[^}]*"version"[^}]*"queue"[^}]*}' | head -1)

    if [ -n "$json_data" ]; then
      debug "log" "Found JSON object with version and queue"
    else
      # 方法3：查找包含queue字段的JSON
      json_data=$(echo "$body_content" | grep -o '{[^}]*"queue"[^}]*}' | head -1)

      if [ -n "$json_data" ]; then
        debug "log" "Found JSON object with queue field"
      else
        # 方法4：查找任何看起来像JSON的对象
        json_data=$(echo "$body_content" | grep -o '{[^}]*}' | head -1)

        if [ -n "$json_data" ]; then
          debug "log" "Found potential JSON object"
        fi
      fi
    fi
  fi

  debug "log" "Extracted JSON data: $json_data"

  # 验证JSON格式并返回
  if [ -n "$json_data" ]; then
    debug "log" "JSON data is not empty, attempting to parse..."
        if echo "$json_data" | jq . > /dev/null 2>&1; then
      local result=$(echo "$json_data" | jq -c .)
      debug "log" "Valid JSON extracted: $result"
      echo "$result"
    else
      debug "error" "JSON parsing failed, using default"
            echo '{"queue":[],"issue_locked_by":null,"queue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"queue_lock_version":1,"build_lock_version":1,"version":1}'
    fi
  else
    debug "error" "JSON data is empty, using default"
        echo '{"queue":[],"issue_locked_by":null,"queue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"queue_lock_version":1,"build_lock_version":1,"version":1}'
  fi
}

# 私有方法：更新issue
queue_manager_update_issue() {
  local body="$1"

    # 在测试环境中，直接返回成功
  if [ "$GITHUB_TOKEN" = "test_token" ] || [ "$GITHUB_REPOSITORY" = "test/repo" ]; then
        debug "log" "Test environment: skipping issue update"
        return 0
    fi
    
    local response=$(curl -s -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$_QUEUE_MANAGER_ISSUE_NUMBER" \
        -d "{\"body\": \"$body\"}")
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        debug "success" "Issue updated successfully"
        return 0
    else
        debug "error" "Failed to update issue"
        return 1
    fi
}

# 私有方法：更新评论
queue_manager_update_comment() {
    local body="$1"
    local comment_id="${2:-}"
    
    # 在测试环境中，直接返回成功
    if [ "$GITHUB_TOKEN" = "test_token" ] || [ "$GITHUB_REPOSITORY" = "test/repo" ]; then
        debug "log" "Test environment: skipping comment update"
    return 0
  fi

    # 如果没有指定评论ID，尝试查找队列锁或构建锁评论
    if [ -z "$comment_id" ]; then
        if [ -n "${_QUEUE_MANAGER_QUEUE_COMMENT_ID:-}" ]; then
            comment_id="$_QUEUE_MANAGER_QUEUE_COMMENT_ID"
        elif [ -n "${_QUEUE_MANAGER_BUILD_COMMENT_ID:-}" ]; then
            comment_id="$_QUEUE_MANAGER_BUILD_COMMENT_ID"
        fi
    fi
    
    if [ -z "$comment_id" ]; then
        debug "error" "No comment ID available for update"
        return 1
    fi
    
  local response=$(curl -s -X PATCH \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$_QUEUE_MANAGER_ISSUE_NUMBER/comments/$comment_id" \
        -d "{\"body\": \"$body\"}")

  if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        debug "success" "Comment updated successfully"
    return 0
  else
        debug "error" "Failed to update comment"
    return 1
  fi
}

# ========== 三锁架构核心函数 ==========

# 私有方法：获取 Issue 锁（Issue 主体）
queue_manager_acquire_issue_lock() {
  local build_id="$1"
  local timeout="${2:-$_QUEUE_MANAGER_ISSUE_LOCK_TIMEOUT}"

  debug "log" "尝试获取 Issue 锁，构建ID: $build_id，超时时间: ${timeout}s"

  local start_time=$(date +%s)
  local attempt=0

  while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
    attempt=$((attempt + 1))

    # 刷新队列数据
    queue_manager_refresh

    # 获取当前 Issue 锁状态
    local issue_locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.issue_locked_by // null')
    local issue_lock_version=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.issue_lock_version // 1')

    if [ "$issue_locked_by" = "null" ] || [ "$issue_locked_by" = "$build_id" ]; then
      # 尝试获取 Issue 锁
      local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" --arg version "$issue_lock_version" '
        if (.issue_lock_version | tonumber) == ($version | tonumber) then
          .issue_locked_by = $build_id |
          .issue_lock_version = (.issue_lock_version | tonumber) + 1
        else
          .  # 版本不匹配，保持原数据
        end
      ')

      # 检查版本是否更新成功
      local new_issue_lock_version=$(echo "$updated_queue_data" | jq -r '.issue_lock_version // 1')
      local new_locked_by=$(echo "$updated_queue_data" | jq -r '.issue_locked_by // null')

      if [ "$new_issue_lock_version" -gt "$issue_lock_version" ] && [ "$new_locked_by" = "$build_id" ]; then
        # 版本更新成功，说明获取锁成功
        local update_response=$(queue_manager_update_issue_lock "$updated_queue_data" "$build_id")

        if [ $? -eq 0 ]; then
          debug "success" "成功获取 Issue 锁（版本: $issue_lock_version → $new_issue_lock_version，尝试次数: $attempt）"
          _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
          return 0
        fi
      else
        # 版本未更新，说明有其他构建抢先获取了锁
        debug "log" "版本检查失败，其他构建抢先获取了 Issue 锁（版本: $issue_lock_version，尝试次数: $attempt）"
      fi
    else
      debug "log" "Issue 锁被 $issue_locked_by 持有，等待释放...（尝试次数: $attempt）"
    fi

    # 指数退避延迟
    if [ "$attempt" -gt 1 ]; then
      local backoff_delay=$((_QUEUE_MANAGER_RETRY_DELAY * (2 ** (attempt - 1))))
      local max_backoff=5 # 最大延迟5秒
      if [ "$backoff_delay" -gt "$max_backoff" ]; then
        backoff_delay="$max_backoff"
      fi
      debug "log" "指数退避延迟${backoff_delay}秒"
      sleep "$backoff_delay"
    else
      sleep "$_QUEUE_MANAGER_RETRY_DELAY"
    fi
  done

  debug "error" "获取 Issue 锁超时（总尝试次数: $attempt）"
  return 1
}

# 私有方法：释放 Issue 锁
queue_manager_release_issue_lock() {
  local build_id="$1"

  debug "log" "释放 Issue 锁，构建ID: $build_id"

  # 刷新队列数据
  queue_manager_refresh

  # 检查是否持有 Issue 锁
  local issue_locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.issue_locked_by // null')

  if [ "$issue_locked_by" = "$build_id" ]; then
    # 释放 Issue 锁
    local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '
      .issue_locked_by = null |
      .issue_lock_version = (.issue_lock_version // 0) + 1
    ')

    local update_response=$(queue_manager_update_issue_lock "$updated_queue_data" "无")

    if [ $? -eq 0 ]; then
      debug "success" "成功释放 Issue 锁"
      _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
      return 0
    fi
  else
    debug "log" "未持有 Issue 锁，无需释放"
    return 0
  fi

  debug "error" "释放 Issue 锁失败"
  return 1
}

# 私有方法：更新 Issue 锁（Issue 主体）
queue_manager_update_issue_lock() {
  local queue_data="$1"
  local issue_locked_by="${2:-无}"

  # 获取当前时间
  local current_time=$(date '+%Y-%m-%d %H:%M:%S')

  # 提取版本号
  local issue_lock_version=$(echo "$queue_data" | jq -r '.issue_lock_version // 1')
  local queue_locked_by=$(echo "$queue_data" | jq -r '.queue_locked_by // "无"')
  local build_locked_by=$(echo "$queue_data" | jq -r '.build_locked_by // "无"')

  # 生成 Issue 锁状态模板
  local body=$(generate_issue_lock_body "$current_time" "$queue_data" "$issue_lock_version" "$issue_locked_by" "$queue_locked_by" "$build_locked_by")

  # 更新 Issue 主体
  queue_manager_update_issue "$body"
}

# 私有方法：获取队列锁（使用评论存储）
queue_manager_acquire_queue_lock() {
  local build_id="$1"
  local timeout="${2:-$_QUEUE_MANAGER_QUEUE_LOCK_TIMEOUT}"

  debug "log" "尝试获取队列锁，构建ID: $build_id，超时时间: ${timeout}s"

  local start_time=$(date +%s)
  local attempt=0

  while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
    attempt=$((attempt + 1))

    # 获取队列锁评论数据
    local queue_comment_content=$(queue_manager_get_queue_comment)
    if [ $? -ne 0 ]; then
      debug "log" "队列锁评论不存在，正在创建..."
      queue_manager_create_queue_comment
      sleep 2
      continue
    fi

    local queue_data=$(queue_manager_extract_json "$queue_comment_content")

    local queue_lock_version=$(echo "$queue_data" | jq -r '.queue_lock_version // 1')
    local queue_locked_by=$(echo "$queue_data" | jq -r '.queue_locked_by // null')

    if [ "$queue_locked_by" = "null" ] || [ "$queue_locked_by" = "$build_id" ]; then
      # 基于队列锁版本号尝试获取锁
      local updated_queue_data=$(echo "$queue_data" | jq --arg build_id "$build_id" --arg version "$queue_lock_version" '
        if (.queue_lock_version | tonumber) == ($version | tonumber) then
          .queue_locked_by = $build_id |
          .queue_lock_version = (.queue_lock_version | tonumber) + 1
        else
          .  # 版本不匹配，保持原数据
        end
      ')

      # 检查版本是否更新成功
      local new_queue_lock_version=$(echo "$updated_queue_data" | jq -r '.queue_lock_version // 1')
      local new_locked_by=$(echo "$updated_queue_data" | jq -r '.queue_locked_by // null')

      if [ "$new_queue_lock_version" -gt "$queue_lock_version" ] && [ "$new_locked_by" = "$build_id" ]; then
        # 版本更新成功，说明获取锁成功
        local update_response=$(queue_manager_update_queue_comment "$updated_queue_data" "$build_id")

        if [ $? -eq 0 ]; then
          debug "success" "成功获取队列锁（版本: $queue_lock_version → $new_queue_lock_version，尝试次数: $attempt）"
          return 0
        fi
      else
        # 版本未更新，说明有其他构建抢先获取了锁
        debug "log" "版本检查失败，其他构建抢先获取了队列锁（版本: $queue_lock_version，尝试次数: $attempt）"
      fi
    else
      debug "log" "队列锁被 $queue_locked_by 持有，等待释放...（尝试次数: $attempt）"
    fi

    # 指数退避延迟
    if [ "$attempt" -gt 1 ]; then
      local backoff_delay=$((_QUEUE_MANAGER_RETRY_DELAY * (2 ** (attempt - 1))))
      local max_backoff=10 # 最大延迟10秒
      if [ "$backoff_delay" -gt "$max_backoff" ]; then
        backoff_delay="$max_backoff"
      fi
      debug "log" "指数退避延迟${backoff_delay}秒"
      sleep "$backoff_delay"
    else
      sleep "$_QUEUE_MANAGER_RETRY_DELAY"
    fi
  done

  debug "error" "获取队列锁超时（总尝试次数: $attempt）"
  return 1
}

# 私有方法：释放队列锁
queue_manager_release_queue_lock() {
  local build_id="$1"

  debug "log" "释放队列锁，构建ID: $build_id"

  # 获取队列锁评论数据
  local queue_comment_content=$(queue_manager_get_queue_comment)
  if [ $? -ne 0 ]; then
    debug "log" "队列锁评论不存在，无需释放"
    return 0
  fi

  local queue_data=$(queue_manager_extract_json "$queue_comment_content")
  local queue_locked_by=$(echo "$queue_data" | jq -r '.queue_locked_by // null')

  if [ "$queue_locked_by" = "$build_id" ]; then
    # 释放队列锁
    local updated_queue_data=$(echo "$queue_data" | jq '
      .queue_locked_by = null |
      .queue_lock_version = (.queue_lock_version // 0) + 1
    ')

    local update_response=$(queue_manager_update_queue_comment "$updated_queue_data" "无")

    if [ $? -eq 0 ]; then
      debug "success" "成功释放队列锁"
      return 0
    fi
  else
    debug "log" "未持有队列锁，无需释放"
    return 0
  fi

  debug "error" "释放队列锁失败"
  return 1
}

# 私有方法：更新队列锁评论
queue_manager_update_queue_comment() {
  local queue_data="$1"
  local queue_locked_by="${2:-无}"

  # 获取当前时间
  local current_time=$(date '+%Y-%m-%d %H:%M:%S')

  # 提取版本号
  local queue_lock_version=$(echo "$queue_data" | jq -r '.queue_lock_version // 1')

  # 生成队列锁状态模板
  local body=$(generate_queue_lock_body "$current_time" "$queue_data" "$queue_lock_version" "$queue_locked_by")

  # 更新队列锁评论
  queue_manager_update_comment "$body" "$_QUEUE_MANAGER_QUEUE_COMMENT_ID"
}

# 私有方法：获取队列锁评论
queue_manager_get_queue_comment() {
  local comment_id="${_QUEUE_MANAGER_QUEUE_COMMENT_ID:-}"

  if [ -z "$comment_id" ]; then
    debug "log" "队列锁评论ID未设置，尝试查找..."
    queue_manager_find_queue_comment
    comment_id="${_QUEUE_MANAGER_QUEUE_COMMENT_ID:-}"
  fi

  if [ -n "$comment_id" ]; then
    local response=$(curl -s \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$_QUEUE_MANAGER_ISSUE_NUMBER/comments/$comment_id")

    if echo "$response" | jq -e '.body' >/dev/null 2>&1; then
      echo "$response"
      return 0
    fi
  fi

  return 1
}

# 私有方法：查找队列锁评论
queue_manager_find_queue_comment() {
  local response=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$_QUEUE_MANAGER_ISSUE_NUMBER/comments")

  if echo "$response" | jq -e '.[]' >/dev/null 2>&1; then
    local comment_id=$(echo "$response" | jq -r '.[] | select(.body | contains("队列锁")) | .id // empty' | head -1)
    if [ -n "$comment_id" ]; then
      _QUEUE_MANAGER_QUEUE_COMMENT_ID="$comment_id"
      debug "log" "找到队列锁评论ID: $comment_id"
      return 0
    fi
  fi

  return 1
}

# 私有方法：创建队列锁评论
queue_manager_create_queue_comment() {
  local current_time=$(date '+%Y-%m-%d %H:%M:%S')
  local default_queue_data='{"queue":[],"queue_locked_by":null,"queue_lock_version":1}'

  local body="# 队列锁管理

**最后更新时间：** $current_time

### 队列锁状态
- **队列锁状态：** 空闲 🔓
- **队列锁持有者：** 无
- **版本：** 1

---

### 队列锁数据
\`\`\`json
$default_queue_data
\`\`\`"

  local response=$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$_QUEUE_MANAGER_ISSUE_NUMBER/comments" \
    -d "{\"body\": \"$body\"}")

  if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
    local comment_id=$(echo "$response" | jq -r '.id')
    _QUEUE_MANAGER_QUEUE_COMMENT_ID="$comment_id"
    debug "success" "创建队列锁评论成功，ID: $comment_id"
    return 0
  else
    debug "error" "创建队列锁评论失败"
    return 1
  fi
}

# 私有方法：获取构建锁（使用评论存储）
queue_manager_acquire_build_lock() {
  local build_id="$1"
  local timeout="${2:-$_QUEUE_MANAGER_BUILD_LOCK_TIMEOUT}"

  debug "log" "尝试获取构建锁，构建ID: $build_id，超时时间: ${timeout}s"

  local start_time=$(date +%s)
  local attempt=0

  while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
    attempt=$((attempt + 1))

    # 获取构建锁评论数据
    local build_comment_content=$(queue_manager_get_build_comment)
    if [ $? -ne 0 ]; then
      debug "log" "构建锁评论不存在，正在创建..."
      queue_manager_create_build_comment
      sleep 2
      continue
    fi

    local build_data=$(queue_manager_extract_json "$build_comment_content")

    local build_lock_version=$(echo "$build_data" | jq -r '.build_lock_version // 1')
    local build_locked_by=$(echo "$build_data" | jq -r '.build_locked_by // null')

    if [ "$build_locked_by" = "null" ] || [ "$build_locked_by" = "$build_id" ]; then
      # 基于构建锁版本号尝试获取锁
      local updated_build_data=$(echo "$build_data" | jq --arg build_id "$build_id" --arg version "$build_lock_version" '
        if (.build_lock_version | tonumber) == ($version | tonumber) then
          .build_locked_by = $build_id |
          .build_lock_version = (.build_lock_version | tonumber) + 1
        else
          .  # 版本不匹配，保持原数据
        end
      ')

      # 检查版本是否更新成功
      local new_build_lock_version=$(echo "$updated_build_data" | jq -r '.build_lock_version // 1')
      local new_locked_by=$(echo "$updated_build_data" | jq -r '.build_locked_by // null')

      if [ "$new_build_lock_version" -gt "$build_lock_version" ] && [ "$new_locked_by" = "$build_id" ]; then
        # 版本更新成功，说明获取锁成功
        local update_response=$(queue_manager_update_build_comment "$updated_build_data" "$build_id")

        if [ $? -eq 0 ]; then
          debug "success" "成功获取构建锁（版本: $build_lock_version → $new_build_lock_version，尝试次数: $attempt）"
          return 0
        fi
      else
        # 版本未更新，说明有其他构建抢先获取了锁
        debug "log" "版本检查失败，其他构建抢先获取了构建锁（版本: $build_lock_version，尝试次数: $attempt）"
      fi
    else
      debug "log" "构建锁被 $build_locked_by 持有，等待释放...（尝试次数: $attempt）"
    fi

    # 指数退避延迟
    if [ "$attempt" -gt 1 ]; then
      local backoff_delay=$((_QUEUE_MANAGER_RETRY_DELAY * (2 ** (attempt - 1))))
      local max_backoff=10 # 最大延迟10秒
      if [ "$backoff_delay" -gt "$max_backoff" ]; then
        backoff_delay="$max_backoff"
      fi
      debug "log" "指数退避延迟${backoff_delay}秒"
      sleep "$backoff_delay"
    else
      sleep "$_QUEUE_MANAGER_RETRY_DELAY"
    fi
  done

  debug "error" "获取构建锁超时（总尝试次数: $attempt）"
  return 1
}

# 私有方法：释放构建锁
queue_manager_release_build_lock() {
  local build_id="$1"

  debug "log" "释放构建锁，构建ID: $build_id"

  # 获取构建锁评论数据
  local build_comment_content=$(queue_manager_get_build_comment)
  if [ $? -ne 0 ]; then
    debug "log" "构建锁评论不存在，无需释放"
    return 0
  fi

  local build_data=$(queue_manager_extract_json "$build_comment_content")
  local build_locked_by=$(echo "$build_data" | jq -r '.build_locked_by // null')

  if [ "$build_locked_by" = "$build_id" ]; then
    # 释放构建锁
    local updated_build_data=$(echo "$build_data" | jq '
      .build_locked_by = null |
      .build_lock_version = (.build_lock_version // 0) + 1
    ')

    local update_response=$(queue_manager_update_build_comment "$updated_build_data" "无")

    if [ $? -eq 0 ]; then
      debug "success" "成功释放构建锁"
      return 0
    fi
  else
    debug "log" "未持有构建锁，无需释放"
    return 0
  fi

  debug "error" "释放构建锁失败"
  return 1
}

# 私有方法：更新构建锁评论
queue_manager_update_build_comment() {
  local build_data="$1"
  local build_locked_by="${2:-无}"

  # 获取当前时间
  local current_time=$(date '+%Y-%m-%d %H:%M:%S')

  # 提取版本号
  local build_lock_version=$(echo "$build_data" | jq -r '.build_lock_version // 1')

  # 生成构建锁状态模板
  local body=$(generate_build_lock_body "$current_time" "$build_data" "$build_lock_version" "$build_locked_by")

  # 更新构建锁评论
  queue_manager_update_comment "$body" "$_QUEUE_MANAGER_BUILD_COMMENT_ID"
}

# 私有方法：获取构建锁评论
queue_manager_get_build_comment() {
  local comment_id="${_QUEUE_MANAGER_BUILD_COMMENT_ID:-}"

  if [ -z "$comment_id" ]; then
    debug "log" "构建锁评论ID未设置，尝试查找..."
    queue_manager_find_build_comment
    comment_id="${_QUEUE_MANAGER_BUILD_COMMENT_ID:-}"
  fi

  if [ -n "$comment_id" ]; then
    local response=$(curl -s \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$_QUEUE_MANAGER_ISSUE_NUMBER/comments/$comment_id")

    if echo "$response" | jq -e '.body' >/dev/null 2>&1; then
      echo "$response"
      return 0
    fi
  fi

  return 1
}

# 私有方法：查找构建锁评论
queue_manager_find_build_comment() {
  local response=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$_QUEUE_MANAGER_ISSUE_NUMBER/comments")

  if echo "$response" | jq -e '.[]' >/dev/null 2>&1; then
    local comment_id=$(echo "$response" | jq -r '.[] | select(.body | contains("构建锁")) | .id // empty' | head -1)
    if [ -n "$comment_id" ]; then
      _QUEUE_MANAGER_BUILD_COMMENT_ID="$comment_id"
      debug "log" "找到构建锁评论ID: $comment_id"
      return 0
    fi
  fi

  return 1
}

# 私有方法：创建构建锁评论
queue_manager_create_build_comment() {
  local current_time=$(date '+%Y-%m-%d %H:%M:%S')
  local default_build_data='{"queue":[],"build_locked_by":null,"build_lock_version":1}'

  local body="# 构建锁管理

**最后更新时间：** $current_time

### 构建锁状态
- **构建锁状态：** 空闲 🔓
- **构建锁持有者：** 无
- **版本：** 1

---

### 构建锁数据
\`\`\`json
$default_build_data
\`\`\`"

  local response=$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$_QUEUE_MANAGER_ISSUE_NUMBER/comments" \
    -d "{\"body\": \"$body\"}")

  if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
    local comment_id=$(echo "$response" | jq -r '.id')
    _QUEUE_MANAGER_BUILD_COMMENT_ID="$comment_id"
    debug "success" "创建构建锁评论成功，ID: $comment_id"
    return 0
  else
    debug "error" "创建构建锁评论失败"
    return 1
  fi
}

# 公共方法：获取队列状态
queue_manager_get_status() {
  local queue_length=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '.queue | length // 0')
    local issue_locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.issue_locked_by // "null"')
    local queue_locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.queue_locked_by // "null"')
    local build_locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.build_locked_by // "null"')
  local version=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.version // 1')

  echo "队列统计:"
  echo "  总数量: $queue_length"
  echo "  版本: $version"
    echo "  锁状态:"
    echo "    Issue 锁: $issue_locked_by"
    echo "    队列锁: $queue_locked_by"
    echo "    构建锁: $build_locked_by"
}

# 公共方法：悲观锁加入队列
queue_manager_join() {
  local issue_number="$1"
  local trigger_data="$2"
  local queue_limit="${3:-5}"

    echo "=== 悲观锁加入队列 ==="
    debug "log" "Starting pessimistic lock queue join process..."

    # 从trigger_data中提取build_id（现在由workflow中的通用函数处理）
    local build_id=$(echo "$trigger_data" | jq -r '.build_id // empty')
  if [ -z "$build_id" ]; then
        build_id="${GITHUB_RUN_ID:-}"
        if [ -z "$build_id" ]; then
            debug "error" "No build_id found in trigger_data and no GITHUB_RUN_ID available"
    return 1
  fi
  debug "log" "Using GITHUB_RUN_ID as build_id: $build_id"
    else
        debug "log" "Using build_id from trigger_data: $build_id"
    fi

  # 初始化队列管理器
  queue_manager_init "$issue_number"

  # 执行统一的清理操作
  queue_manager_cleanup

    # 获取 Issue 锁
    if ! queue_manager_acquire_issue_lock "$build_id"; then
        debug "error" "Failed to acquire issue lock"
        return 1
    fi
    
    # 获取队列锁
    if ! queue_manager_acquire_queue_lock "$build_id"; then
        debug "error" "Failed to acquire queue lock"
        queue_manager_release_issue_lock "$build_id"
        return 1
    fi
    
    # 在队列锁保护下执行队列操作
    debug "log" "Issue lock and queue lock acquired, performing queue operations..."

    # 刷新队列数据
    queue_manager_refresh

    # 验证队列数据结构
    local queue_data_valid=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -e '.queue != null and .version != null' >/dev/null 2>&1 && echo "true" || echo "false")
    if [ "$queue_data_valid" != "true" ]; then
        debug "error" "Invalid queue data structure"
        queue_manager_release_queue_lock "$build_id"
        queue_manager_release_issue_lock "$build_id"
        return 1
    fi

    # 检查队列长度
    local current_queue_length=$(queue_manager_get_length)

    # 如果队列为空，重置队列状态到版本1
    if [ "$current_queue_length" -eq 0 ]; then
      debug "log" "Queue is empty, resetting queue state to version 1"
      queue_manager_reset "队列为空时自动重置"
      current_queue_length=0
    fi

    if [ "$current_queue_length" -ge "$queue_limit" ]; then
      debug "error" "Queue is full ($current_queue_length/$queue_limit)"
        queue_manager_release_queue_lock "$build_id"
        queue_manager_release_issue_lock "$build_id"
      return 1
    fi

    # 检查是否已在队列中
    local already_in_queue=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" '.queue | map(select(.build_id == $build_id)) | length')
    if [ "$already_in_queue" -gt 0 ]; then
      debug "log" "Already in queue"
        queue_manager_release_queue_lock "$build_id"
        queue_manager_release_issue_lock "$build_id"
      return 0
    fi

    # 解析触发数据
    debug "log" "Parsing trigger data: $trigger_data"
    local parsed_trigger_data=$(echo "$trigger_data" | jq -c . 2>/dev/null || echo "{}")
    debug "log" "Parsed trigger data: $parsed_trigger_data"

    # 提取构建信息
    debug "log" "Extracting build information..."
    local tag=$(echo "$parsed_trigger_data" | jq -r '.tag // empty')
    local email=$(echo "$parsed_trigger_data" | jq -r '.email // empty')
    local customer=$(echo "$parsed_trigger_data" | jq -r '.customer // empty')
    local customer_link=$(echo "$parsed_trigger_data" | jq -r '.customer_link // empty')
    local super_password=$(echo "$parsed_trigger_data" | jq -r '.super_password // empty')
    local slogan=$(echo "$parsed_trigger_data" | jq -r '.slogan // empty')
    local rendezvous_server=$(echo "$parsed_trigger_data" | jq -r '.rendezvous_server // empty')
    local rs_pub_key=$(echo "$parsed_trigger_data" | jq -r '.rs_pub_key // empty')
    local api_server=$(echo "$parsed_trigger_data" | jq -r '.api_server // empty')
    local trigger_type=$(echo "$parsed_trigger_data" | jq -r '.trigger_type // empty')

    debug "log" "Extracted build info - tag: '$tag', email: '$email', customer: '$customer', slogan: '$slogan', trigger_type: '$trigger_type'"
    debug "log" "Extracted privacy info - rendezvous_server: '$rendezvous_server', api_server: '$api_server'"

    # 创建新队列项
    debug "log" "Creating new queue item..."
    local new_queue_item=$(jq -c -n \
      --arg build_id "$build_id" \
      --arg build_title "Custom Rustdesk Build" \
      --arg tag "$tag" \
      --arg email "$email" \
      --arg customer "$customer" \
      --arg customer_link "$customer_link" \
      --arg super_password "$super_password" \
      --arg slogan "$slogan" \
      --arg rendezvous_server "$rendezvous_server" \
      --arg rs_pub_key "$rs_pub_key" \
      --arg api_server "$api_server" \
      --arg trigger_type "$trigger_type" \
      --arg join_time "$_QUEUE_MANAGER_CURRENT_TIME" \
      '{build_id: $build_id, build_title: $build_title, tag: $tag, email: $email, customer: $customer, customer_link: $customer_link, super_password: $super_password, slogan: $slogan, rendezvous_server: $rendezvous_server, rs_pub_key: $rs_pub_key, api_server: $api_server, trigger_type: $trigger_type, join_time: $join_time}')

    debug "log" "New queue item created: $new_queue_item"

    # 添加新项到队列
    debug "log" "Current queue data: $_QUEUE_MANAGER_QUEUE_DATA"
    local new_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --argjson new_item "$new_queue_item" '
            .queue += [$new_item] |
            .version = (.version // 0) + 1
        ')

    debug "log" "Updated queue data: $new_queue_data"

    # 更新队列（在队列锁保护下）
    local update_response=$(queue_manager_update_queue_comment "$new_queue_data" "$build_id")

    if [ $? -eq 0 ]; then
      debug "success" "Successfully joined queue at position $((current_queue_length + 1))"
      _QUEUE_MANAGER_QUEUE_DATA="$new_queue_data"

        # 释放队列锁和 Issue 锁
        queue_manager_release_queue_lock "$build_id"
        queue_manager_release_issue_lock "$build_id"
      return 0
    else
        debug "error" "Failed to update queue"
        queue_manager_release_queue_lock "$build_id"
        queue_manager_release_issue_lock "$build_id"
  return 1
    fi
}

# 公共方法：悲观锁获取构建权限
queue_manager_acquire_lock() {
  local build_id="$1"
  local queue_limit="${2:-5}"

  echo "=== 悲观锁获取构建权限 ==="
  debug "log" "Starting pessimistic lock acquisition..."

  local start_time=$(date +%s)

  while [ $(($(date +%s) - start_time)) -lt $_QUEUE_MANAGER_MAX_WAIT_TIME ]; do
    # 刷新队列数据
    queue_manager_refresh

    # 执行统一的清理操作
    queue_manager_cleanup

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
            # 获取 Issue 锁
            if ! queue_manager_acquire_issue_lock "$build_id"; then
                debug "error" "Failed to acquire issue lock for build"
                sleep "$_QUEUE_MANAGER_CHECK_INTERVAL"
                continue
            fi
            
            # 获取构建锁
            if queue_manager_acquire_build_lock "$build_id"; then
                debug "success" "Successfully acquired build lock"
                
                # 更新队列数据，设置当前构建
      local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" '
                .run_id = $build_id |
                .version = (.version // 0) + 1
            ')

                # 更新队列锁评论
                local update_response=$(queue_manager_update_queue_comment "$updated_queue_data" "无")

      if [ $? -eq 0 ]; then
                    debug "success" "Successfully updated queue with build lock"
        _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"

                    # 释放 Issue 锁（构建锁已获取，可以释放 Issue 锁）
                    queue_manager_release_issue_lock "$build_id"
        return 0
                else
                    debug "error" "Failed to update queue with build lock"
                    queue_manager_release_build_lock "$build_id"
                    queue_manager_release_issue_lock "$build_id"
                fi
            else
                debug "error" "Failed to acquire build lock"
                queue_manager_release_issue_lock "$build_id"
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
    
    # 获取 Issue 锁
    if ! queue_manager_acquire_issue_lock "$build_id"; then
        debug "error" "Failed to acquire issue lock for release"
        return 1
    fi

  # 刷新队列数据
  queue_manager_refresh

  # 从队列中移除当前构建
  local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" '
        .queue = (.queue | map(select(.build_id != $build_id))) |
        .run_id = null |
        .version = (.version // 0) + 1
    ')

    # 更新队列锁评论
    local update_response=$(queue_manager_update_queue_comment "$updated_queue_data" "无")

  if [ $? -eq 0 ]; then
        debug "success" "Successfully updated queue after build completion"
    _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
        
        # 释放构建锁
        queue_manager_release_build_lock "$build_id"
        
        # 释放 Issue 锁
        queue_manager_release_issue_lock "$build_id"
        
        debug "success" "Successfully released build lock"
    return 0
  else
        debug "error" "Failed to update queue after build completion"
        queue_manager_release_issue_lock "$build_id"
    return 1
  fi
}

# 公共方法：统一的清理操作
queue_manager_cleanup() {
  debug "log" "Performing unified cleanup operations..."

  # 1. 自动清理过期队列项（超过6小时的）
  debug "log" "Step 1: Cleaning expired queue items (older than $_QUEUE_MANAGER_QUEUE_TIMEOUT_HOURS hours)"

  # 获取当前时间戳
  local current_time=$(date +%s)

  # 计算超时秒数
  local queue_timeout_seconds=$((_QUEUE_MANAGER_QUEUE_TIMEOUT_HOURS * 3600))

    # 移除超过队列超时时间的队列项
    local cleaned_queue=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg current_time "$current_time" --arg timeout_seconds "$queue_timeout_seconds" '
            .queue = (.queue | map(select(
                # 将日期字符串转换为时间戳进行比较
                (($current_time | tonumber) - (try (.join_time | strptime("%Y-%m-%d %H:%M:%S") | mktime) catch 0)) < ($timeout_seconds | tonumber)
            )))
        ')

    local update_response=$(queue_manager_update_queue_comment "$cleaned_queue" "无")
    if [ $? -eq 0 ]; then
      debug "success" "Auto-clean completed"
      _QUEUE_MANAGER_QUEUE_DATA="$cleaned_queue"
    else
      debug "error" "Auto-clean failed"
  fi

  # 2. 清理已完成的工作流
  debug "log" "Step 2: Cleaning completed workflows"
    local build_ids=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.queue[]?.build_id // empty')
    local builds_to_remove=()

    if [ -n "$build_ids" ]; then
        for build_id in $build_ids; do
      debug "log" "Checking build $build_id..."

            # 获取工作流运行状态
      local run_status="unknown"
      if [ -n "$GITHUB_TOKEN" ] && [ "$GITHUB_TOKEN" != "test_token" ] && [ "$GITHUB_REPOSITORY" != "test/repo" ]; then
                local run_response=$(curl -s \
          -H "Authorization: token $GITHUB_TOKEN" \
          -H "Accept: application/vnd.github.v3+json" \
          "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$build_id")

                # 检查HTTP状态码
                local http_status=$(echo "$run_response" | jq -r '.status // empty')

                if [[ "$http_status" =~ ^[0-9]+$ ]] && [ "$http_status" -ge 400 ]; then
          run_status="not_found"
                elif echo "$run_response" | jq -e '.message' | grep -q "Not Found"; then
          run_status="not_found"
        else
                    run_status=$(echo "$run_response" | jq -r '.status // "unknown"')
        fi
      else
        debug "log" "Test environment: assuming build is running"
        run_status="in_progress"
      fi

      # 检查是否需要清理
      case "$run_status" in
                "completed"|"cancelled"|"failure"|"skipped"|"not_found")
        debug "log" "Build $build_id needs cleanup (status: $run_status)"
        builds_to_remove+=("$build_id")
        ;;
                "queued"|"in_progress"|"waiting")
        debug "log" "Build $build_id is still running (status: $run_status), no cleanup needed"
        ;;
      "unknown")
                    debug "log" "Build $build_id has unknown status: $run_status, not cleaning to avoid removing waiting builds"
        ;;
      *)
        debug "log" "Build $build_id has unexpected status: $run_status, not cleaning to avoid removing waiting builds"
        ;;
      esac
    done

    # 执行清理操作
    if [ ${#builds_to_remove[@]} -gt 0 ]; then
      debug "log" "Removing ${#builds_to_remove[@]} completed builds: ${builds_to_remove[*]}"

      # 从队列中移除这些构建
      local cleaned_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --argjson builds_to_remove "$(printf '%s\n' "${builds_to_remove[@]}" | jq -R . | jq -s .)" '
                .queue = (.queue | map(select(.build_id as $id | $builds_to_remove | index($id) | not))) |
                .version = (.version // 0) + 1
            ')

      # 更新队列
            local update_response=$(queue_manager_update_queue_comment "$cleaned_queue_data" "无")

      if [ $? -eq 0 ]; then
        debug "success" "Successfully cleaned ${#builds_to_remove[@]} completed builds"
        _QUEUE_MANAGER_QUEUE_DATA="$cleaned_queue_data"
      else
        debug "error" "Failed to clean completed builds"
      fi
    else
      debug "log" "No builds need cleanup"
    fi
  else
    debug "log" "Queue is empty, nothing to clean"
  fi

  # 3. 检查并清理已完成的构建锁
  debug "log" "Step 3: Checking and cleaning completed build locks"
  local current_run_id=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.run_id // null')

  if [ "$current_run_id" != "null" ]; then
    debug "log" "Current build lock holder: $current_run_id"

    # 检查当前持有构建锁的构建状态
    local run_status="unknown"
    if [ -n "$GITHUB_TOKEN" ] && [ "$GITHUB_TOKEN" != "test_token" ] && [ "$GITHUB_REPOSITORY" != "test/repo" ]; then
            local run_response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$current_run_id")

      # 检查HTTP状态码
      local http_status=$(echo "$run_response" | jq -r '.status // empty')

      if [[ "$http_status" =~ ^[0-9]+$ ]] && [ "$http_status" -ge 400 ]; then
        run_status="not_found"
      elif echo "$run_response" | jq -e '.message' | grep -q "Not Found"; then
        run_status="not_found"
      else
        run_status=$(echo "$run_response" | jq -r '.status // "unknown"')
      fi
    else
      debug "log" "Test environment: assuming build is running"
      run_status="in_progress"
    fi

    debug "log" "Current build lock holder status: $run_status"

    # 只有当构建确实已完成时才进行清理
    case "$run_status" in
            "completed"|"cancelled"|"failure"|"skipped"|"not_found")
      debug "log" "Current build lock holder needs cleanup (status: $run_status), performing cleanup"

      # 内联的清理逻辑
      debug "log" "Current build lock holder needs cleanup (status: $run_status), releasing pessimistic build lock"
      debug "log" "Current queue data before lock release: $_QUEUE_MANAGER_QUEUE_DATA"

      # 释放悲观构建锁（保留乐观队列锁数据）
      local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '
                    .run_id = null |
                    .version = (.version // 0) + 1
                ')

      debug "log" "Updated queue data after pessimistic lock release: $updated_queue_data"

      # 更新时释放乐观锁和悲观锁
                local update_response=$(queue_manager_update_queue_comment "$updated_queue_data" "无")

      if [ $? -eq 0 ]; then
        debug "success" "Successfully released lock for completed build"
        _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
      else
        debug "error" "Failed to release lock for completed build"
      fi
      ;;
            "queued"|"in_progress"|"waiting")
      debug "log" "Current build lock holder is still running (status: $run_status), no cleanup needed"
      ;;
    "unknown")
      debug "log" "Current build lock holder has unknown status: $run_status, but not cleaning to avoid removing waiting builds"
      ;;
    *)
      debug "log" "Current build lock holder has unexpected status: $run_status, not cleaning to avoid removing waiting builds"
      ;;
    esac
  else
    debug "log" "No current build lock holder, no cleanup needed"
  fi

  # 4. 移除重复项（可选，仅在需要时执行）
  debug "log" "Step 4: Removing duplicate items (if any)"
  local current_queue_length=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '.queue | length // 0')
  local unique_queue_length=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '.queue | group_by(.build_id) | length // 0')

  if [ "$current_queue_length" -gt "$unique_queue_length" ]; then
    debug "log" "Found duplicate items, removing them"
    local deduplicated_queue=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '
            .queue = (.queue | group_by(.build_id) | map(.[0])) |
            .version = (.version // 0) + 1
        ')

        local update_response=$(queue_manager_update_queue_comment "$deduplicated_queue" "无")

    if [ $? -eq 0 ]; then
      debug "success" "Successfully removed duplicate items"
      _QUEUE_MANAGER_QUEUE_DATA="$deduplicated_queue"
    else
      debug "error" "Failed to remove duplicate items"
    fi
  else
    debug "log" "No duplicate items found"
  fi

  debug "log" "Unified cleanup completed"
}

# 公共方法：重置队列
queue_manager_reset() {
  local reason="${1:-手动重置}"
  echo "=== 重置队列 ==="
  debug "log" "Resetting queue to default state: $reason"

  local now=$(date '+%Y-%m-%d %H:%M:%S')
    local reset_queue_data='{"version": 1, "issue_locked_by": null, "queue_locked_by": null, "build_locked_by": null, "issue_lock_version": 1, "queue_lock_version": 1, "build_lock_version": 1, "queue": []}'

  # 在测试环境中，直接设置全局变量
  if [ "$GITHUB_TOKEN" = "test_token" ] || [ "$GITHUB_REPOSITORY" = "test/repo" ]; then
    debug "log" "Test environment: directly setting global queue data"
    _QUEUE_MANAGER_QUEUE_DATA="$reset_queue_data"
    debug "success" "Queue reset successful in test environment"
    return 0
  fi

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
    local trigger_data="$1"
    local queue_limit="${2:-5}"
    queue_manager_join "$issue_number" "$trigger_data" "$queue_limit"
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
  "cleanup")
    queue_manager_cleanup
    ;;
  "reset")
    local reason="${1:-手动重置}"
    queue_manager_reset "$reason"
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
