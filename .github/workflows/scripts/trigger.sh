#!/bin/bash
# 触发器和参数提取脚本 - 伪面向对象模式
# 这个文件处理事件触发和参数提取逻辑，采用简单的伪面向对象设计

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# Trigger 管理器 - 伪面向对象实现
# 使用全局变量存储实例状态

# 私有属性（全局变量）
_TRIGGER_MANAGER_EVENT_NAME=""
_TRIGGER_MANAGER_EVENT_DATA=""
_TRIGGER_MANAGER_BUILD_ID=""
_TRIGGER_MANAGER_TRIGGER_TYPE=""
_TRIGGER_MANAGER_EXTRACTED_PARAMS=""
_TRIGGER_MANAGER_FINAL_DATA=""

# 构造函数
trigger_manager_init() {
    local event_name="${1:-}"
    local event_data="${2:-}"
    local build_id="${3:-}"
    
    _TRIGGER_MANAGER_EVENT_NAME="$event_name"
    _TRIGGER_MANAGER_EVENT_DATA="$event_data"
    _TRIGGER_MANAGER_BUILD_ID="$build_id"
    
    debug "log" "Initializing trigger manager"
    debug "var" "Event name" "$_TRIGGER_MANAGER_EVENT_NAME"
    debug "var" "Build ID" "$_TRIGGER_MANAGER_BUILD_ID"
    
    # 如果参数为空，尝试从环境变量获取
    if [ -z "$_TRIGGER_MANAGER_EVENT_NAME" ]; then
        _TRIGGER_MANAGER_EVENT_NAME="$EVENT_NAME"
        debug "log" "Using EVENT_NAME from environment: $_TRIGGER_MANAGER_EVENT_NAME"
    fi
    if [ -z "$_TRIGGER_MANAGER_EVENT_DATA" ]; then
        _TRIGGER_MANAGER_EVENT_DATA="$EVENT_DATA"
        debug "log" "Using EVENT_DATA from environment"
    fi
    if [ -z "$_TRIGGER_MANAGER_BUILD_ID" ]; then
        _TRIGGER_MANAGER_BUILD_ID="$BUILD_ID"
        debug "log" "Using BUILD_ID from environment: $_TRIGGER_MANAGER_BUILD_ID"
    fi
}

# 私有方法：从 workflow_dispatch 事件中提取参数
trigger_manager_extract_workflow_dispatch_params() {
    local event_data="$1"
    
    debug "log" "Extracting parameters from workflow_dispatch event"
    
    # 从完整事件数据中提取 inputs 部分
    local tag=$(echo "$event_data" | jq -r '.inputs.tag // empty')
    local email=$(echo "$event_data" | jq -r '.inputs.email // empty')
    local customer=$(echo "$event_data" | jq -r '.inputs.customer // empty')
    local customer_link=$(echo "$event_data" | jq -r '.inputs.customer_link // empty')
    local super_password=$(echo "$event_data" | jq -r '.inputs.super_password // empty')
    local slogan=$(echo "$event_data" | jq -r '.inputs.slogan // empty')
    local rendezvous_server=$(echo "$event_data" | jq -r '.inputs.rendezvous_server // empty')
    local rs_pub_key=$(echo "$event_data" | jq -r '.inputs.rs_pub_key // empty')
    local api_server=$(echo "$event_data" | jq -r '.inputs.api_server // empty')
    
    debug "var" "Extracted tag" "$tag"
    debug "var" "Extracted email" "$email"
    debug "var" "Extracted customer" "$customer"
    
    # 返回提取的参数（正确引用包含空格的变量值）
    echo "TAG=\"$tag\""
    echo "EMAIL=\"$email\""
    echo "CUSTOMER=\"$customer\""
    echo "CUSTOMER_LINK=\"$customer_link\""
    echo "SUPER_PASSWORD=\"$super_password\""
    echo "SLOGAN=\"$slogan\""
    echo "RENDEZVOUS_SERVER=\"$rendezvous_server\""
    echo "RS_PUB_KEY=\"$rs_pub_key\""
    echo "API_SERVER=\"$api_server\""
}

