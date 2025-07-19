#!/bin/bash
# 审核和验证脚本
# 这个文件处理构建审核和参数验证逻辑

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
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
        debug "log" "Domain detected: $clean_ip"
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
    
    # 检查关键参数是否为空
    if [ -z "$rendezvous_server" ] || [ -z "$api_server" ]; then
        echo "Critical server parameters are missing"
        return 1
    fi
    
    # 检查是否为私有IP
    if check_private_ip "$rendezvous_server"; then
        echo "Rendezvous server is a private IP: $rendezvous_server"
        return 0  # 需要审核
    fi
    
    if check_private_ip "$api_server"; then
        echo "API server is a private IP: $api_server"
        return 0  # 需要审核
    fi
    
    # 检查邮箱格式
    if [ -n "$email" ] && [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "Invalid email format: $email"
        return 1
    fi
    
    echo "All parameters are valid"
    return 0
}

# 设置审核数据
setup_review_data() {
    local trigger_output="$1"
    
    # 设置环境变量
    echo "TRIGGER_OUTPUT=$trigger_output" >> $GITHUB_ENV
    echo "BUILD_REJECTED=false" >> $GITHUB_ENV
    echo "BUILD_TIMEOUT=false" >> $GITHUB_ENV
}

# 确定是否需要审核
determine_review_requirement() {
    local trigger_type="$1"
    local rendezvous_server="$2"
    local api_server="$3"
    local actor="$4"
    local repo_owner="$5"
    
    debug "var" "Trigger type" "$trigger_type"
    debug "var" "Rendezvous server" "$rendezvous_server"
    debug "var" "API server" "$api_server"
    debug "var" "Actor" "$actor"
    debug "var" "Repo owner" "$repo_owner"
    
    # 手动触发：无需审核
    if [ "$trigger_type" = "workflow_dispatch" ]; then
        debug "log" "Manual trigger - no review needed"
        echo "false"
        return 0
    fi
    
    # Issue触发：需要审核
    if [ "$trigger_type" = "issue" ]; then
        # 如果是仓库所有者，不需要审核
        if [ "$actor" = "$repo_owner" ]; then
            debug "log" "Issue trigger by repo owner - no review needed"
            echo "false"
            return 0
        fi
        
        # 检查是否为公网IP或域名（需要审核）
        if [ -n "$rendezvous_server" ] && ! check_private_ip "$rendezvous_server"; then
            debug "log" "Rendezvous server is public IP/domain - review needed"
            echo "true"
            return 0
        fi
        
        if [ -n "$api_server" ] && ! check_private_ip "$api_server"; then
            debug "log" "API server is public IP/domain - review needed"
            echo "true"
            return 0
        fi
        
        # 私有IP无需审核
        debug "log" "Private IP detected - no review needed"
        echo "false"
        return 0
    fi
    
    echo "false"
}

