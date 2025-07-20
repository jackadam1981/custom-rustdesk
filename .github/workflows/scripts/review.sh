#!/bin/bash
# 审核和验证脚本 - 伪面向对象模式
# 这个文件处理构建审核和参数验证逻辑，采用简单的伪面向对象设计

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# 审核管理器 - 伪面向对象实现
# 使用全局变量存储实例状态

# 私有属性（全局变量）
_REVIEW_MANAGER_TRIGGER_DATA=""
_REVIEW_MANAGER_ACTOR=""
_REVIEW_MANAGER_REPO_OWNER=""
_REVIEW_MANAGER_TRIGGER_TYPE=""
_REVIEW_MANAGER_RENDEZVOUS_SERVER=""
_REVIEW_MANAGER_API_SERVER=""
_REVIEW_MANAGER_EMAIL=""
_REVIEW_MANAGER_ORIGINAL_ISSUE_NUMBER=""

# 构造函数
review_manager_init() {
    local trigger_data="$1"
    local actor="$2"
    local repo_owner="$3"
    
    _REVIEW_MANAGER_TRIGGER_DATA="$trigger_data"
    _REVIEW_MANAGER_ACTOR="$actor"
    _REVIEW_MANAGER_REPO_OWNER="$repo_owner"
    
    # 检测触发类型
    _REVIEW_MANAGER_TRIGGER_TYPE=$(review_manager_detect_trigger_type)
    
    # 提取服务器参数
    review_manager_extract_parameters
    
    debug "log" "Initializing review manager"
    debug "var" "Trigger type" "$_REVIEW_MANAGER_TRIGGER_TYPE"
    debug "var" "Actor" "$_REVIEW_MANAGER_ACTOR"
    debug "var" "Repo owner" "$_REVIEW_MANAGER_REPO_OWNER"
}

# 私有方法：检测触发类型
review_manager_detect_trigger_type() {
    if [ -n "$GITHUB_EVENT_NAME" ]; then
        case "$GITHUB_EVENT_NAME" in
            "workflow_dispatch")
                echo "workflow_dispatch"
                ;;
            "issues")
                echo "issue"
                ;;
            *)
                echo "$GITHUB_EVENT_NAME"
                ;;
        esac
    else
        echo "${TRIGGER_TYPE:-unknown}"
    fi
}

# 私有方法：提取参数
review_manager_extract_parameters() {
    debug "log" "Extracting parameters from trigger data"
    
    _REVIEW_MANAGER_RENDEZVOUS_SERVER=$(echo "$_REVIEW_MANAGER_TRIGGER_DATA" | jq -r '.rendezvous_server // empty')
    _REVIEW_MANAGER_API_SERVER=$(echo "$_REVIEW_MANAGER_TRIGGER_DATA" | jq -r '.api_server // empty')
    _REVIEW_MANAGER_EMAIL=$(echo "$_REVIEW_MANAGER_TRIGGER_DATA" | jq -r '.email // empty')
    
    debug "var" "Rendezvous server" "$_REVIEW_MANAGER_RENDEZVOUS_SERVER"
    debug "var" "API server" "$_REVIEW_MANAGER_API_SERVER"
    debug "var" "Email" "$_REVIEW_MANAGER_EMAIL"
}

