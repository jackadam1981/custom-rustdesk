#!/bin/bash
# Issue模板生成脚本
# 这个文件包含所有issue模板生成函数

# 生成队列管理模板
generate_queue_management_body() {
    local current_time="$1"
    local queue_data="$2"
    local lock_status="$3"
    local current_build="$4"
    local lock_holder="$5"
    local version="$6"
    
    # 计算队列统计信息
    local queue_length=$(echo "$queue_data" | jq '.queue | length // 0')
    local issue_count=$(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "issue")) | length // 0')
    local workflow_count=$(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0')
    
    cat <<EOF
## 构建队列管理

**最后更新时间：** $current_time

### 当前状态
- **构建锁状态：** $lock_status
- **当前构建：** $current_build
- **锁持有者：** $lock_holder
- **版本：** $version

### 构建队列
- **当前数量：** $queue_length/5
- **Issue触发：** $issue_count/3
- **手动触发：** $workflow_count/5

---

### 队列数据
\`\`\`json
$queue_data
\`\`\`
EOF
}

# 生成混合锁状态模板
generate_hybrid_lock_status_body() {
    local current_time="$1"
    local queue_data="$2"
    local version="$3"
    local optimistic_lock_status="$4"
    local pessimistic_lock_status="$5"
    local current_build="${6:-无}"
    local lock_holder="${7:-无}"
    
    # 计算队列统计信息
    local queue_length=$(echo "$queue_data" | jq '.queue | length // 0')
    local issue_count=$(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "issue")) | length // 0')
    local workflow_count=$(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0')
    
    # 确定锁状态显示
    local lock_status_display
    if [ "$pessimistic_lock_status" = "占用 🔒" ]; then
        lock_status_display="占用 🔒"
    else
        lock_status_display="空闲 🔓"
    fi
    
    cat <<EOF
## 构建队列管理

**最后更新时间：** $current_time

### 当前状态
- **构建锁状态：** $lock_status_display
- **当前构建：** $current_build
- **锁持有者：** $lock_holder
- **版本：** $version

### 混合锁状态
- **乐观锁（排队）：** $optimistic_lock_status
- **悲观锁（构建）：** $pessimistic_lock_status

### 构建队列
- **当前数量：** $queue_length/5
- **Issue触发：** $issue_count/3
- **手动触发：** $workflow_count/5

---

### 队列数据
\`\`\`json
$queue_data
\`\`\`
EOF
}

# 生成队列清理记录
generate_queue_cleanup_record() {
    local current_time="$1"
    local current_version="$2"
    local total_count="$3"
    local issue_count="$4"
    local workflow_count="$5"
    local cleanup_reason="$6"
    local queue_data="$7"
    
    cat <<EOF
## 构建队列管理

**最后更新时间：** $current_time

### 清理记录
- **清理原因：** $cleanup_reason
- **清理时间：** $current_time
- **版本：** $current_version

### 清理后状态
- **构建锁状态：** 空闲 🔓
- **当前构建：** 无
- **锁持有者：** 无

### 构建队列
- **当前数量：** $total_count/5
- **Issue触发：** $issue_count/3
- **手动触发：** $workflow_count/5

---

### 队列数据
\`\`\`json
$queue_data
\`\`\`
EOF
}

# 生成队列重置记录
generate_queue_reset_record() {
    local current_time="$1"
    local reset_reason="$2"
    local queue_data="$3"
    
    cat <<EOF
## 构建队列管理

**最后更新时间：** $current_time

### 重置记录
- **重置原因：** $reset_reason
- **重置时间：** $current_time
- **版本：** 1

### 重置后状态
- **构建锁状态：** 空闲 🔓
- **当前构建：** 无
- **锁持有者：** 无

### 混合锁状态
- **乐观锁（排队）：** 空闲 🔓
- **悲观锁（构建）：** 空闲 🔓

### 构建队列
- **当前数量：** 0/5
- **Issue触发：** 0/3
- **手动触发：** 0/5

---

### 队列数据
\`\`\`json
$queue_data
\`\`\`
EOF
}

# 生成审核评论
generate_review_comment() {
    local rendezvous_server="$1"
    local api_server="$2"
    
    cat <<EOF
## 🔍 构建审核请求

**审核原因：** 检测到私有IP地址，需要管理员审核

### 服务器配置
- **Rendezvous Server：** $rendezvous_server
- **API Server：** $api_server

### 审核选项
请回复以下内容之一：

**同意构建：**
- 确认服务器配置正确
- 同意进行构建

**拒绝构建：**
- 服务器配置有误
- 拒绝进行构建

### 审核说明
- 审核超时时间：6小时
- 超时后构建将自动取消
- 只有仓库所有者和管理员可以审核

---
*此审核请求由构建队列系统自动生成*
EOF
}

# 生成乐观锁通知
generate_optimistic_lock_notification() {
    local operation_type="$1"
    local build_id="$2"
    local queue_position="$3"
    local operation_time="$4"
    local retry_count="$5"
    
    cat <<EOF
## 🔄 乐观锁操作通知

**操作类型：** $operation_type
**构建ID：** $build_id
**队列位置：** $queue_position
**操作时间：** $operation_time
**重试次数：** $retry_count

**状态：** 乐观锁操作完成
**说明：** 使用快速重试机制，减少等待时间
EOF
}

# 生成悲观锁通知
generate_pessimistic_lock_notification() {
    local operation_type="$1"
    local build_id="$2"
    local wait_duration="$3"
    local operation_time="$4"
    local lock_status="$5"
    
    cat <<EOF
## 🔒 悲观锁操作通知

**操作类型：** $operation_type
**构建ID：** $build_id
**等待时间：** ${wait_duration}秒
**操作时间：** $operation_time

**状态：** $lock_status
**说明：** 使用悲观锁确保构建独占性
EOF
}

# 生成队列重置通知
generate_queue_reset_notification() {
    local reset_reason="$1"
    local reset_time="$2"
    
    cat <<EOF
## 🔄 队列重置通知

**重置原因：** $reset_reason
**重置时间：** $reset_time

**状态：** 队列已重置为默认状态
**说明：** 所有队列项已清空，锁已释放
EOF
}

# 生成清理原因文本
generate_cleanup_reasons() {
    local reasons=("$@")
    local reason_text=""
    
    for reason in "${reasons[@]}"; do
        if [ -z "$reason_text" ]; then
            reason_text="$reason"
        else
            reason_text="$reason_text; $reason"
        fi
    done
    
    echo "$reason_text"
}

# 生成清理后的 issue 内容
generate_cleaned_issue_body() {
    local tag="$1"
    local original_tag="$2"
    local customer="$3"
    local slogan="$4"
    
    cat <<EOF
## 构建请求已处理
- 标签: $tag
- 原始标签: $original_tag
- 客户: $customer
- 标语: $slogan

**状态：** 构建已启动
**时间：** $(date '+%Y-%m-%d %H:%M:%S')

---
*敏感信息已自动清理，原始参数已安全保存*
EOF
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 2 ]; then
        echo "Usage: $0 <template_type> <parameters...>"
        echo "Template types: queue_management, hybrid_lock, cleanup, reset, review, optimistic, pessimistic, reset_notification, cleaned_issue"
        exit 1
    fi
    
    local template_type="$1"
    shift 1
    
    case "$template_type" in
        "queue_management")
            generate_queue_management_body "$@"
            ;;
        "hybrid_lock")
            generate_hybrid_lock_status_body "$@"
            ;;
        "cleanup")
            generate_queue_cleanup_record "$@"
            ;;
        "reset")
            generate_queue_reset_record "$@"
            ;;
        "review")
            generate_review_comment "$@"
            ;;
        "optimistic")
            generate_optimistic_lock_notification "$@"
            ;;
        "pessimistic")
            generate_pessimistic_lock_notification "$@"
            ;;
        "reset_notification")
            generate_queue_reset_notification "$@"
            ;;
        "cleaned_issue")
            generate_cleaned_issue_body "$@"
            ;;
        *)
            echo "Unknown template type: $template_type"
            exit 1
            ;;
    esac
fi 
