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

# 获取和解密构建参�?get_and_decrypt_build_params() {
    local current_build_id="$1"
    
    # 获取队列数据
    local queue_manager_issue="1"
    local queue_manager_content=$(get_queue_manager_content "$queue_manager_issue")
    local queue_data=$(extract_queue_json "$queue_manager_content")
    
    if [ $? -ne 0 ]; then
        echo "�?Failed to get queue data"
        return 1
    fi
    
    # 从队列中找到当前构建�?    local current_queue_item=$(echo "$queue_data" | \
        jq -r --arg build_id "$current_build_id" \
        '.queue[] | select(.build_id == $build_id) // empty')
    
    if [ -z "$current_queue_item" ]; then
        echo "�?Current build not found in queue"
        return 1
    fi
    
    # 获取当前队列项的加密参数
    local encrypted_email=$(echo "$current_queue_item" | jq -r '.encrypted_email // empty')
    
    if [ -z "$encrypted_email" ]; then
        echo "�?No encrypted parameters found for current build"
        return 1
    fi
    
    # 解密参数
    local email=$(decrypt_params "$encrypted_email")
    
    # 获取公开参数
    local tag=$(echo "$current_queue_item" | jq -r '.tag // empty')
    local customer=$(echo "$current_queue_item" | jq -r '.customer // empty')
    
    echo "🔐 Decrypted parameters for notification:"
    echo "TAG: $tag"
    echo "EMAIL: $email"
    echo "CUSTOMER: $customer"
    
    # 设置环境变量供后续步骤使�?    echo "FINISH_TAG=$tag" >> $GITHUB_ENV
    echo "FINISH_EMAIL=$email" >> $GITHUB_ENV
    echo "FINISH_CUSTOMER=$customer" >> $GITHUB_ENV
    
    # 返回解密的数�?    echo "TAG=$tag"
    echo "EMAIL=$email"
    echo "CUSTOMER=$customer"
}

# 处理构建完成
process_build_completion() {
    local project_name="$1"
    local build_status="$2"
    local build_artifacts="$3"
    local error_message="$4"
    
    echo "Processing build completion for $project_name"
    
    if [ "$build_status" = "success" ]; then
        echo "�?Build completed successfully"
        echo "Build artifacts: $build_artifacts"
    else
        echo "�?Build failed"
        echo "Error message: $error_message"
    fi
}

# 更新队列状�?update_queue_status() {
    local project_name="$1"
    local status="$2"
    
    # 使用队列管理器更新状�?    update_queue_item_status "$project_name" "$status"
}

# 发送完成通知
send_completion_notification() {
    local project_name="$1"
    local build_status="$2"
    local project_url="$3"
    local build_artifacts="$4"
    local error_message="$5"
    
    echo "Sending completion notification for $project_name"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ "$build_status" = "success" ]; then
        cat > notification.md <<EOF
## 🎉 构建完成通知

**项目�?* $project_name
**状态：** �?成功
**完成时间�?* $timestamp
**项目链接�?* $project_url

### 构建产物
$build_artifacts

---
*此通知由构建队列系统自动生�?
EOF
    else
        cat > notification.md <<EOF
## �?构建失败通知

**项目�?* $project_name
**状态：** �?失败
**失败时间�?* $timestamp
**项目链接�?* $project_url

### 错误信息
$error_message

---
*此通知由构建队列系统自动生�?
EOF
    fi
    
    cat notification.md
    
    # 这里可以添加发送通知的逻辑
    # 例如：发送到Slack、钉钉、邮件等
}

# 清理临时文件
cleanup_temporary_files() {
    echo "Cleaning up temporary files..."
    rm -rf /tmp/build_*
    rm -rf /tmp/cache_*
    echo "Cleanup completed"
}

# 释放构建锁（使用混合锁策略）
release_build_lock() {
    local run_id="$1"
    
    echo "Releasing build lock using hybrid lock strategy..."
    
    # 使用混合锁策略释放锁
    source .github/workflows/scripts/hybrid-lock.sh
    main_hybrid_lock "release_lock" "$run_id" "1"
    
    # 检查结�?    if [ $? -eq 0 ]; then
        echo "�?Successfully released build lock"
        return 0
    else
        echo "�?Failed to release build lock"
        return 1
    fi
}

# 最终处�?final_processing() {
    local final_input="$1"
    
    # 使用jq解析单行JSON
    echo "Final data: $final_input"
    echo "Ready status: $(jq -r '.ready' <<< "$final_input")"
    echo "Version: $(jq -r '.version' <<< "$final_input")"
}

# 生成报告
generate_report() {
    local project_name="$1"
    local trigger_type="$2"
    local issue_number="$3"
    
    echo "Build completed successfully"
    
    # 只在issue模式下添加构建完成评�?    if [ "$trigger_type" = "issue" ] && [ -n "$issue_number" ]; then
        local completion_comment=$(cat <<EOF
## �?构建完成

**状态：** 构建已完�?**构建锁：** 已释�?🔓
**时间�?* $(date '+%Y-%m-%d %H:%M:%S')
下一个队列项目可以开始构建�?EOF
)

        curl -X POST \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/comments \
            -d "$(jq -n --arg body "$completion_comment" '{"body": $body}')"
    fi
}

# 最终状态更�?final_status_update() {
    local project_name="$1"
    local build_status="$2"
    
    echo "Final status update for $project_name"
    echo "Build process finished with status: $build_status"
    echo "Queue has been updated and lock released"
    echo "All cleanup tasks completed"
}

# 主完成函�?process_finish() {
    local project_name="$1"
    local project_url="$2"
    local build_status="$3"
    local build_artifacts="$4"
    local error_message="$5"
    local run_id="$6"
    local trigger_type="$7"
    local issue_number="$8"
    
    echo "Starting finish process for $project_name..."
    
    # 设置完成环境
    setup_finish_environment "$project_name" "$build_status" "$project_url"
    
    # 获取和解密构建参�?    local decrypted_params=$(get_and_decrypt_build_params "$run_id")
    if [ $? -eq 0 ]; then
        eval "$decrypted_params"
    fi
    
    # 处理构建完成
    process_build_completion "$project_name" "$build_status" "$build_artifacts" "$error_message"
    
    # 更新队列状�?    update_queue_status "$project_name" "$build_status"
    
    # 发送完成通知
    send_completion_notification "$project_name" "$build_status" "$project_url" "$build_artifacts" "$error_message"
    
    # 清理临时文件
    cleanup_temporary_files
    
    # 释放构建�?    release_build_lock "$run_id"
    
    # 最终处�?    final_processing "$project_name"
    
    # 生成报告
    generate_report "$project_name" "$trigger_type" "$issue_number"
    
    # 最终状态更�?    final_status_update "$project_name" "$build_status"
    
    echo "Finish process completed successfully"
} 
