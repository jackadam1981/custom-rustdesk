#!/bin/bash
# 审核和验证脚本 - 伪面向对象模式
# 这个文件处理构建审核和参数验证逻辑，采用简单的伪面向对象设计

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# 私有方法：检查是否为私有IP地址
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

# 公共方法：并行验证所有参数
validate_parameters() {
    local event_data="$1"
    local trigger_data="$2"
    
    debug "log" "Starting parallel parameter validation"
    
    # 从trigger_data中提取需要的参数
    local rendezvous_server=$(echo "$trigger_data" | jq -r '.rendezvous_server // empty')
    local api_server=$(echo "$trigger_data" | jq -r '.api_server // empty')
    local email=$(echo "$trigger_data" | jq -r '.email // empty')
    
    debug "var" "Rendezvous server" "$rendezvous_server"
    debug "var" "API server" "$api_server"
    debug "var" "Email" "$email"
    
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
    
    # 返回结果
    if [ "$has_issues" = "true" ]; then
        local issues_json=$(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .)
        echo "$issues_json"
        return 0  # 返回0表示有问题
    else
        echo "[]"
        return 1  # 返回1表示没有问题
    fi
}

# 公共方法：确定是否需要审核
need_review() {
    local event_data="$1"
    local trigger_data="$2"
    
    # 从trigger_data中提取需要的参数
    local rendezvous_server=$(echo "$trigger_data" | jq -r '.rendezvous_server // empty')
    local api_server=$(echo "$trigger_data" | jq -r '.api_server // empty')
    
    # 从event_data中提取actor和repo_owner
    local actor=$(echo "$event_data" | jq -r '.sender.login // empty')
    local repo_owner=$(echo "$event_data" | jq -r '.repository.owner.login // empty')
    
    # 检测触发类型
    local trigger_type=""
    if [ -n "$GITHUB_EVENT_NAME" ]; then
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
        trigger_type="${TRIGGER_TYPE:-unknown}"
    fi
    
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

# 公共方法：处理审核流程
handle_review() {
    local event_data="$1"
    local trigger_data="$2"
    
    debug "log" "Review required. Starting review process..."
    
    # 从trigger_data中提取需要的参数
    local rendezvous_server=$(echo "$trigger_data" | jq -r '.rendezvous_server // empty')
    local api_server=$(echo "$trigger_data" | jq -r '.api_server // empty')
    
    # 从event_data中提取actor和repo_owner
    local actor=$(echo "$event_data" | jq -r '.sender.login // empty')
    local repo_owner=$(echo "$event_data" | jq -r '.repository.owner.login // empty')
    
    # 检测触发类型
    local trigger_type=""
    if [ -n "$GITHUB_EVENT_NAME" ]; then
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
        trigger_type="${TRIGGER_TYPE:-unknown}"
    fi
    
    # 获取原始issue编号
    local original_issue_number=""
    if [ "$trigger_type" = "issues" ] && [ -n "$GITHUB_EVENT_PATH" ]; then
        original_issue_number=$(jq -r '.issue.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null)
    else
        original_issue_number=$(curl -s \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs" | \
            jq -r '.jobs[0].steps[] | select(.name == "Setup framework") | .outputs.build_id // empty')
    fi
    
    # 生成审核评论
    local review_comment=$(generate_review_comment "$rendezvous_server" "$api_server")
    
    # 如果是Issue触发，添加到原始Issue
    if [ -n "$original_issue_number" ]; then
        add_issue_comment "$original_issue_number" "$review_comment"
        debug "log" "Review comment added to issue #$original_issue_number"
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
        return 1
    else
        debug "error" "Build timed out during review"
        return 2
    fi
}

# 公共方法：处理拒绝逻辑
handle_rejection() {
    local event_data="$1"
    local trigger_data="$2"
    local validation_result="$3"
    
    debug "log" "Handling build rejection"
    
    # 从event_data中提取actor和repo_owner
    local actor=$(echo "$event_data" | jq -r '.sender.login // empty')
    local repo_owner=$(echo "$event_data" | jq -r '.repository.owner.login // empty')
    
    # 检测触发类型
    local trigger_type=""
    if [ -n "$GITHUB_EVENT_NAME" ]; then
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
        trigger_type="${TRIGGER_TYPE:-unknown}"
    fi
    
    # 如果是Issue触发，回复到原始Issue
    if [ "$trigger_type" = "issue" ]; then
        local original_issue_number=""
        if [ -n "$GITHUB_EVENT_PATH" ]; then
            original_issue_number=$(jq -r '.issue.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null)
        else
            original_issue_number=$(curl -s \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs" | \
                jq -r '.jobs[0].steps[] | select(.name == "Setup framework") | .outputs.build_id // empty')
        fi
        
        if [ -n "$original_issue_number" ]; then
            # 生成包含所有问题的拒绝回复
            local current_time=$(date '+%Y-%m-%d %H:%M:%S')
            local reject_comment=$(generate_comprehensive_rejection_comment "$validation_result" "$current_time")
            add_issue_comment "$original_issue_number" "$reject_comment"
            debug "log" "Comprehensive rejection comment added to issue #$original_issue_number"
        fi
    fi
    
    # 生成拒绝原因
    local issues_count=$(echo "$validation_result" | jq 'length' 2>/dev/null)
    local reject_reason=""
    
    if [ -n "$issues_count" ] && [ "$issues_count" -eq 1 ] 2>/dev/null; then
        reject_reason=$(echo "$validation_result" | jq -r '.[0]')
    else
        reject_reason="Multiple validation issues found ($issues_count issues)"
    fi
    
    # 设置拒绝原因到环境变量
    echo "REJECT_REASON=$reject_reason" >> $GITHUB_ENV
    
    debug "error" "Build rejected: $reject_reason"
}

# 公共方法：输出数据
output_data() {
    local event_data="$1"
    local trigger_data="$2"
    local build_rejected="$3"
    local build_timeout="$4"
    
    debug "log" "Outputting review data"
    
    # 生成包含所有必要信息的JSON
    local output_data=$(jq -c -n \
        --argjson trigger_data "$trigger_data" \
        --arg build_rejected "$build_rejected" \
        --arg build_timeout "$build_timeout" \
        --arg validation_passed "$([ "$build_rejected" = "true" ] && echo "false" || echo "true")" \
        --arg reject_reason "$([ "$build_rejected" = "true" ] && echo "Build rejected" || echo "")" \
        '{trigger_data: $trigger_data, build_rejected: $build_rejected, build_timeout: $build_timeout, validation_passed: $validation_passed, reject_reason: $reject_reason}')
    
    # 输出到GitHub Actions输出变量
    echo "data<<EOF" >> $GITHUB_OUTPUT
    echo "$trigger_data" >> $GITHUB_OUTPUT
    echo "EOF" >> $GITHUB_OUTPUT
    
    # 根据标志设置构建批准状态    
    if [ "$build_rejected" = "true" ]; then
        echo "validation_passed=false" >> $GITHUB_OUTPUT
        if [ "$BUILD_REJECTED" = "true" ]; then
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
    
    debug "log" "Review output: $trigger_data"
}

# 公共方法：输出被拒绝构建的数据
output_rejected_data() {
    local trigger_data="$1"
    echo "data={}" >> $GITHUB_OUTPUT
    echo "validation_passed=false" >> $GITHUB_OUTPUT
    echo "reject_reason=Build was rejected - no data to pass forward" >> $GITHUB_OUTPUT
    debug "error" "Build was rejected - no data to pass forward"
}

# 公共方法：获取触发数据
get_trigger_data() {
    local trigger_data="$1"
    echo "$trigger_data"
}

# 公共方法：获取服务器参数
get_server_params() {
    local trigger_data="$1"
    
    # 从trigger_data中提取服务器参数
    local rendezvous_server=$(echo "$trigger_data" | jq -r '.rendezvous_server // empty')
    local api_server=$(echo "$trigger_data" | jq -r '.api_server // empty')
    local email=$(echo "$trigger_data" | jq -r '.email // empty')
    
    echo "RENDEZVOUS_SERVER=$rendezvous_server"
    echo "API_SERVER=$api_server"
    echo "EMAIL=$email"
}

# 主审核管理函数 - 供工作流调用
# 参数说明：
#   arg1: operation - 操作类型 (validate|need-review|handle-review|handle-rejection|output-data|output-rejected|get-trigger-data|get-server-params)
#   arg2: trigger_data - 触发数据JSON字符串 (仅在需要时使用)
#   arg3: event_data - GitHub事件数据JSON字符串 (仅在需要时使用)
#   arg4: 额外参数 - 根据操作类型不同而不同 (仅在需要时使用)
#   arg5: 额外参数 - 根据操作类型不同而不同 (仅在需要时使用)
#   arg6: 额外参数 - 根据操作类型不同而不同 (仅在需要时使用)
review_manager() {
    local operation="$1"
    local arg1="$2"
    local arg2="$3"
    local arg3="$4"
    local arg4="$5"
    local arg5="$6"
    
    case "$operation" in
        "validate")
            validate_parameters "$arg1" "$arg2"
            ;;
        "need-review")
            need_review "$arg1" "$arg2"
            ;;
        "handle-review")
            handle_review "$arg1" "$arg2"
            ;;
        "handle-rejection")
            handle_rejection "$arg1" "$arg2" "$arg3"
            ;;
        "output-data")
            output_data "$arg1" "$arg2" "$arg3" "$arg4"
            ;;
        "output-rejected")
            output_rejected_data "$arg1"
            ;;
        "get-trigger-data")
            get_trigger_data "$arg1"
            ;;
        "get-server-params")
            get_server_params "$arg1"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
