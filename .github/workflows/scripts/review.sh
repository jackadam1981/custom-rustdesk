#!/bin/bash
# 审核和验证脚本 - 伪面向对象模式
# 这个文件处理构建审核和参数验证逻辑，采用简单的伪面向对象设计

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# 私有方法：验证服务器地址格式
validate_server_address() {
    local server_address="$1"
    local server_name="$2"
    
    # 去除协议前缀、端口和路径
    local clean_address="$server_address"
    clean_address="${clean_address#*://}"
    clean_address="${clean_address%%:*}"
    clean_address="${clean_address%%/*}"
    
    # 检查是否为空
    if [ -z "$clean_address" ]; then
        echo "$server_name 地址不能为空"
        return 1
    fi
    
    # 检查是否为有效IP地址
    if [[ "$clean_address" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # 验证IP地址段是否在有效范围内
        IFS='.' read -ra ADDR <<< "$clean_address"
        for segment in "${ADDR[@]}"; do
            if [ "$segment" -lt 0 ] || [ "$segment" -gt 255 ]; then
                echo "$server_name 地址格式错误: $server_address (IP地址段超出范围0-255)"
                return 1
            fi
        done
        # IP地址格式正确
        return 0
    fi
    
    # 检查是否为有效域名
    local fqdn_regex='^([a-zA-Z0-9][-a-zA-Z0-9]{0,62}\.)+[a-zA-Z]{2,63}$'
    if [[ "$clean_address" =~ $fqdn_regex ]]; then
        # 域名格式正确
        return 0
    fi
    
    # 既不是有效IP也不是有效域名
    echo "$server_name 地址格式错误: $server_address (请提供有效的IP地址或完整域名)"
    return 1
}

# 私有方法：检查是否为私有IP地址
check_private_ip() {
    local ip="$1"
    
    # 去除协议前缀、端口和路径
    local clean_ip="$ip"
    clean_ip="${clean_ip#*://}"
    clean_ip="${clean_ip%%:*}"
    clean_ip="${clean_ip%%/*}"
    
    # 检查是否为IP地址格式
    if [[ "$clean_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # 检查是否为私有IP地址
        if [[ "$clean_ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|169\.254\.) ]]; then
            return 0  # 是私有IP
        else
            return 1  # 是公网IP
        fi
    fi
    
    return 1  # 不是IP地址（是域名）
}

# 私有方法：检查是否为有效的IP地址
is_valid_ip() {
    local ip="$1"
    
    # 去除协议前缀、端口和路径
    local clean_ip="$ip"
    clean_ip="${clean_ip#*://}"
    clean_ip="${clean_ip%%:*}"
    clean_ip="${clean_ip%%/*}"
    
    # 检查是否为IP地址格式
    if [[ "$clean_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # 检查每个段是否在有效范围内
        IFS='.' read -ra ADDR <<< "$clean_ip"
        for segment in "${ADDR[@]}"; do
            if [ "$segment" -lt 0 ] || [ "$segment" -gt 255 ]; then
        return 1
            fi
        done
        return 0  # 是有效IP
    fi
    
    return 1  # 不是IP地址
}

# 私有方法：统一验证服务器地址（格式验证 + 公网检查）
validate_server_address_with_review() {
    local server_address="$1"
    local server_name="$2"
    
    local issues=()
    local needs_review=false
    
    # 1. 格式验证
    if [ -n "$server_address" ]; then
        if ! validate_server_address "$server_address" "$server_name" > /dev/null 2>&1; then
            issues+=("$server_name 地址格式错误: $server_address (请提供有效的IP地址或完整域名)")
        else
            # 2. 公网检查（仅在格式验证通过后进行）
            if ! check_private_ip "$server_address"; then
                needs_review=true
            fi
        fi
    else
        issues+=("$server_name 地址不能为空")
    fi
    
    # 返回结果：issues数组和是否需要审核
    echo "${issues[*]}|$needs_review"
}

# 公共方法：并行验证所有参数
validate_parameters() {
    local event_data="$1"
    local trigger_data="$2"
    
    # 从trigger_data中提取需要的参数
    local rendezvous_server=$(echo "$trigger_data" | jq -r '.rendezvous_server // empty')
    local api_server=$(echo "$trigger_data" | jq -r '.api_server // empty')
    local email=$(echo "$trigger_data" | jq -r '.email // empty')
    
    # 调试：输出提取的参数
    debug "var" "Extracted rendezvous_server" "$rendezvous_server"
    debug "var" "Extracted api_server" "$api_server"
    debug "var" "Extracted email" "$email"
    
    local issues=()
    local has_issues=false
    local needs_review=false
    
    # 并行验证所有参数（不提前退出，收集所有错误）
    
    # 1. 检查邮箱格式
    if [ -n "$email" ] && [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        issues+=("邮件地址格式错误: $email (请提供有效的邮件地址)")
        has_issues=true
        debug "log" "Email validation failed: $email"
    else
        debug "log" "Email validation passed: $email"
    fi
    
    # 2. 统一验证Rendezvous server地址（格式 + 公网检查）
    local rendezvous_result=$(validate_server_address_with_review "$rendezvous_server" "Rendezvous server")
    local rendezvous_issues=$(echo "$rendezvous_result" | cut -d'|' -f1)
    local rendezvous_needs_review=$(echo "$rendezvous_result" | cut -d'|' -f2)
    
    if [ -n "$rendezvous_issues" ]; then
        issues+=("$rendezvous_issues")
        has_issues=true
        debug "log" "Rendezvous server validation failed: $rendezvous_server"
    else
        debug "log" "Rendezvous server validation passed: $rendezvous_server"
        if [ "$rendezvous_needs_review" = "true" ]; then
            needs_review=true
            debug "log" "Rendezvous server needs review (public IP/domain): $rendezvous_server"
        fi
    fi
    
    # 3. 统一验证API server地址（格式 + 公网检查）
    local api_result=$(validate_server_address_with_review "$api_server" "API server")
    local api_issues=$(echo "$api_result" | cut -d'|' -f1)
    local api_needs_review=$(echo "$api_result" | cut -d'|' -f2)
    
    if [ -n "$api_issues" ]; then
        issues+=("$api_issues")
        has_issues=true
        debug "log" "API server validation failed: $api_server"
    else
        debug "log" "API server validation passed: $api_server"
        if [ "$api_needs_review" = "true" ]; then
            needs_review=true
            debug "log" "API server needs review (public IP/domain): $api_server"
        fi
    fi

    # 返回结果
    if [ "$has_issues" = "true" ]; then
        local issues_json
        if ! issues_json=$(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .); then
            debug "error" "参数校验结果生成JSON失败，内容: ${issues[*]}"
            exit 2
        fi
        debug "log" "Validation failed with issues: $issues_json"
        echo "$issues_json"
        return 1
    else
        debug "log" "All validations passed"
        # 输出是否需要审核的信息
        if [ "$needs_review" = "true" ]; then
            debug "log" "Validation passed but needs review"
        fi
        echo "[]"
        return 0
    fi
}

# 公共方法：确定是否需要审核
need_review() {
    local event_data="$1"
    local trigger_data="$2"
    
    # 从event_data中提取actor和repo_owner
    local actor=$(echo "$event_data" | jq -r '.sender.login // empty' || echo "")
    local repo_owner=$(echo "$event_data" | jq -r '.repository.owner.login // empty' || echo "")
    
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
    
    # 手动触发：无需审核
    if [ "$trigger_type" = "workflow_dispatch" ]; then
        echo "false"
        return 0
    fi
    
    # Issue触发：需要审核
    if [ "$trigger_type" = "issue" ]; then
        # 如果是仓库所有者，不需要审核
        if [ "$actor" = "$repo_owner" ]; then
            echo "false"
            return 0
        fi
        
        # 直接检查服务器地址是否为公网地址
        local rendezvous_server=$(echo "$trigger_data" | jq -r '.rendezvous_server // empty' || echo "")
        local api_server=$(echo "$trigger_data" | jq -r '.api_server // empty' || echo "")
        
        # 检查是否需要审核
        local needs_review=false
        
        # 检查rendezvous_server
        if [ -n "$rendezvous_server" ]; then
            if ! check_private_ip "$rendezvous_server"; then
                needs_review=true
                debug "log" "Rendezvous server needs review (public): $rendezvous_server"
            fi
        fi
        
        # 检查api_server
        if [ -n "$api_server" ]; then
            if ! check_private_ip "$api_server"; then
                needs_review=true
                debug "log" "API server needs review (public): $api_server"
            fi
        fi
        
        if [ "$needs_review" = "true" ]; then
            echo "true"
            return 0
        fi
        
        # 私有IP无需审核
        echo "false"
        return 0
    fi
    
    echo "false"
}

# 公共方法：处理审核流程
handle_review() {
    local event_data="$1"
    local trigger_data="$2"
    
    # 从trigger_data中提取需要的参数
    local rendezvous_server=$(echo "$trigger_data" | jq -r '.rendezvous_server // empty' || echo "")
    local api_server=$(echo "$trigger_data" | jq -r '.api_server // empty' || echo "")
    
    # 从event_data中提取actor和repo_owner
    local actor=$(echo "$event_data" | jq -r '.sender.login // empty' || echo "")
    local repo_owner=$(echo "$event_data" | jq -r '.repository.owner.login // empty' || echo "")
    
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
        original_issue_number=$(jq -r '.issue.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
    else
        original_issue_number=$(echo "$event_data" | jq -r '.issue.number // empty' || echo "")
    fi
    
    # 生成审核评论
    local review_comment=$(generate_review_comment "$rendezvous_server" "$api_server")
    
    # 如果是Issue触发，添加到原始Issue
    if [ -n "$original_issue_number" ]; then
        add_issue_comment "$original_issue_number" "$review_comment"
    fi
    
    # 循环检查审核回复
    local start_time=$(date +%s)
    local timeout=21600  # 6小时超时
    local approved=false
    local rejected=false
    
    while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
        # 获取issue的最新评论
        local comments=$(curl -s \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$original_issue_number/comments")
        
        # 保证comments一定是数组
        if echo "$comments" | jq -e 'type == "object"' > /dev/null 2>&1; then
            comments="[$comments]"
        fi
        
        # 检查是否有管理员回复        
        if echo "$comments" | jq -e --arg owner "$repo_owner" '.[] | select(.user.login == $owner or .user.login == "admin" or .user.login == "管理员用户名") | select(.body | contains("同意构建"))' > /dev/null 2>&1; then
            approved=true
            break
        fi
        
        if echo "$comments" | jq -e --arg owner "$repo_owner" '.[] | select(.user.login == $owner or .user.login == "admin" or .user.login == "管理员用户名") | select(.body | contains("拒绝构建"))' > /dev/null 2>&1; then
            rejected=true
            break
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

    # 从event_data中提取actor和repo_owner
    local actor=$(echo "$event_data" | jq -r '.sender.login // empty' || echo "")
    local repo_owner=$(echo "$event_data" | jq -r '.repository.owner.login // empty' || echo "")

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
            original_issue_number=$(jq -r '.issue.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
        else
            original_issue_number=$(echo "$event_data" | jq -r '.issue.number // empty' || echo "")
        fi

        if [ -n "$original_issue_number" ]; then
            # 生成包含所有问题的拒绝回复
            local reject_comment="❌ 参数校验失败，原因如下："
            
            # 尝试解析validation_result为JSON数组
            if echo "$validation_result" | jq -e 'type == "array"' > /dev/null 2>&1; then
                # 是JSON数组，遍历每个错误
                local issues_count=$(echo "$validation_result" | jq 'length' 2>/dev/null || echo "0")
                if [ "$issues_count" -gt 0 ] 2>/dev/null; then
                    for ((i=0; i<issues_count; i++)); do
                        local reason=$(echo "$validation_result" | jq -r ".[$i]" 2>/dev/null || echo "未知错误")
                        reject_comment+=$'\n'"- $reason"
                    done
                else
                    reject_comment+=$'\n'"- 未知参数校验错误"
                fi
            else
                # 不是JSON数组，直接使用validation_result作为错误信息
                reject_comment+=$'\n'"- $validation_result"
            fi
            
            add_issue_comment "$original_issue_number" "$reject_comment" || true
        fi
    fi

    # 生成拒绝原因
    local reject_reason=""
    if echo "$validation_result" | jq -e 'type == "array"' > /dev/null 2>&1; then
        # 是JSON数组
        local issues_count=$(echo "$validation_result" | jq 'length' 2>/dev/null || echo "0")
        if [ "$issues_count" -eq 1 ] 2>/dev/null; then
            reject_reason=$(echo "$validation_result" | jq -r '.[0]' 2>/dev/null || echo "参数格式错误")
        elif [ "$issues_count" -gt 1 ] 2>/dev/null; then
            reject_reason="发现 $issues_count 个参数校验问题"
        else
            reject_reason="未知参数校验错误"
        fi
    else
        # 不是JSON数组，使用简化的错误信息
        reject_reason="参数校验失败"
    fi

    # 设置拒绝原因到环境变量
    if [ -n "$GITHUB_ENV" ] && [ -w "$GITHUB_ENV" ]; then
        echo "REJECT_REASON=$reject_reason" >> $GITHUB_ENV
    fi

    debug "error" "Build rejected: $reject_reason"
}

# 公共方法：输出数据
output_data() {
    local event_data="$1"
    local trigger_data="$2"
    local build_rejected="$3"
    local build_timeout="$4"
    
    # 生成包含所有必要信息的JSON
    local output_data=$(jq -c -n \
        --argjson trigger_data "$trigger_data" \
        --arg build_rejected "$build_rejected" \
        --arg build_timeout "$build_timeout" \
        --arg validation_passed "$([ "$build_rejected" = "true" ] && echo "false" || echo "true")" \
        --arg reject_reason "$([ "$build_rejected" = "true" ] && echo "Build rejected" || echo "")" \
        '{trigger_data: $trigger_data, build_rejected: $build_rejected, build_timeout: $build_timeout, validation_passed: $validation_passed, reject_reason: $reject_reason}' || echo "{}")
    
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
    local rendezvous_server=$(echo "$trigger_data" | jq -r '.rendezvous_server // empty' || echo "")
    local api_server=$(echo "$trigger_data" | jq -r '.api_server // empty' || echo "")
    local email=$(echo "$trigger_data" | jq -r '.email // empty' || echo "")
    
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
            validate_parameters "$arg2" "$arg1"
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