# 并行检查所有参数
validate_all_parameters() {
    local rendezvous_server="$1"
    local api_server="$2"
    local email="$3"
    
    local issues=()
    local has_issues=false
    
    # 检查关键服务器参数是否为空
    if [ -z "$rendezvous_server" ]; then
        issues+=("Rendezvous server is missing")
        has_issues=true
    fi
    
    if [ -z "$api_server" ]; then
        issues+=("API server is missing")
        has_issues=true
    fi
    
    # 检查邮箱格式
    if [ -n "$email" ] && [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        issues+=("Invalid email format: $email")
        has_issues=true
    fi
    
    # 注意：公网IP和域名不需要在这里检查，它们会在审核流程中处理
    # 这里只检查真正的验证错误（缺失参数、无效邮箱等）
    
    # 返回结果
    if [ "$has_issues" = "true" ]; then
        # 将问题数组转换为JSON字符串
        local issues_json=$(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .)
        echo "$issues_json"
        return 0  # 返回0表示有问题
    else
        echo "[]"
        return 1  # 返回1表示没有问题
    fi
}

# 获取原始issue编号
get_original_issue_number() {
    # 如果是Issue触发，直接从github.event中获取Issue编号
    if [ "$GITHUB_EVENT_NAME" = "issues" ] && [ -n "$GITHUB_EVENT_PATH" ]; then
        # 从github.event文件中读取Issue编号
        jq -r '.issue.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null
    else
        # 备用方法：通过API调用获取（保持向后兼容）
        curl -s \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs" | \
            jq -r '.jobs[0].steps[] | select(.name == "Setup framework") | .outputs.build_id // empty'
    fi
}

# 提取和验证数据
extract_and_validate_data() {
    local input="$1"
    
    # 简单输出接收到的数据（重定向到stderr避免被当作变量赋值）
    debug "log" "Review.sh接收到输入数据"
    
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
    debug "log" "Extracted data:"
    debug "var" "RENDEZVOUS_SERVER" "$rendezvous_server"
    debug "var" "API_SERVER" "$api_server"
    debug "var" "EMAIL" "$email"
    
    # 返回提取的数据
    echo "RENDEZVOUS_SERVER=$rendezvous_server"
    echo "API_SERVER=$api_server"
    echo "EMAIL=$email"
    echo "PARSED_INPUT=$parsed_input"
}

# 处理审核流程
handle_review_process() {
    local rendezvous_server="$1"
    local api_server="$2"
    local original_issue_number="$3"
    
    debug "log" "Review required. Starting review process..."
    
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
        debug "log" "Checking for admin approval... ($(($(date +%s) - start_time))s elapsed)"
        
        # 获取issue的最新评论
        local comments=$(curl -s \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$original_issue_number/comments")
        
        # 检查是否有管理员回复        
        # 获取仓库所有者和管理员列表        
        local repo_owner="$GITHUB_REPOSITORY_OWNER"
        
        # 检查是否有管理员回复（包括仓库所有者）
        if echo "$comments" | jq -e --arg owner "$repo_owner" '.[] | select(.user.login == $owner or .user.login == "admin" or .user.login == "管理员用户名") | select(.body | contains("同意构建"))' > /dev/null 2>&1; then
            approved=true
            break
        fi
        
        if echo "$comments" | jq -e --arg owner "$repo_owner" '.[] | select(.user.login == $owner or .user.login == "admin" or .user.login == "管理员用户名") | select(.body | contains("拒绝构建"))' > /dev/null 2>&1; then
            rejected=true
            break
        fi
        
        # 调试：输出最新的评论信息
        debug "log" "Latest comments:"
        if echo "$comments" | jq -e '.[]' > /dev/null 2>&1; then
            debug "log" "Comments found:"
            echo "$comments" | jq -r '.[-3:] | .[] | "\(.user.login): \(.body)"' | head -10 | while IFS= read -r comment; do
                debug "log" "  $comment"
            done
        else
            debug "log" "No valid comments found or API error"
        fi
        
        # 等待30秒后再次检查
        sleep 30
    done
    
    # 处理审核结果
    if [ "$approved" = "true" ]; then
        debug "success" "Build approved by admin"
        return 0
    elif [ "$rejected" = "true" ]; then
        debug "error" "Build rejected by admin"
        echo "BUILD_REJECTED=true" >> $GITHUB_ENV
        return 1
    else
        debug "error" "Build timed out during review"
        echo "BUILD_TIMEOUT=true" >> $GITHUB_ENV
        return 2
    fi
}

# 输出数据
output_data() {
    local current_data="$1"
    local build_rejected="$2"
    local build_timeout="$3"
    
    # 简单输出数据（重定向到stderr避免被当作变量赋值）
    debug "log" "Review.sh输出数据"
    
    # 输出到GitHub Actions输出变量（使用多行格式避免截断）
    echo "data<<EOF" >> $GITHUB_OUTPUT
    echo "$current_data" >> $GITHUB_OUTPUT
    echo "EOF" >> $GITHUB_OUTPUT
    
    # 根据标志设置构建批准状态    
    if [ "$build_rejected" = "true" ]; then
        echo "validation_passed=false" >> $GITHUB_OUTPUT
        # 检查是否是自动拒绝（通过环境变量判断）
        if [ "$BUILD_REJECTED" = "true" ]; then
            # 从环境变量中获取具体的拒绝原因
            local reject_reason="${REJECT_REASON:-Build was rejected due to validation issues}"
            echo "reject_reason=$reject_reason" >> $GITHUB_OUTPUT
            debug "error" "Build was rejected: $reject_reason"
        else
            echo "reject_reason=Build was rejected by admin" >> $GITHUB_OUTPUT
            debug "error" "Build was rejected by admin"
        fi
    elif [ "$build_timeout" = "true" ]; then
        echo "validation_passed=false" >> $GITHUB_OUTPUT
        echo "reject_reason=Build timed out during review" >> $GITHUB_OUTPUT
        debug "error" "Build timed out during review"
    else
        echo "validation_passed=true" >> $GITHUB_OUTPUT
        echo "reject_reason=" >> $GITHUB_OUTPUT
        debug "success" "Build was approved or no review needed"
    fi
    
    # 显示输出信息
    debug "log" "Review output: $current_data"
}

# 输出被拒绝构建的数据
output_rejected_data() {
    echo "data={}" >> $GITHUB_OUTPUT
    echo "validation_passed=false" >> $GITHUB_OUTPUT
    echo "reject_reason=Build was rejected - no data to pass forward" >> $GITHUB_OUTPUT
    debug "error" "Build was rejected - no data to pass forward"
}

# 主处理函数
process_review() {
    local trigger_output="$1"
    local actor="$2"
    local repo_owner="$3"

    debug "log" "原始输入: $trigger_output"
    
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
    
    # 从GitHub事件中检测触发类型
    local trigger_type=""
    if [ -n "$GITHUB_EVENT_NAME" ]; then
        # 将GitHub事件名称映射到我们的触发类型
        case "$GITHUB_EVENT_NAME" in
            "workflow_dispatch")
                trigger_type="workflow_dispatch"
                ;;
            "issues")
                trigger_type="issue"
                ;;
            *)
                trigger_type="$GITHUB_EVENT_NAME"
                ;;
        esac
    else
        # 在本地测试环境中，尝试从环境变量获取
        trigger_type="${TRIGGER_TYPE:-unknown}"
    fi
    
    debug "var" "Trigger type" "$trigger_type"
    
    # 并行检查所有参数
    local validation_result=$(validate_all_parameters "$RENDEZVOUS_SERVER" "$API_SERVER" "$EMAIL")
    local validation_exit_code=$?
    
    debug "log" "Validation result: '$validation_result'"
    debug "log" "Validation exit code: $validation_exit_code"
    
    # 如果有问题，处理拒绝逻辑
    if [ $validation_exit_code -eq 0 ] && [ "$validation_result" != "[]" ]; then
        # 设置拒绝标志
        export BUILD_REJECTED="true"
        
        # 解析问题列表
        local issues_array=$(echo "$validation_result" | jq -r '.[]' 2>/dev/null)
        local issues_count=$(echo "$validation_result" | jq 'length' 2>/dev/null)
        
        if [ -n "$issues_count" ] && [ "$issues_count" -gt 0 ] 2>/dev/null; then
            debug "log" "Found $issues_count validation issues"
        else
            debug "log" "Found validation issues (count: $issues_count)"
        fi
        
        # 如果是Issue触发，回复到原始Issue
        if [ "$trigger_type" = "issue" ]; then
            local original_issue_number=$(get_original_issue_number)
            if [ -n "$original_issue_number" ]; then
                # 生成包含所有问题的拒绝回复
                local current_time=$(date '+%Y-%m-%d %H:%M:%S')
                local reject_comment=$(generate_comprehensive_rejection_comment "$validation_result" "$current_time")
                add_issue_comment "$original_issue_number" "$reject_comment"
                debug "log" "Comprehensive rejection comment added to issue #$original_issue_number"
            fi
        fi
        
        # 生成拒绝原因（用于输出）
        local reject_reason=""
        if [ -n "$issues_count" ] && [ "$issues_count" -eq 1 ] 2>/dev/null; then
            reject_reason=$(echo "$validation_result" | jq -r '.[0]')
        else
            reject_reason="Multiple validation issues found ($issues_count issues)"
        fi
        
        # 设置拒绝原因到环境变量
        echo "REJECT_REASON=$reject_reason" >> $GITHUB_ENV
        
        output_data "$PARSED_INPUT" "true" "false"
        return 0  # 正常退出，不抛出错误
    else
        # 没有问题，设置标志为false
        export BUILD_REJECTED="false"
    fi
    
    # 确定是否需要审核    
    local need_review=$(determine_review_requirement "$trigger_type" "$RENDEZVOUS_SERVER" "$API_SERVER" "$actor" "$repo_owner")
    debug "log" "Need review: $need_review"
    
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