# 私有方法：检查是否为私有IP地址
review_manager_check_private_ip() {
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

# 私有方法：获取原始issue编号
review_manager_get_original_issue_number() {
    if [ "$GITHUB_EVENT_NAME" = "issues" ] && [ -n "$GITHUB_EVENT_PATH" ]; then
        jq -r '.issue.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null
    else
        curl -s \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs" | \
            jq -r '.jobs[0].steps[] | select(.name == "Setup framework") | .outputs.build_id // empty'
    fi
}

# 公共方法：并行验证所有参数
review_manager_validate_parameters() {
    debug "log" "Starting parallel parameter validation"
    
    local issues=()
    local has_issues=false
    
    # 检查关键服务器参数是否为空
    if [ -z "$_REVIEW_MANAGER_RENDEZVOUS_SERVER" ]; then
        issues+=("Rendezvous server is missing")
        has_issues=true
    fi
    
    if [ -z "$_REVIEW_MANAGER_API_SERVER" ]; then
        issues+=("API server is missing")
        has_issues=true
    fi
    
    # 检查邮箱格式
    if [ -n "$_REVIEW_MANAGER_EMAIL" ] && [[ ! "$_REVIEW_MANAGER_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        issues+=("Invalid email format: $_REVIEW_MANAGER_EMAIL")
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
review_manager_need_review() {
    debug "var" "Trigger type" "$_REVIEW_MANAGER_TRIGGER_TYPE"
    debug "var" "Rendezvous server" "$_REVIEW_MANAGER_RENDEZVOUS_SERVER"
    debug "var" "API server" "$_REVIEW_MANAGER_API_SERVER"
    debug "var" "Actor" "$_REVIEW_MANAGER_ACTOR"
    debug "var" "Repo owner" "$_REVIEW_MANAGER_REPO_OWNER"
    
    # 手动触发：无需审核
    if [ "$_REVIEW_MANAGER_TRIGGER_TYPE" = "workflow_dispatch" ]; then
        debug "log" "Manual trigger - no review needed"
        echo "false"
        return 0
    fi
    
    # Issue触发：需要审核
    if [ "$_REVIEW_MANAGER_TRIGGER_TYPE" = "issue" ]; then
        # 如果是仓库所有者，不需要审核
        if [ "$_REVIEW_MANAGER_ACTOR" = "$_REVIEW_MANAGER_REPO_OWNER" ]; then
            debug "log" "Issue trigger by repo owner - no review needed"
            echo "false"
            return 0
        fi
        
        # 检查是否为公网IP或域名（需要审核）
        if [ -n "$_REVIEW_MANAGER_RENDEZVOUS_SERVER" ] && ! review_manager_check_private_ip "$_REVIEW_MANAGER_RENDEZVOUS_SERVER"; then
            debug "log" "Rendezvous server is public IP/domain - review needed"
            echo "true"
            return 0
        fi
        
        if [ -n "$_REVIEW_MANAGER_API_SERVER" ] && ! review_manager_check_private_ip "$_REVIEW_MANAGER_API_SERVER"; then
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
review_manager_handle_review() {
    debug "log" "Review required. Starting review process..."
    
    # 获取原始issue编号
    _REVIEW_MANAGER_ORIGINAL_ISSUE_NUMBER=$(review_manager_get_original_issue_number)
    
    # 在issue中添加审核状态
    local review_comment=$(generate_review_comment "$_REVIEW_MANAGER_RENDEZVOUS_SERVER" "$_REVIEW_MANAGER_API_SERVER")
    
    if [ -n "$_REVIEW_MANAGER_ORIGINAL_ISSUE_NUMBER" ]; then
        add_issue_comment "$_REVIEW_MANAGER_ORIGINAL_ISSUE_NUMBER" "$review_comment"
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
            "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$_REVIEW_MANAGER_ORIGINAL_ISSUE_NUMBER/comments")
        
        # 检查是否有管理员回复        
        if echo "$comments" | jq -e --arg owner "$_REVIEW_MANAGER_REPO_OWNER" '.[] | select(.user.login == $owner or .user.login == "admin" or .user.login == "管理员用户名") | select(.body | contains("同意构建"))' > /dev/null 2>&1; then
            approved=true
            break
        fi
        
        if echo "$comments" | jq -e --arg owner "$_REVIEW_MANAGER_REPO_OWNER" '.[] | select(.user.login == $owner or .user.login == "admin" or .user.login == "管理员用户名") | select(.body | contains("拒绝构建"))' > /dev/null 2>&1; then
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
review_manager_handle_rejection() {
    local validation_result="$1"
    
    debug "log" "Handling build rejection"
    
    # 如果是Issue触发，回复到原始Issue
    if [ "$_REVIEW_MANAGER_TRIGGER_TYPE" = "issue" ]; then
        _REVIEW_MANAGER_ORIGINAL_ISSUE_NUMBER=$(review_manager_get_original_issue_number)
        if [ -n "$_REVIEW_MANAGER_ORIGINAL_ISSUE_NUMBER" ]; then
            # 生成包含所有问题的拒绝回复
            local current_time=$(date '+%Y-%m-%d %H:%M:%S')
            local reject_comment=$(generate_comprehensive_rejection_comment "$validation_result" "$current_time")
            add_issue_comment "$_REVIEW_MANAGER_ORIGINAL_ISSUE_NUMBER" "$reject_comment"
            debug "log" "Comprehensive rejection comment added to issue #$_REVIEW_MANAGER_ORIGINAL_ISSUE_NUMBER"
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
review_manager_output_data() {
    local build_rejected="$1"
    local build_timeout="$2"
    
    debug "log" "Outputting review data"
    
    # 输出到GitHub Actions输出变量
    echo "data<<EOF" >> $GITHUB_OUTPUT
    echo "$_REVIEW_MANAGER_TRIGGER_DATA" >> $GITHUB_OUTPUT
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
    
    debug "log" "Review output: $_REVIEW_MANAGER_TRIGGER_DATA"
}

# 公共方法：输出被拒绝构建的数据
review_manager_output_rejected_data() {
    echo "data={}" >> $GITHUB_OUTPUT
    echo "validation_passed=false" >> $GITHUB_OUTPUT
    echo "reject_reason=Build was rejected - no data to pass forward" >> $GITHUB_OUTPUT
    debug "error" "Build was rejected - no data to pass forward"
}

# 公共方法：获取触发数据
review_manager_get_trigger_data() {
    echo "$_REVIEW_MANAGER_TRIGGER_DATA"
}

# 公共方法：获取服务器参数
review_manager_get_server_params() {
    echo "RENDEZVOUS_SERVER=$_REVIEW_MANAGER_RENDEZVOUS_SERVER"
    echo "API_SERVER=$_REVIEW_MANAGER_API_SERVER"
    echo "EMAIL=$_REVIEW_MANAGER_EMAIL"
}

# 主审核管理函数 - 供工作流调用
review_manager() {
    local operation="$1"
    local trigger_data="$2"
    local actor="$3"
    local repo_owner="$4"
    
    # 初始化审核管理器
    review_manager_init "$trigger_data" "$actor" "$repo_owner"
    
    case "$operation" in
        "validate")
            review_manager_validate_parameters
            ;;
        "need-review")
            review_manager_need_review
            ;;
        "handle-review")
            review_manager_handle_review
            ;;
        "handle-rejection")
            local validation_result="$5"
            review_manager_handle_rejection "$validation_result"
            ;;
        "output-data")
            local build_rejected="$5"
            local build_timeout="$6"
            review_manager_output_data "$build_rejected" "$build_timeout"
            ;;
        "output-rejected")
            review_manager_output_rejected_data
            ;;
        "get-trigger-data")
            review_manager_get_trigger_data
            ;;
        "get-server-params")
            review_manager_get_server_params
            ;;
        "process")
            # 完整的审核处理流程
            review_manager_process_review
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
}

