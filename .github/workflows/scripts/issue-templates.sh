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

# 生成构建拒绝回复
generate_build_rejection_comment() {
    local reject_reason="$1"
    local current_time="$2"
    
    cat <<EOF
## ❌ 构建请求被拒绝

**拒绝原因：** $reject_reason

**拒绝时间：** $current_time

请检查构建参数后重新提交请求。

---
*如有疑问，请联系管理员*
EOF
}

# 生成综合拒绝回复（包含所有问题）
generate_comprehensive_rejection_comment() {
    local issues_json="$1"
    local current_time="$2"
    
    # 解析问题列表
    local issues_count=$(echo "$issues_json" | jq 'length' 2>/dev/null)
    
    cat <<EOF
## ❌ 构建请求被拒绝

**拒绝时间：** $current_time

**发现的问题：** ($issues_count 个问题)

EOF
    
    # 输出每个问题
    echo "$issues_json" | jq -r '.[]' 2>/dev/null | while IFS= read -r issue; do
        echo "- ❌ $issue"
    done
    
    cat <<EOF

### 修复建议
1. **缺失参数：** 请填写所有必需的服务器参数
2. **邮箱格式：** 请使用有效的邮箱地址格式（如：user@example.com）
3. **公网地址：** 使用公网IP或域名需要管理员审核，请使用私有IP地址或联系管理员

### 重新提交
请修复上述问题后重新提交构建请求。

---
*如有疑问，请联系管理员*
EOF
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

**状态：** 已清理隐私
**时间：** $(date '+%Y-%m-%d %H:%M:%S')

---
*敏感信息已自动清理，原始参数已安全保存*
EOF
}

# 生成拒绝评论
generate_rejection_comment() {
    local username="$1"
    local reason="$2"
    
    cat <<EOF
## ❌ 构建请求被拒绝

**用户：** @$username
**拒绝原因：** $reason

**拒绝时间：** $(date '+%Y-%m-%d %H:%M:%S')

请检查构建参数后重新提交请求。

---
*如有疑问，请联系管理员*
EOF
}

# 生成批准评论
generate_approval_comment() {
    local username="$1"
    local message="$2"
    
    cat <<EOF
## ✅ 构建请求已批准

**用户：** @$username
**状态：** $message

**批准时间：** $(date '+%Y-%m-%d %H:%M:%S')

构建已加入队列，请等待构建完成。

---
*构建进度将通过评论更新*
EOF
}

# 生成构建开始评论
generate_build_start_comment() {
    local username="$1"
    local build_id="$2"
    local queue_position="$3"
    
    cat <<EOF
## 🚀 构建已开始

**用户：** @$username
**构建ID：** $build_id
**队列位置：** $queue_position

**开始时间：** $(date '+%Y-%m-%d %H:%M:%S')

构建正在执行中，请耐心等待...

---
*构建完成后将自动更新状态*
EOF
}

# 生成构建成功评论
generate_build_success_comment() {
    local username="$1"
    local build_id="$2"
    local build_url="$3"
    local duration="$4"
    
    cat <<EOF
## ✅ 构建成功完成

**用户：** @$username
**构建ID：** $build_id
**构建时长：** ${duration}秒

**完成时间：** $(date '+%Y-%m-%d %H:%M:%S')

### 构建结果
- **状态：** 成功 ✅
- **构建日志：** [查看详情]($build_url)
- **下载地址：** 请查看构建日志中的下载链接

### 使用说明
1. 下载构建产物
2. 解压并安装
3. 配置服务器参数
4. 启动服务

---
*构建已完成，issue将自动关闭*
EOF
}

# 生成构建失败评论
generate_build_failure_comment() {
    local username="$1"
    local build_id="$2"
    local build_url="$3"
    local error_message="$4"
    local duration="$5"
    
    cat <<EOF
## ❌ 构建失败

**用户：** @$username
**构建ID：** $build_id
**构建时长：** ${duration}秒

**失败时间：** $(date '+%Y-%m-%d %H:%M:%S')

### 构建结果
- **状态：** 失败 ❌
- **构建日志：** [查看详情]($build_url)
- **错误信息：** $error_message

### 可能的原因
1. 编译错误
2. 依赖缺失
3. 配置错误
4. 网络问题

### 建议操作
1. 检查构建日志
2. 修复错误
3. 重新提交构建请求

---
*如需帮助，请联系管理员*
EOF
}

# 生成超时评论
generate_timeout_comment() {
    local username="$1"
    local timeout_type="$2"
    local timeout_duration="$3"
    
    cat <<EOF
## ⏰ 操作超时

**用户：** @$username
**超时类型：** $timeout_type
**超时时长：** ${timeout_duration}秒

**超时时间：** $(date '+%Y-%m-%d %H:%M:%S')

### 超时说明
- 审核超时：管理员未在指定时间内审核
- 构建超时：构建过程超过最大时间限制
- 等待超时：等待锁释放超过最大时间

### 建议操作
1. 检查网络连接
2. 重新提交请求
3. 联系管理员

---
*系统将自动清理相关资源*
EOF
}

# 生成队列满员评论
generate_queue_full_comment() {
    local username="$1"
    local current_count="$2"
    local max_count="$3"
    
    cat <<EOF
## 🚫 队列已满

**用户：** @$username
**当前队列：** $current_count/$max_count

**拒绝时间：** $(date '+%Y-%m-%d %H:%M:%S')

### 队列状态
- **当前数量：** $current_count
- **最大容量：** $max_count
- **状态：** 队列已满，无法接受新请求

### 建议操作
1. 等待队列中的构建完成
2. 稍后重新提交请求
3. 联系管理员增加队列容量

---
*队列状态会定期更新*
EOF
}

# 生成权限不足评论
generate_permission_denied_comment() {
    local username="$1"
    local required_permission="$2"
    
    cat <<EOF
## 🔒 权限不足

**用户：** @$username
**所需权限：** $required_permission

**拒绝时间：** $(date '+%Y-%m-%d %H:%M:%S')

### 权限说明
- **当前权限：** 普通用户
- **所需权限：** $required_permission
- **权限范围：** 仓库所有者和管理员

### 建议操作
1. 联系仓库所有者
2. 请求管理员权限
3. 使用其他方式提交构建请求

---
*权限问题请联系仓库管理员*
EOF
} 

# 生成构建完成通知模板
generate_completion_notification() {
    local build_status="$1"
    local tag="$2"
    local customer="$3"
    local download_url="$4"
    local error_message="$5"
    
    local notification_body=""
    
    if [ "$build_status" = "success" ]; then
        notification_body=$(cat <<EOF
## ✅ 构建完成通知

**构建状态：** 成功
**构建标签：** $tag
**客户：** $customer
**完成时间：** $(date '+%Y-%m-%d %H:%M:%S')

### 下载信息
- **下载链接：** $download_url
- **文件大小：** 约 50MB
- **支持平台：** Windows, macOS, Linux

### 使用说明
1. 下载并解压文件
2. 运行对应的可执行文件
3. 使用配置的服务器地址连接

---
*如有问题，请联系技术支持*
EOF
)
    else
        notification_body=$(cat <<EOF
## ❌ 构建失败通知

**构建状态：** 失败
**构建标签：** $tag
**客户：** $customer
**失败时间：** $(date '+%Y-%m-%d %H:%M:%S')

### 错误信息
$error_message

### 建议操作
1. 检查构建参数是否正确
2. 确认服务器配置是否有效
3. 重新提交构建请求

---
*如需帮助，请联系技术支持*
EOF
)
    fi
    
    echo "$notification_body"
} 