# 私有方法：从 issue 内容中提取参数
trigger_manager_extract_issue_params() {
    local event_data="$1"
    
    debug "log" "Extracting parameters from issue event"
    
    # 从事件数据中提取 issue 信息
    local build_id=$(echo "$event_data" | jq -r '.issue.number // empty')
    local issue_body=$(echo "$event_data" | jq -r '.issue.body // empty')
    
    debug "var" "Issue number" "$build_id"
    
    # 使用新格式提取参数（JSON格式）
    local tag=$(echo "$issue_body" | jq -r '.tag // empty' 2>/dev/null)
    local email=$(echo "$issue_body" | jq -r '.email // empty' 2>/dev/null)
    local customer=$(echo "$issue_body" | jq -r '.customer // empty' 2>/dev/null)
    local customer_link=$(echo "$issue_body" | jq -r '.customer_link // empty' 2>/dev/null)
    local super_password=$(echo "$issue_body" | jq -r '.super_password // empty' 2>/dev/null)
    local slogan=$(echo "$issue_body" | jq -r '.slogan // empty' 2>/dev/null)
    local rendezvous_server=$(echo "$issue_body" | jq -r '.rendezvous_server // empty' 2>/dev/null)
    local rs_pub_key=$(echo "$issue_body" | jq -r '.rs_pub_key // empty' 2>/dev/null)
    local api_server=$(echo "$issue_body" | jq -r '.api_server // empty' 2>/dev/null)
    
    # 如果新格式提取失败，尝试旧格式
    if [ -z "$tag" ]; then
        tag=$(echo "$issue_body" | sed -n 's/.*--tag:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
        debug "log" "Using legacy format for tag extraction"
    fi
    if [ -z "$email" ]; then
        email=$(echo "$issue_body" | sed -n 's/.*--email:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
    fi
    if [ -z "$customer" ]; then
        customer=$(echo "$issue_body" | sed -n 's/.*--customer:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
    fi
    if [ -z "$customer_link" ]; then
        customer_link=$(echo "$issue_body" | sed -n 's/.*--customer_link:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
    fi
    if [ -z "$super_password" ]; then
        super_password=$(echo "$issue_body" | sed -n 's/.*--super_password:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
    fi
    if [ -z "$slogan" ]; then
        slogan=$(echo "$issue_body" | sed -n 's/.*--slogan:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
    fi
    if [ -z "$rendezvous_server" ]; then
        rendezvous_server=$(echo "$issue_body" | sed -n 's/.*--rendezvous_server:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
    fi
    if [ -z "$rs_pub_key" ]; then
        rs_pub_key=$(echo "$issue_body" | sed -n 's/.*--rs_pub_key:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
    fi
    if [ -z "$api_server" ]; then
        api_server=$(echo "$issue_body" | sed -n 's/.*--api_server:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
    fi
    
    debug "var" "Extracted tag" "$tag"
    debug "var" "Extracted email" "$email"
    debug "var" "Extracted customer" "$customer"
        
    # 返回提取的参数（正确引用包含空格的变量值）
    echo "BUILD_ID=\"$build_id\""
    echo "TAG=\"$tag\""
    echo "EMAIL=\"$email\""
    echo "CUSTOMER=\"$customer\""
    echo "CUSTOMER_LINK=\"$customer_link\""
    echo "SUPER_PASSWORD=\"$super_password\""
    echo "SLOGAN=\"$slogan\""
    echo "RENDEZVOUS_SERVER=\"$rendezvous_server\""
    echo "RS_PUB_KEY=\"$rs_pub_key\""
    echo "API_SERVER=\"$api_server\""
}

# 私有方法：应用默认值（使用 secrets）
trigger_manager_apply_default_values() {
    local tag="$1"
    local email="$2"
    local customer="$3"
    local customer_link="$4"
    local super_password="$5"
    local slogan="$6"
    local rendezvous_server="$7"
    local rs_pub_key="$8"
    local api_server="$9"
    
    debug "log" "Applying default values"
    
    # 检查关键参数是否为空，如果为空则使用secrets兜底
    if [ -z "$rendezvous_server" ] || [ -z "$rs_pub_key" ]; then
        debug "warning" "Using secrets fallback for missing critical parameters"
        tag="${tag:-$DEFAULT_TAG}"
        email="${email:-$DEFAULT_EMAIL}"
        customer="${customer:-$DEFAULT_CUSTOMER}"
        customer_link="${customer_link:-$DEFAULT_CUSTOMER_LINK}"
        super_password="${super_password:-$DEFAULT_SUPER_PASSWORD}"
        slogan="${slogan:-$DEFAULT_SLOGAN}"
        rendezvous_server="${rendezvous_server:-$DEFAULT_RENDEZVOUS_SERVER}"
        rs_pub_key="${rs_pub_key:-$DEFAULT_RS_PUB_KEY}"
        api_server="${api_server:-$DEFAULT_API_SERVER}"
    fi
    
    debug "var" "Final tag" "$tag"
    debug "var" "Final email" "$email"
    debug "var" "Final customer" "$customer"
    
    # 返回应用默认值后的参数（正确引用包含空格的变量值）
    echo "TAG=\"$tag\""
    echo "EMAIL=\"$email\""
    echo "CUSTOMER=\"$customer\""
    echo "CUSTOMER_LINK=\"$customer_link\""
    echo "SUPER_PASSWORD=\"$super_password\""
    echo "SLOGAN=\"$slogan\""
    echo "RENDEZVOUS_SERVER=\"$rendezvous_server\""
    echo "RS_PUB_KEY=\"$rs_pub_key\""
    echo "API_SERVER=\"$api_server\""
}

# 私有方法：处理 tag 时间戳
trigger_manager_process_tag_timestamp() {
    local original_tag="$1"
    
    debug "log" "Processing tag timestamp for: $original_tag"
    
    # 如果tag已经包含时间戳，直接返回
    if [[ "$original_tag" =~ ^.*-[0-9]{8}-[0-9]{6}$ ]]; then
        debug "log" "Tag already contains timestamp"
        echo "$original_tag"
        return 0
    fi
    
    # 生成时间戳
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    local final_tag="${original_tag}-${timestamp}"
    
    debug "var" "Generated timestamp" "$timestamp"
    debug "var" "Final tag" "$final_tag"
    
    echo "$final_tag"
}

# 私有方法：生成最终JSON数据
trigger_manager_generate_final_data() {
    local final_tag="$1"
    local original_tag="$2"
    local email="$3"
    local customer="$4"
    local customer_link="$5"
    local super_password="$6"
    local slogan="$7"
    local rendezvous_server="$8"
    local rs_pub_key="$9"
    local api_server="${10}"
    
    debug "log" "Generating final JSON data"
    
    # 生成初始JSON数据
    local data=$(jq -c -n \
        --arg tag "$final_tag" \
        --arg original_tag "$original_tag" \
        --arg email "$email" \
        --arg customer "$customer" \
        --arg customer_link "$customer_link" \
        --arg super_password "$super_password" \
        --arg slogan "$slogan" \
        --arg rendezvous_server "$rendezvous_server" \
        --arg rs_pub_key "$rs_pub_key" \
        --arg api_server "$api_server" \
        '{tag: $tag, original_tag: $original_tag, email: $email, customer: $customer, customer_link: $customer_link, super_password: $super_password, slogan: $slogan, rendezvous_server: $rendezvous_server, rs_pub_key: $rs_pub_key, api_server: $api_server}')
    
    debug "var" "Generated JSON data" "$data"
    echo "$data"
}

# 私有方法：更新 issue 内容
trigger_manager_update_issue_content() {
    local issue_number="$1"
    local cleaned_body="$2"
    
    debug "log" "Updating issue content for issue #$issue_number"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$cleaned_body" '{"body": $body}')
    
    # 使用GitHub API更新issue
    local response=$(curl -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Issue #$issue_number updated successfully"
        return 0
    else
        debug "error" "Failed to update issue #$issue_number"
        return 1
    fi
}

# 私有方法：清理 issue 内容
trigger_manager_clean_issue_content() {
    local final_tag="$1"
    local original_tag="$2"
    local customer="$3"
    local slogan="$4"
    
    debug "log" "Cleaning issue content"
    
    local cleaned_body=$(generate_cleaned_issue_body "$final_tag" "$original_tag" "$customer" "$slogan")
    
    debug "var" "Cleaned body" "$cleaned_body"
    echo "$cleaned_body"
}

# 私有方法：输出到 GitHub Actions
trigger_manager_output_to_github() {
    local final_data="$1"
    local trigger_type="$2"
    local current_build_id="$3"
    local final_tag="$4"
    local email="$5"
    local customer="$6"
    local slogan="$7"
    local rendezvous_server="$8"
    local api_server="$9"
    
    debug "log" "Outputting to GitHub Actions"
    
    # 检查是否在GitHub Actions环境中
    if [ -n "$GITHUB_OUTPUT" ]; then
        echo "data=$final_data" >> $GITHUB_OUTPUT
    echo "trigger_type=$trigger_type" >> $GITHUB_OUTPUT
    echo "build_id=$current_build_id" >> $GITHUB_OUTPUT
        echo "tag=$final_tag" >> $GITHUB_OUTPUT
        echo "email=$email" >> $GITHUB_OUTPUT
        echo "customer=$customer" >> $GITHUB_OUTPUT
        echo "slogan=$slogan" >> $GITHUB_OUTPUT
        echo "rendezvous_server=$rendezvous_server" >> $GITHUB_OUTPUT
        echo "api_server=$api_server" >> $GITHUB_OUTPUT
    echo "should_proceed=true" >> $GITHUB_OUTPUT
    
        debug "success" "Output written to GitHub Actions"
    else
        debug "warning" "Not in GitHub Actions environment, skipping output"
    fi
    
    # 显示输出信息
    echo "Trigger output: $final_data"
}

# 公共方法：获取触发类型
trigger_manager_get_trigger_type() {
    echo "$_TRIGGER_MANAGER_TRIGGER_TYPE"
}

# 公共方法：获取最终数据
trigger_manager_get_final_data() {
    echo "$_TRIGGER_MANAGER_FINAL_DATA"
}

# 公共方法：获取提取的参数
trigger_manager_get_extracted_params() {
    echo "$_TRIGGER_MANAGER_EXTRACTED_PARAMS"
}

# 公共方法：验证参数
trigger_manager_validate_params() {
    local tag="$1"
    local email="$2"
    local customer="$3"
    local rendezvous_server="$4"
    local api_server="$5"
    
    debug "log" "Validating parameters"
    
    local errors=()
    
    # 检查必需参数
    if [ -z "$tag" ]; then
        errors+=("Tag is required")
    fi
    if [ -z "$email" ]; then
        errors+=("Email is required")
    fi
    if [ -z "$customer" ]; then
        errors+=("Customer is required")
    fi
    if [ -z "$rendezvous_server" ]; then
        errors+=("Rendezvous server is required")
    fi
    if [ -z "$api_server" ]; then
        errors+=("API server is required")
    fi
    
    # 验证邮箱格式
    if [ -n "$email" ] && ! echo "$email" | grep -E "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$" > /dev/null; then
        errors+=("Invalid email format")
    fi
    
    # 返回错误数量
    echo "${#errors[@]}"
    
    # 输出错误信息
    for error in "${errors[@]}"; do
        debug "error" "$error"
    done
}

# 主 Trigger 管理函数 - 供工作流调用
trigger_manager() {
    local operation="$1"
    local event_name="${2:-}"
    local event_data="${3:-}"
    local build_id="${4:-}"
    
    # 初始化 Trigger 管理器
    trigger_manager_init "$event_name" "$event_data" "$build_id"
    
    case "$operation" in
        "extract-workflow-dispatch")
            trigger_manager_extract_workflow_dispatch_params "$event_data"
            ;;
        "extract-issue")
            trigger_manager_extract_issue_params "$event_data"
            ;;
        "apply-defaults")
            local tag="$2"
            local email="$3"
            local customer="$4"
            local customer_link="$5"
            local super_password="$6"
            local slogan="$7"
            local rendezvous_server="$8"
            local rs_pub_key="$9"
            local api_server="${10}"
            trigger_manager_apply_default_values "$tag" "$email" "$customer" "$customer_link" "$super_password" "$slogan" "$rendezvous_server" "$rs_pub_key" "$api_server"
            ;;
        "process-tag")
            local original_tag="$2"
            trigger_manager_process_tag_timestamp "$original_tag"
            ;;
        "generate-data")
            local final_tag="$2"
            local original_tag="$3"
            local email="$4"
            local customer="$5"
            local customer_link="$6"
            local super_password="$7"
            local slogan="$8"
            local rendezvous_server="$9"
            local rs_pub_key="${10}"
            local api_server="${11}"
            trigger_manager_generate_final_data "$final_tag" "$original_tag" "$email" "$customer" "$customer_link" "$super_password" "$slogan" "$rendezvous_server" "$rs_pub_key" "$api_server"
            ;;
        "update-issue")
            local issue_number="$2"
            local cleaned_body="$3"
            trigger_manager_update_issue_content "$issue_number" "$cleaned_body"
            ;;
        "clean-issue")
            local final_tag="$2"
            local original_tag="$3"
            local customer="$4"
            local slogan="$5"
            trigger_manager_clean_issue_content "$final_tag" "$original_tag" "$customer" "$slogan"
            ;;
        "get-trigger-type")
            trigger_manager_get_trigger_type
            ;;
        "get-final-data")
            trigger_manager_get_final_data
            ;;
        "get-extracted-params")
            trigger_manager_get_extracted_params
            ;;
        "validate")
            local tag="$2"
            local email="$3"
            local customer="$4"
            local rendezvous_server="$5"
            local api_server="$6"
            trigger_manager_validate_params "$tag" "$email" "$customer" "$rendezvous_server" "$api_server"
            ;;
        "output-to-github")
            local final_data="$2"
            local trigger_type="$3"
            local build_id="$4"
            local final_tag="$5"
            local email="$6"
            local customer="$7"
            local slogan="$8"
            local rendezvous_server="$9"
            local api_server="${10}"
            trigger_manager_output_to_github "$final_data" "$trigger_type" "$build_id" "$final_tag" "$email" "$customer" "$slogan" "$rendezvous_server" "$api_server"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