# 完整的审核处理流程
review_manager_process_review() {
    debug "log" "Starting complete review process"
    
    # 设置审核数据
    echo "TRIGGER_OUTPUT=$_REVIEW_MANAGER_TRIGGER_DATA" >> $GITHUB_ENV
    echo "BUILD_REJECTED=false" >> $GITHUB_ENV
    echo "BUILD_TIMEOUT=false" >> $GITHUB_ENV
    
    # 并行检查所有参数
    local validation_result=$(review_manager_validate_parameters)
    local validation_exit_code=$?
    
    debug "log" "Validation result: '$validation_result'"
    debug "log" "Validation exit code: $validation_exit_code"
    
    # 如果有问题，处理拒绝逻辑
    if [ $validation_exit_code -eq 0 ] && [ "$validation_result" != "[]" ]; then
        export BUILD_REJECTED="true"
        review_manager_handle_rejection "$validation_result"
        review_manager_output_data "true" "false"
        return 0
    else
        export BUILD_REJECTED="false"
    fi
    
    # 确定是否需要审核    
    local need_review=$(review_manager_need_review)
    debug "log" "Need review: $need_review"
    
    # 如果需要审核，处理审核流程
    if [ "$need_review" = "true" ]; then
        review_manager_handle_review
        local review_result=$?
        
        if [ $review_result -eq 1 ]; then
            # 被拒绝
            return 1
        elif [ $review_result -eq 2 ]; then
            # 超时
            echo "BUILD_TIMEOUT=true" >> $GITHUB_ENV
            review_manager_output_rejected_data
            return 1
        fi
    fi
    
    # 输出数据
    review_manager_output_data "$BUILD_REJECTED" "$BUILD_TIMEOUT"
}

# 兼容性函数 - 保持向后兼容
process_review() {
    local trigger_output="$1"
    local actor="$2"
    local repo_owner="$3"
    
    debug "log" "Calling review_manager process with legacy function"
    review_manager "process" "$trigger_output" "$actor" "$repo_owner"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 3 ]; then
        echo "Usage: $0 <operation> <trigger_data> <actor> [repo_owner] [additional_params...]"
        echo "Operations: validate, need-review, handle-review, handle-rejection, output-data, output-rejected, get-trigger-data, get-server-params, process"
        exit 1
    fi
    
    operation="$1"
    trigger_data="$2"
    actor="$3"
    repo_owner="${4:-}"
    
    review_manager "$operation" "$trigger_data" "$actor" "$repo_owner"
fi
