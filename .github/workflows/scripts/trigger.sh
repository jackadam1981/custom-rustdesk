#!/bin/bash
# 触发器和参数提取脚本
# 这个文件处理事件触发和参数提取逻辑

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# GitHub Actions 环境变量设置
# 这些变量在 GitHub Actions 中自动提供

# 从 workflow_dispatch 事件中提取参数
extract_workflow_dispatch_params() {
    local event_data="$1"
    
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

# 从 issue 内容中提取参数
extract_issue_params() {
    local event_data="$1"
    
    # 从事件数据中提取 issue 信息
    local build_id=$(echo "$event_data" | jq -r '.issue.number // empty')
    local issue_body=$(echo "$event_data" | jq -r '.issue.body // empty')
    
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

# 应用默认值（使用 secrets）
apply_default_values() {
    local tag="$1"
    local email="$2"
    local customer="$3"
    local customer_link="$4"
    local super_password="$5"
    local slogan="$6"
    local rendezvous_server="$7"
    local rs_pub_key="$8"
    local api_server="$9"
    
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

# 处理 tag 时间戳
process_tag_timestamp() {
    local original_tag="$1"
    
    # 如果tag已经包含时间戳，直接返回
    if [[ "$original_tag" =~ ^.*-[0-9]{8}-[0-9]{6}$ ]]; then
        echo "$original_tag"
        return 0
    fi
    
    # 生成时间戳
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    local final_tag="${original_tag}-${timestamp}"
    
    echo "$final_tag"
}

# 生成最终JSON数据
generate_final_data() {
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
    
    echo "$data"
}



# 更新 issue 内容
update_issue_content() {
    local issue_number="$1"
    local cleaned_body="$2"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$cleaned_body" '{"body": $body}')
    
    # 使用GitHub API更新issue
    curl -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number \
        -d "$json_payload"
}

# 主处理函数
process_trigger() {
    local event_name="$1"
    local event_data="$2"
    local build_id="$3"

    debug "log" "Preparing environment..."
    
    # 如果参数为空，尝试从环境变量获取
    if [ -z "$event_name" ]; then
        event_name="$EVENT_NAME"
    fi
    if [ -z "$event_data" ]; then
        event_data="$EVENT_DATA"
    fi
    if [ -z "$build_id" ]; then
        build_id="$BUILD_ID"
    fi
    
    debug "var" "Event name" "$event_name"
    debug "var" "Build ID" "$build_id"
    # 判断触发方式并提取参数
    if [ "$event_name" = "workflow_dispatch" ]; then
        # 手动触发：使用workflow_dispatch输入参数
        local params=$(extract_workflow_dispatch_params "$event_data")
        eval "$params"
        local trigger_type="workflow_dispatch"
        local current_build_id="$build_id"
    else
        # Issue触发：从issue内容中提取参数
        local params=$(extract_issue_params "$event_data")
        eval "$params"
        local trigger_type="issue"
        local current_build_id="$BUILD_ID"
    fi
    
    # 应用默认值
    local final_params=$(apply_default_values "$TAG" "$EMAIL" "$CUSTOMER" "$CUSTOMER_LINK" "$SUPER_PASSWORD" "$SLOGAN" "$RENDEZVOUS_SERVER" "$RS_PUB_KEY" "$API_SERVER")
    eval "$final_params"
    
    # 处理tag时间戳
    local final_tag=$(process_tag_timestamp "$TAG")
    
    # 生成最终JSON数据
    local final_data=$(generate_final_data "$final_tag" "$TAG" "$EMAIL" "$CUSTOMER" "$CUSTOMER_LINK" "$SUPER_PASSWORD" "$SLOGAN" "$RENDEZVOUS_SERVER" "$RS_PUB_KEY" "$API_SERVER")
    
    # 如果是issue触发，清理issue内容
    if [ "$trigger_type" = "issue" ] && [ -n "$current_build_id" ]; then
        local cleaned_body=$(generate_cleaned_issue_body "$final_tag" "$TAG" "$CUSTOMER" "$SLOGAN")
        update_issue_content "$current_build_id" "$cleaned_body"
    fi
    
    # 输出到GitHub Actions输出变量
    echo "data=$final_data" >> $GITHUB_OUTPUT
    echo "trigger_type=$trigger_type" >> $GITHUB_OUTPUT
    echo "build_id=$current_build_id" >> $GITHUB_OUTPUT
    echo "tag=$final_tag" >> $GITHUB_OUTPUT
    echo "email=$EMAIL" >> $GITHUB_OUTPUT
    echo "customer=$CUSTOMER" >> $GITHUB_OUTPUT
    echo "slogan=$SLOGAN" >> $GITHUB_OUTPUT
    echo "rendezvous_server=$RENDEZVOUS_SERVER" >> $GITHUB_OUTPUT
    echo "api_server=$API_SERVER" >> $GITHUB_OUTPUT
    echo "should_proceed=true" >> $GITHUB_OUTPUT
    
    # 显示输出信息
    echo "Trigger output: $final_data"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 2 ]; then
        echo "Usage: $0 <event_name> <event_data> [build_id]"
        exit 1
    fi
    
    process_trigger "$@"
fi 
