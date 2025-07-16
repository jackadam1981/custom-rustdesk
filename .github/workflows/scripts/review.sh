#!/bin/bash
# 审核和验证脚本
# 这个文件处理构建审核和参数验证逻辑

# 加载依赖脚本
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh



# 检查是否为私有IP地址
check_private_ip() {
    local ip="$1"
    
    # 如果为空，返回false
    if [ -z "$ip" ]; then
        return 1
    fi
    
    # 移除协议前缀（http:// 或 https://）
    local clean_ip="$ip"
    if [[ "$ip" =~ ^https?:// ]]; then
        clean_ip="${ip#*://}"
    fi
    
    # 移除端口号（如果存在）
    if [[ "$clean_ip" =~ :[0-9]+$ ]]; then
        clean_ip="${clean_ip%:*}"
    fi
    
    # 检查是否为域名（包含字母）
    if [[ "$clean_ip" =~ [a-zA-Z] ]]; then
        echo "Domain detected: $clean_ip"
        return 1  # 域名不是私有IP
    fi
    
    # 检查私有IP地址范围
    # 10.0.0.0/8
    if [[ "$clean_ip" =~ ^10\. ]]; then
        return 0
    fi
    
    # 172.16.0.0/12
    if [[ "$clean_ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        return 0
    fi
    
    # 192.168.0.0/16
    if [[ "$clean_ip" =~ ^192\.168\. ]]; then
        return 0
    fi
    
    # 127.0.0.0/8 (localhost)
    if [[ "$clean_ip" =~ ^127\. ]]; then
        return 0
    fi
    
    # 169.254.0.0/16 (link-local)
    if [[ "$clean_ip" =~ ^169\.254\. ]]; then
        return 0
    fi
    
    # 如果不是私有IP，返回false
    return 1
}

# 验证服务器参数
validate_server_parameters() {
    local rendezvous_server="$1"
    local api_server="$2"
    local email="$3"
    
    # 验证邮箱格式
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "邮箱格式无效: $email"
        return 1
    fi
    
    # 验证服务器地址格式（基本格式检查）
    # 支持IP地址、域名，可选端口号，API服务器支持http/https协议
    if [[ ! "$rendezvous_server" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
        echo "Rendezvous服务器地址格式无效: $rendezvous_server"
        return 1
    fi
    
    # API服务器支持http/https协议前缀
    if [[ ! "$api_server" =~ ^(https?://)?[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
        echo "API服务器地址格式无效: $api_server"
        return 1
    fi
    
    # 所有验证通过
    return 0
}

# 设置数据
setup_review_data() {
    local trigger_output="$1"
    
    if [ -z "$trigger_output" ]; then
        echo "No trigger output provided"
        return 1
    fi
    
    echo "TRIGGER_OUTPUT=$trigger_output" >> $GITHUB_ENV
}

# 提取数据
extract_and_validate_data() {
    local input="$1"
    
    # 简单输出接收到的数据（重定向到stderr避免被当作变量赋值）
    echo "Review.sh接收到输入数据" >&2
    
    # 直接使用输入数据
    local parsed_input="$input"
    
    # 提取服务器地址
    local rendezvous_server=$(echo "$parsed_input" | jq -r '.rendezvous_server // empty')
    local api_server=$(echo "$parsed_input" | jq -r '.api_server // empty')
    local email=$(echo "$parsed_input" | jq -r '.email // empty')
    
    # 设置环境变量供后续步骤使用
    echo "RENDEZVOUS_SERVER=$rendezvous_server" >> $GITHUB_ENV
    echo "API_SERVER=$api_server" >> $GITHUB_ENV
    echo "EMAIL=$email" >> $GITHUB_ENV
    echo "CURRENT_DATA=$parsed_input" >> $GITHUB_ENV
    
    # 调试输出（重定向到stderr避免干扰JSON解析）
    echo "Extracted data:" >&2
    echo "RENDEZVOUS_SERVER: $rendezvous_server" >&2
    echo "API_SERVER: $api_server" >&2
    echo "EMAIL: $email" >&2
    
    # 返回提取的数据
    echo "RENDEZVOUS_SERVER=$rendezvous_server"
    echo "API_SERVER=$api_server"
    echo "EMAIL=$email"
    echo "PARSED_INPUT=$parsed_input"
}

# 自动拒绝无效的服务器参数
auto_reject_invalid_parameters() {
    local rendezvous_server="$1"
    local api_server="$2"
    local email="$3"
    
    # 检查参数是否为空    
    if [ -z "$rendezvous_server" ] || [ -z "$api_server" ] || [ -z "$email" ]; then
        echo "Missing required parameters"
        echo "RENDEZVOUS_SERVER: $rendezvous_server"
        echo "API_SERVER: $api_server"
        echo "EMAIL: $email"
        
        local reject_comment=$(generate_reject_comment "缺少必要的服务器参数" "Rendezvous Server: $rendezvous_server\n- API Server: $api_server\n- Email: $email")
        
        echo "BUILD_REJECTED=true" >> $GITHUB_ENV
        echo "REJECT_REASON=Missing required parameters" >> $GITHUB_ENV
        echo "REJECT_COMMENT=$reject_comment" >> $GITHUB_ENV
        return 1
    fi
    
    # 验证服务器参数
    if ! validate_server_parameters "$rendezvous_server" "$api_server" "$email"; then
        local auto_reject_reason="服务器参数验证失败"
        echo "自动拒绝原因: $auto_reject_reason"
        
        local reject_comment=$(generate_reject_comment "$auto_reject_reason" "")
        
        # 获取原始issue编号
        local original_issue_number=$(get_original_issue_number)
        
        if [ -n "$original_issue_number" ]; then
            add_issue_comment "$original_issue_number" "$reject_comment"
        fi
        
        echo "BUILD_REJECTED=true" >> $GITHUB_ENV
        echo "REJECT_COMMENT=$reject_comment" >> $GITHUB_ENV
        return 1
    else
        echo "All parameter validations passed"
        return 0
    fi
}

# 确定是否需要审核
determine_review_requirement() {
    local rendezvous_server="$1"
    local api_server="$2"
    local actor="$3"
    local repo_owner="$4"
    
    # 默认需要审核    
    local need_review=true

    # 仓库所有者免审核
    if [ "$actor" = "$repo_owner" ]; then
        echo "Repo owner detected, skipping review."
        need_review=false
    fi
    
    # 检查是否为私有IP地址
    local rendezvous_private=false
    local api_private=false
    
    echo "Checking Rendezvous Server: $rendezvous_server"
    if [ -n "$rendezvous_server" ] && check_private_ip "$rendezvous_server"; then
        rendezvous_private=true
        echo "Rendezvous server is private IP: $rendezvous_server"
    else
        echo "Rendezvous server is public IP or domain: $rendezvous_server"
    fi
    
    echo "Checking API Server: $api_server"
    if [ -n "$api_server" ] && check_private_ip "$api_server"; then
        api_private=true
        echo "API server is private IP: $api_server"
    else
        echo "API server is public IP or domain: $api_server"
    fi
    
    # 判断是否需要审核    
    if [ "$need_review" = "false" ]; then
        echo "Skipping review due to repo owner or private IP check."
    else
        if [ "$rendezvous_private" = "true" ] && [ "$api_private" = "true" ]; then
            need_review=false
            echo "Both servers are private IPs - no review needed"
        else
            need_review=true
            echo "At least one server is public IP - review required"
        fi
    fi
    
    # 设置审核标记到环境变量，供后续步骤使用
    echo "NEED_REVIEW=$need_review" >> $GITHUB_ENV
    echo "$need_review"
}

# 处理审核流程
handle_review_process() {
    local rendezvous_server="$1"
    local api_server="$2"
    local original_issue_number="$3"
    
    echo "Review required. Starting review process..."
    
    # 在issue中添加审核状态
    local review_comment=$(generate_review_comment "$rendezvous_server" "$api_server")
    
    if [ -n "$original_issue_number" ]; then
        add_issue_comment "$original_issue_number" "$review_comment"
    fi
    
    # 循环检查审核回复
    local start_time=$(date +%s)
    local timeout=21600  # 6小时超时
    local approved=false
    local rejected=false
    
    while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
        echo "Checking for admin approval... ($(($(date +%s) - start_time))s elapsed)"
        
        # 获取issue的最新评论
        local comments=$(curl -s \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$original_issue_number/comments")
        
        # 检查是否有管理员回复        
        # 获取仓库所有者和管理员列表        
        local repo_owner="$GITHUB_REPOSITORY_OWNER"
        
        # 检查是否有管理员回复（包括仓库所有者）
        if echo "$comments" | jq -e --arg owner "$repo_owner" '.[] | select(.user.login == $owner or .user.login == "admin" or .user.login == "管理员用户名") | select(.body | contains("同意构建"))' > /dev/null; then
            approved=true
            break
        fi
        
        if echo "$comments" | jq -e --arg owner "$repo_owner" '.[] | select(.user.login == $owner or .user.login == "admin" or .user.login == "管理员用户名") | select(.body | contains("拒绝构建"))' > /dev/null; then
            rejected=true
            break
        fi
        
        # 调试：输出最新的评论信息
        echo "Latest comments:"
        echo "$comments" | jq -r '.[-3:] | .[] | "User: \(.user.login), Body: \(.body[0:100])..."'
        
        # 等待30秒后再次检查        
        sleep 30
    done
    
    if [ "$approved" = true ]; then
        echo "Admin approval received"
        # 添加审核通过评论
        local approval_comment=$(generate_approval_comment)
        
        if [ -n "$original_issue_number" ]; then
            add_issue_comment "$original_issue_number" "$approval_comment"
        fi
        return 0
    elif [ "$rejected" = true ]; then
        echo "Build rejected by admin"
        
        # 添加拒绝评论
        local reject_comment=$(generate_admin_reject_comment)
        
        if [ -n "$original_issue_number" ]; then
            add_issue_comment "$original_issue_number" "$reject_comment"
        fi
        
        echo "Build rejected by admin - setting build_approved to false"
        # 设置构建被拒绝标志        
        echo "BUILD_REJECTED=true" >> $GITHUB_ENV
        return 1
    else
        echo "Review timeout after 6 hours"
        # 添加超时评论
        local timeout_comment=$(generate_timeout_comment)
        
        if [ -n "$original_issue_number" ]; then
            add_issue_comment "$original_issue_number" "$timeout_comment"
        fi
        
        return 2
    fi
}

# 获取原始issue编号
get_original_issue_number() {
    curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs" | \
        jq -r '.jobs[0].steps[] | select(.name == "Setup framework") | .outputs.build_id // empty'
}

# 生成拒绝评论
generate_reject_comment() {
    local reason="$1"
    local details="$2"
    
    cat <<EOF
## 构建被自动拒绝
**拒绝原因** $reason
$details

**时间** $(date '+%Y-%m-%d %H:%M:%S')
请检查参数后重新提交issueEOF
}

# 生成审核评论
generate_review_comment() {
    local rendezvous_server="$1"
    local api_server="$2"
    
    cat <<EOF
## 🔍 审核状态
**需要审核原因：** 检测到公网IP地址或域名- Rendezvous Server: $rendezvous_server
- API Server: $api_server

**审核要求** 请管理员回复 '同意构建' 或 '拒绝构建'

**状态：** 等待审核
**时间** $(date '+%Y-%m-%d %H:%M:%S')
EOF
}

# 生成审核通过评论
generate_approval_comment() {
    cat <<EOF
## 审核通过
**状态：** 审核通过
**时间** $(date '+%Y-%m-%d %H:%M:%S')
EOF
}

# 生成管理员拒绝评论
generate_admin_reject_comment() {
    cat <<EOF
## 构建被拒绝
**状态：** 构建已被管理员拒绝
**时间** $(date '+%Y-%m-%d %H:%M:%S')
构建流程已终止。如需重新构建，请重新提交issue
EOF
}

# 生成超时评论
generate_timeout_comment() {
    cat <<EOF
## 审核超时
**状态：** 审核超时
**时间** $(date '+%Y-%m-%d %H:%M:%S')
构建将自动终止。如需重新构建，请重新提交issue
EOF
}

# 输出数据
output_data() {
    local current_data="$1"
    local build_rejected="$2"
    local build_timeout="$3"
    
    # 简单输出数据（重定向到stderr避免被当作变量赋值）
    echo "Review.sh输出数据" >&2
    
    # 输出到GitHub Actions输出变量（使用多行格式避免截断）
    echo "data<<EOF" >> $GITHUB_OUTPUT
    echo "$current_data" >> $GITHUB_OUTPUT
    echo "EOF" >> $GITHUB_OUTPUT
    
    # 根据标志设置构建批准状态    
    if [ "$build_rejected" = "true" ]; then
        echo "validation_passed=false" >> $GITHUB_OUTPUT
        echo "reject_reason=Build was rejected by admin" >> $GITHUB_OUTPUT
        echo "Build was rejected by admin"
    elif [ "$build_timeout" = "true" ]; then
        echo "validation_passed=false" >> $GITHUB_OUTPUT
        echo "reject_reason=Build timed out during review" >> $GITHUB_OUTPUT
        echo "Build timed out during review"
    else
        echo "validation_passed=true" >> $GITHUB_OUTPUT
        echo "reject_reason=" >> $GITHUB_OUTPUT
        echo "Build was approved or no review needed"
    fi
    
    # 显示输出信息
    echo "Review output: $current_data"
}

# 输出被拒绝构建的数据
output_rejected_data() {
    echo "data={}" >> $GITHUB_OUTPUT
    echo "validation_passed=false" >> $GITHUB_OUTPUT
    echo "reject_reason=Build was rejected - no data to pass forward" >> $GITHUB_OUTPUT
    echo "Build was rejected - no data to pass forward"
}

# 主处理函数
process_review() {
    local trigger_output="$1"
    local actor="$2"
    local repo_owner="$3"
    
    # 设置审核数据
    setup_review_data "$trigger_output"
    
    # 提取和验证数据    
    local extracted_data=$(extract_and_validate_data "$trigger_output")
    # 安全地设置变量，避免eval破坏JSON格式
    while IFS='=' read -r var_name var_value; do
        if [[ "$var_name" == "PARSED_INPUT" ]]; then
            # 对于JSON数据，使用printf安全设置
            printf -v "$var_name" '%s' "$var_value"
        else
            # 对于普通变量，直接设置
            eval "$var_name=\"$var_value\""
        fi
    done <<< "$extracted_data"
    
    # 自动拒绝无效参数
    if ! auto_reject_invalid_parameters "$RENDEZVOUS_SERVER" "$API_SERVER" "$EMAIL"; then
        return 1
    fi
    
    # 确定是否需要审核    
    local need_review=$(determine_review_requirement "$RENDEZVOUS_SERVER" "$API_SERVER" "$actor" "$repo_owner")
    
    # 如果需要审核，处理审核流程
    if [ "$need_review" = "true" ]; then
        local original_issue_number=$(get_original_issue_number)
        handle_review_process "$RENDEZVOUS_SERVER" "$API_SERVER" "$original_issue_number"
        local review_result=$?
        
        if [ $review_result -eq 1 ]; then
            # 被拒绝
            return 1
        elif [ $review_result -eq 2 ]; then
            # 超时
            echo "BUILD_TIMEOUT=true" >> $GITHUB_ENV
            output_rejected_data
            return 1
        fi
    fi
    
    # 输出数据
    output_data "$PARSED_INPUT" "$BUILD_REJECTED" "$BUILD_TIMEOUT"
} 
