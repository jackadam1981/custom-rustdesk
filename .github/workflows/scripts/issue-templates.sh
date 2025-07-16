#!/bin/bash
# Issue 模板和评论生成函数
# 这个文件包含所有 markdown 模板生成函数

# 生成队列管理 issue 正文（支持混合锁）
generate_queue_management_body() {
    local current_time="$1"
    local queue_data="$2"
    local lock_status="$3"
    local current_build="$4"
    local lock_holder="$5"
    local version="$6"
    local optimistic_lock_status="${7:-空闲 🔓}"  # 乐观锁状态
    local pessimistic_lock_status="${8:-空闲 🔓}" # 悲观锁状态
    cat <<EOF
# 构建队列管理

**最后更新时间：** $current_time

## 当前状态
- **构建锁状态：** $lock_status
- **当前构建：** $current_build
- **锁持有者：** $lock_holder
- **版本：** $version

## 混合锁状态
- **乐观锁（排队）：** $optimistic_lock_status
- **悲观锁（构建）：** $pessimistic_lock_status

## 构建队列
- **当前数量：** $(echo "$queue_data" | jq '.queue | length // 0')/5
- **Issue触发：** $(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "issue")) | length // 0')/3
- **手动触发：** $(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0')/5

---

## 队列数据
\`\`\`json
$(echo "$queue_data" | jq -c .)
\`\`\`
EOF
}

# 生成构建被拒绝评论
generate_reject_comment() {
    local reason="$1"
    local queue_length="$2"
    local queue_limit="$3"
    local queue_info="$4"
    local current_time="$5"
    
    cat <<EOF
## 构建被拒绝
**拒绝原因：** $reason

**当前队列：**
$queue_info

**建议：** 请稍后重试或联系管理员
**时间：** $current_time
EOF
}

# 生成构建已加入队列评论
generate_success_comment() {
    local queue_position="$1"
    local queue_limit="$2"
    local build_id="$3"
    local tag="$4"
    local customer="$5"
    local slogan="$6"
    local join_time="$7"
    
    cat <<EOF
## 构建已加入队列
**队列位置：** $queue_position/$queue_limit
**构建ID：** $build_id
**标签：** $tag
**客户：** $customer
**标语：** $slogan
**加入时间：** $join_time

**状态：** 等待构建
**预计等待时间：** $((queue_position * 30)) 分钟
EOF
}

# 生成队列清理原因文本
generate_cleanup_reasons() {
    local reasons=("$@")
    local reason_text=""
    
    for reason in "${reasons[@]}"; do
        reason_text="${reason_text}- $reason
"
    done
    
    echo "$reason_text"
}

# 生成构建完成评论
generate_build_complete_comment() {
    local build_id="$1"
    local tag="$2"
    local customer="$3"
    local build_time="$4"
    local download_url="$5"
    
    cat <<EOF
## 构建完成

**构建ID：** $build_id
**标签：** $tag
**客户：** $customer
**完成时间：** $build_time

**下载链接：** $download_url

**状态：** 构建成功 🎉
EOF
}

# 生成构建失败评论
generate_build_failed_comment() {
    local build_id="$1"
    local tag="$2"
    local customer="$3"
    local error_message="$4"
    local build_time="$5"
    
    cat <<EOF
## 构建失败

**构建ID：** $build_id
**标签：** $tag
**客户：** $customer
**失败时间：** $build_time

**错误信息：**
\`\`\`
$error_message
\`\`\`

**状态：** 构建失败 💥
**建议：** 请检查构建参数或联系管理员
EOF
}

# 生成队列重置通知
generate_queue_reset_notification() {
    local reason="$1"
    local reset_time="$2"
    
    cat <<EOF
## 🔄 队列已重置
**重置原因：** $reason
**重置时间：** $reset_time

**说明：** 队列已重置为默认状态，所有等待中的构建需要重新加入队列
EOF
}

# 生成锁超时通知
generate_lock_timeout_notification() {
    local lock_holder="$1"
    local lock_duration="$2"
    local timeout_time="$3"
    
    cat <<EOF
## 构建锁超时
**锁持有者：** $lock_holder
**占用时长：** $lock_duration 小时
**超时时间：** $timeout_time

**说明：** 构建锁已超时，系统将自动释放锁并继续处理队列
EOF
}

# 生成队列状态更新通知
generate_queue_status_update() {
    local action="$1"
    local build_id="$2"
    local queue_position="$3"
    local update_time="$4"
    
    cat <<EOF
## 📊 队列状态更新
**操作：** $action
**构建ID：** $build_id
**队列位置：** $queue_position
**更新时间：** $update_time

**状态：** 队列状态已更新
EOF
}

# 生成队列清理记录
generate_queue_cleanup_record() {
    local current_time="$1"
    local current_version="$2"
    local cleaned_total_count="$3"
    local cleaned_issue_count="$4"
    local cleaned_workflow_count="$5"
    local cleanup_reason_text="$6"
    local cleaned_queue_data="$7"
    
    cat <<EOF
## 构建队列管理

**最后更新时间：** $current_time

### 当前状态
- **构建锁状态：** 空闲 🔓 (已清空)
- **当前构建：** 无
- **锁持有者：** 无
- **版本：** $current_version

### 构建队列
- **当前数量：** $cleaned_total_count/5
- **Issue触发：** $cleaned_issue_count/3
- **手动触发：** $cleaned_workflow_count/5

---

### 清理记录
**清理时间：** $current_time
**清理原因：**
$cleanup_reason_text
### 队列数据
\`\`\`json
$cleaned_queue_data
\`\`\`
EOF
}

# 生成队列重置记录
generate_queue_reset_record() {
    local now="$1"
    local reason="$2"
    local reset_queue_data="$3"
    
    cat <<EOF
## 构建队列管理

**最后更新时间：** $now

### 当前状态
- **构建锁状态：** 空闲 🔓
- **当前构建：** 无
- **锁持有者：** 无
- **版本：** 1

### 混合锁状态
- **乐观锁（排队）：** 空闲 🔓
- **悲观锁（构建）：** 空闲 🔓

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
\`\`\`
EOF
}

# 生成混合锁状态更新模板
generate_hybrid_lock_status_body() {
    local current_time="$1"
    local queue_data="$2"
    local version="$3"
    local optimistic_lock_status="$4"
    local pessimistic_lock_status="$5"
    local current_build="${6:-无}"
    local lock_holder="${7:-无}"
    
    cat <<EOF
## 构建队列管理

**最后更新时间：** $current_time

### 当前状态
- **构建锁状态：** $(if [ "$pessimistic_lock_status" = "占用 🔒" ]; then echo "占用 🔒"; else echo "空闲 🔓"; fi)
- **当前构建：** $current_build
- **锁持有者：** $lock_holder
- **版本：** $version

### 混合锁状态
- **乐观锁（排队）：** $optimistic_lock_status
- **悲观锁（构建）：** $pessimistic_lock_status

### 构建队列
- **当前数量：** $(echo "$queue_data" | jq '.queue | length // 0')/5
- **Issue触发：** $(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "issue")) | length // 0')/3
- **手动触发：** $(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0')/5

---

### 队列数据
\`\`\`json
$queue_data
\`\`\`
EOF
}

# 生成乐观锁状态通知
generate_optimistic_lock_notification() {
    local action="$1"
    local build_id="$2"
    local queue_position="$3"
    local current_time="$4"
    local retry_count="${5:-0}"
    
    cat <<EOF
## 🔄 乐观锁操作通知

**操作类型：** $action
**构建ID：** $build_id
**队列位置：** $queue_position
**操作时间：** $current_time
**重试次数：** $retry_count

**状态：** 乐观锁操作完成
**说明：** 使用快速重试机制，减少等待时间
EOF
}

# 生成悲观锁状态通知
generate_pessimistic_lock_notification() {
    local action="$1"
    local build_id="$2"
    local wait_duration="$3"
    local current_time="$4"
    local lock_status="$5"
    
    cat <<EOF
## 🔒 悲观锁操作通知

**操作类型：** $action
**构建ID：** $build_id
**等待时长：** $wait_duration
**操作时间：** $current_time
**锁状态：** $lock_status

**状态：** 悲观锁操作完成
**说明：** 使用独占锁机制确保构建安全
EOF
}

# 生成混合锁冲突解决通知
generate_hybrid_lock_conflict_resolution() {
    local conflict_type="$1"
    local build_id="$2"
    local resolution_action="$3"
    local current_time="$4"
    local details="$5"
    
    cat <<EOF
## 混合锁冲突解决
**冲突类型：** $conflict_type
**构建ID：** $build_id
**解决动作：** $resolution_action
**解决时间：** $current_time

**详细信息：**
$details

**状态：** 冲突已解决
**说明：** 混合锁策略自动处理并发冲突
EOF
}

# 生成锁超时清理通知
generate_lock_timeout_cleanup() {
    local lock_type="$1"
    local lock_holder="$2"
    local timeout_duration="$3"
    local cleanup_time="$4"
    local cleanup_reason="$5"
    
    cat <<EOF
## 锁超时清理
**锁类型：** $lock_type
**锁持有者：** $lock_holder
**超时时长：** $timeout_duration
**清理时间：** $cleanup_time
**清理原因：** $cleanup_reason

**状态：** 锁已自动释放
**说明：** 防止锁永久占用，确保系统正常运行
EOF
} 
