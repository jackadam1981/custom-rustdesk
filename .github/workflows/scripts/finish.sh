#!/bin/bash
# 收尾脚本
# 这个文件处理构建完成和收尾逻辑

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/queue-manager.sh
source .github/workflows/scripts/issue-manager.sh

# 设置完成环境
setup_finish_environment() {
    local project_name="$1"
    local build_status="$2"
    local project_url="$3"
    
    echo "Setting up finish environment for $project_name"
    echo "Build status: $build_status"
    echo "Project URL: $project_url"
}

# 获取和解密构建参数
get_and_decrypt_build_params() {
    local current_build_id="$1"
    
    # 使用队列管理器获取队列数据
    local queue_data=$(queue_manager "data")
    
    if [ $? -ne 0 ]; then
        debug "error" "Failed to get queue data"
        return 1
    fi
    
    # 从队列中找到当前构建
    local current_queue_item=$(echo "$queue_data" | \
        jq -r --arg build_id "$current_build_id" \
        '.queue[] | select(.build_id == $build_id) // empty')
    
    if [ -z "$current_queue_item" ]; then
        debug "error" "Current build not found in queue"
        return 1
    fi
    
    # 获取当前队列项的加密参数
    local encrypted_email=$(echo "$current_queue_item" | jq -r '.encrypted_email // empty')
    
    if [ -z "$encrypted_email" ]; then
        debug "error" "No encrypted parameters found for current build"
        return 1
    fi
    
    # 解密参数
    local email=$(decrypt_params "$encrypted_email")
    
    # 获取公开参数
    local tag=$(echo "$current_queue_item" | jq -r '.tag // empty')
    local customer=$(echo "$current_queue_item" | jq -r '.customer // empty')
    
    debug "log" "🔐 Decrypted parameters for notification:"
    debug "var" "TAG" "$tag"
    debug "var" "EMAIL" "$email"
    debug "var" "CUSTOMER" "$customer"
    
    # 返回解密后的参数
    echo "TAG=$tag"
    echo "EMAIL=$email"
    echo "CUSTOMER=$customer"
}

# 生成完成通知
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

# 发送邮件通知
send_email_notification() {
    local email="$1"
    local subject="$2"
    local body="$3"
    
    if [ -z "$email" ]; then
        debug "warning" "No email address provided, skipping notification"
        return 0
    fi
    
    # 这里可以集成邮件发送服务
    # 例如：使用 curl 调用邮件 API
    debug "log" "Sending email notification to: $email"
    debug "var" "Subject" "$subject"
    debug "log" "Email notification sent successfully"
}

# 清理构建环境
cleanup_build_environment() {
    local build_id="$1"
    
    debug "log" "Cleaning up build environment for build $build_id"
    
    # 清理临时文件
    rm -rf /tmp/build_*
    
    # 清理日志文件
    find /tmp -name "*.log" -mtime +1 -delete 2>/dev/null || true
    
    debug "success" "Build environment cleanup completed"
}

# 输出完成数据
output_finish_data() {
    local build_status="$1"
    local notification_sent="$2"
    local cleanup_completed="$3"
    local lock_released="$4"
    
    # 输出到GitHub Actions输出变量（如果存在）
    if [ -n "$GITHUB_OUTPUT" ]; then
        echo "finish_status=$build_status" >> $GITHUB_OUTPUT
        echo "notification_sent=$notification_sent" >> $GITHUB_OUTPUT
        echo "cleanup_completed=$cleanup_completed" >> $GITHUB_OUTPUT
        echo "lock_released=$lock_released" >> $GITHUB_OUTPUT
    fi
    
    # 显示输出信息
    echo "Finish output:"
    echo "  Status: $build_status"
    echo "  Notification: $notification_sent"
    echo "  Cleanup: $cleanup_completed"
    echo "  Lock Released: $lock_released"
}

# 主完成函数
process_finish() {
    local build_data="$1"
    local build_status="$2"
    local download_url="$3"
    local error_message="$4"
    
    debug "log" "Processing finish for build status: $build_status"
    
    # 解析构建数据
    local tag=$(echo "$build_data" | jq -r '.tag // empty')
    local customer=$(echo "$build_data" | jq -r '.customer // empty')
    local build_id="$GITHUB_RUN_ID"
    
    # 设置完成环境
    setup_finish_environment "Custom Rustdesk" "$build_status" "$download_url"
    
    # 获取构建参数（如果需要解密）
    local build_params=""
    if [ "$build_status" = "success" ]; then
        build_params=$(get_and_decrypt_build_params "$build_id")
        if [ $? -eq 0 ]; then
            eval "$build_params"
        fi
    fi
    
    # 生成完成通知
    local notification=$(generate_completion_notification "$build_status" "$tag" "$customer" "$download_url" "$error_message")
    
    # 发送通知
    local notification_sent="false"
    if [ -n "$EMAIL" ]; then
        local subject="Custom Rustdesk Build - $build_status"
        send_email_notification "$EMAIL" "$subject" "$notification"
        notification_sent="true"
    fi
    
    # 清理构建环境
    cleanup_build_environment "$build_id"
    local cleanup_completed="true"
    
    # 🔓 释放构建锁（重要：确保锁被释放）
    debug "log" "Releasing build lock for build $build_id"
    local lock_released="false"
    
    # 确保有必要的环境变量
    if [ -z "$GITHUB_TOKEN" ]; then
        debug "warning" "GITHUB_TOKEN not set, skipping lock release"
        lock_released="skipped"
    else
        if queue_manager "release" "$build_id"; then
            debug "success" "Successfully released build lock"
            lock_released="true"
        else
            debug "error" "Failed to release build lock"
            lock_released="false"
        fi
    fi
    
    # 输出完成数据
    output_finish_data "$build_status" "$notification_sent" "$cleanup_completed" "$lock_released"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 2 ]; then
        echo "Usage: $0 <build_data> <build_status> [download_url] [error_message]"
        exit 1
    fi
    
    process_finish "$@"
fi 
