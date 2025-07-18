#!/bin/bash
# 触发器和参数提取脚本
# 这个文件处理事件触发和参数提取逻辑

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh
source .github/workflows/scripts/json-validator.sh

# GitHub Actions 环境变量设置
# 这些变量在 GitHub Actions 中自动提供

# 从 workflow_dispatch 事件中提取参数
extract_workflow_dispatch_params() {
    local event_data="$1"
    
    debug_enter "extract_workflow_dispatch_params" "event_data_length=${#event_data}"
    
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
    
    debug_success "手动触发检测到"
    debug_var "TAG" "$tag"
    debug_var "EMAIL" "$email"
    debug_var "CUSTOMER" "$customer"
    debug_var "CUSTOMER_LINK" "$customer_link"
    debug_var "SUPER_PASSWORD" "$super_password"
    debug_var "SLOGAN" "$slogan"
    debug_var "RENDEZVOUS_SERVER" "$rendezvous_server"
    debug_var "RS_PUB_KEY" "$rs_pub_key"
    debug_var "API_SERVER" "$api_server"
    
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
    
    debug_exit "extract_workflow_dispatch_params" 0
}

# 从 issue 内容中提取参数
extract_issue_params() {
    local event_data="$1"
    
    debug_enter "extract_issue_params" "event_data_length=${#event_data}"
    
    # 从事件数据中提取 issue 信息
    local build_id=$(echo "$event_data" | jq -r '.issue.number // empty')
    local issue_body=$(echo "$event_data" | jq -r '.issue.body // empty')
    
    debug_var "BUILD_ID" "$build_id"
    debug_var "ISSUE_BODY" "$issue_body"
    
    # 保存原始issue内容供后续使用
    echo "ORIGINAL_ISSUE_BODY=$issue_body" >> $GITHUB_ENV
    
    # 使用sed和awk提取参数 - 兼容性更好的方法
    # 支持多种格式：tag: value, --tag: value, tag=value
    local tag=$(echo "$issue_body" | sed -n 's/.*[[:space:]]*\(--\)\?tag:[[:space:]]*\([^[:space:]\r\n]*\).*/\2/p' | head -1)
    local email=$(echo "$issue_body" | sed -n 's/.*[[:space:]]*\(--\)\?email:[[:space:]]*\([^[:space:]\r\n]*\).*/\2/p' | head -1)
    local customer=$(echo "$issue_body" | sed -n 's/.*[[:space:]]*\(--\)\?customer:[[:space:]]*\([^[:space:]\r\n]*\).*/\2/p' | head -1)
    local customer_link=$(echo "$issue_body" | sed -n 's/.*[[:space:]]*\(--\)\?customer_link:[[:space:]]*\([^[:space:]\r\n]*\).*/\2/p' | head -1)
    local super_password=$(echo "$issue_body" | sed -n 's/.*[[:space:]]*\(--\)\?super_password:[[:space:]]*\([^[:space:]\r\n]*\).*/\2/p' | head -1)
    local slogan=$(echo "$issue_body" | sed -n 's/.*[[:space:]]*\(--\)\?slogan:[[:space:]]*\([^[:space:]\r\n]*\).*/\2/p' | head -1)
    local rendezvous_server=$(echo "$issue_body" | sed -n 's/.*[[:space:]]*\(--\)\?rendezvous_server:[[:space:]]*\([^[:space:]\r\n]*\).*/\2/p' | head -1)
    local rs_pub_key=$(echo "$issue_body" | sed -n 's/.*[[:space:]]*\(--\)\?rs_pub_key:[[:space:]]*\([^[:space:]\r\n]*\).*/\2/p' | head -1)
    local api_server=$(echo "$issue_body" | sed -n 's/.*[[:space:]]*\(--\)\?api_server:[[:space:]]*\([^[:space:]\r\n]*\).*/\2/p' | head -1)
    
    debug_success "Issue触发检测到"
    debug_var "提取的TAG" "$tag"
    debug_var "提取的EMAIL" "$email"
    debug_var "提取的CUSTOMER" "$customer"
    debug_var "提取的CUSTOMER_LINK" "$customer_link"
    debug_var "提取的SUPER_PASSWORD" "$super_password"
    debug_var "提取的SLOGAN" "$slogan"
    debug_var "提取的RENDEZVOUS_SERVER" "$rendezvous_server"
    debug_var "提取的RS_PUB_KEY" "$rs_pub_key"
    debug_var "提取的API_SERVER" "$api_server"
    
    # 如果新格式没有找到，尝试旧格式
    if [ -z "$tag" ]; then
        tag=$(echo "$issue_body" | sed -n 's/.*--tag:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
        debug_warning "使用旧格式提取TAG" "$tag"
    fi
    if [ -z "$email" ]; then
        email=$(echo "$issue_body" | sed -n 's/.*--email:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
        debug_warning "使用旧格式提取EMAIL" "$email"
    fi
    if [ -z "$customer" ]; then
        customer=$(echo "$issue_body" | sed -n 's/.*--customer:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
        debug_warning "使用旧格式提取CUSTOMER" "$customer"
    fi
    if [ -z "$customer_link" ]; then
        customer_link=$(echo "$issue_body" | sed -n 's/.*--customer_link:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
        debug_warning "使用旧格式提取CUSTOMER_LINK" "$customer_link"
    fi
    if [ -z "$super_password" ]; then
        super_password=$(echo "$issue_body" | sed -n 's/.*--super_password:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
        debug_warning "使用旧格式提取SUPER_PASSWORD" "$super_password"
    fi
    if [ -z "$slogan" ]; then
        slogan=$(echo "$issue_body" | sed -n 's/.*--slogan:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
        debug_warning "使用旧格式提取SLOGAN" "$slogan"
    fi
    if [ -z "$rendezvous_server" ]; then
        rendezvous_server=$(echo "$issue_body" | sed -n 's/.*--rendezvous_server:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
        debug_warning "使用旧格式提取RENDEZVOUS_SERVER" "$rendezvous_server"
    fi
    if [ -z "$rs_pub_key" ]; then
        rs_pub_key=$(echo "$issue_body" | sed -n 's/.*--rs_pub_key:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
        debug_warning "使用旧格式提取RS_PUB_KEY" "$rs_pub_key"
    fi
    if [ -z "$api_server" ]; then
        api_server=$(echo "$issue_body" | sed -n 's/.*--api_server:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | head -1)
        debug_warning "使用旧格式提取API_SERVER" "$api_server"
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
    
    debug_exit "extract_issue_params" 0
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
        echo "Using secrets fallback for missing critical parameters" >&2
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
    local tag="$1"
    
    # 为tag添加时间标记，确保版本唯一
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    
    # 如果tag不为空，添加时间标记
    if [ -n "$tag" ]; then
        # 检查tag是否已经包含时间标记（避免重复添加）
        if [[ "$tag" =~ [0-9]{8}-[0-9]{6}$ ]]; then
            echo "Tag already contains timestamp: $tag" >&2
            echo "FINAL_TAG=$tag"
            echo "ORIGINAL_TAG=$tag"
        else
            # 添加时间标记到tag
            local final_tag="${tag}-${timestamp}"
            echo "Added timestamp to tag: $final_tag" >&2
            echo "FINAL_TAG=$final_tag"
            echo "ORIGINAL_TAG=$tag"
        fi
    else
        # 如果tag为空，使用默认tag加时间标记
        local final_tag="rustdesk-${timestamp}"
        echo "Using default tag with timestamp: $final_tag" >&2
        echo "FINAL_TAG=$final_tag"
        echo "ORIGINAL_TAG="
    fi
}

# 生成构建数据 JSON
generate_build_data() {
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

**状态：** 构建已启动
**时间：** $(date '+%Y-%m-%d %H:%M:%S')

---
*敏感信息已自动清理，原始参数已安全保存*
EOF
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

    echo "Preparing environment..." >&2 
    
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
    
    echo "Event name: $event_name" >&2
    echo "Build ID: $build_id" >&2
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
    local defaulted_params=$(apply_default_values "$TAG" "$EMAIL" "$CUSTOMER" "$CUSTOMER_LINK" "$SUPER_PASSWORD" "$SLOGAN" "$RENDEZVOUS_SERVER" "$RS_PUB_KEY" "$API_SERVER")
    eval "$defaulted_params"
    
    # 处理 tag 时间戳
    local timestamp_params=$(process_tag_timestamp "$TAG")
    eval "$timestamp_params"
    
    # 生成构建数据
    local data=$(generate_build_data "$FINAL_TAG" "$ORIGINAL_TAG" "$EMAIL" "$CUSTOMER" "$CUSTOMER_LINK" "$SUPER_PASSWORD" "$SLOGAN" "$RENDEZVOUS_SERVER" "$RS_PUB_KEY" "$API_SERVER")
    
    # 校验生成的JSON数据
    if ! validate_json_detailed "$data" "trigger.sh-生成构建数据"; then
        echo "错误: trigger.sh生成的JSON格式不正确" >&2
        exit 1
    fi
    
    # 输出结果到GITHUB_OUTPUT
    echo "trigger_data<<EOF" >> $GITHUB_OUTPUT
    echo "$data" >> $GITHUB_OUTPUT
    echo "EOF" >> $GITHUB_OUTPUT
    echo "trigger_type=$trigger_type" >> $GITHUB_OUTPUT
    echo "build_id=$current_build_id" >> $GITHUB_OUTPUT
    echo "should_proceed=true" >> $GITHUB_OUTPUT
    
    # 如果 issue 触发，更新 issue 内容
    if [ "$trigger_type" = "issue" ]; then
        local cleaned_body=$(generate_cleaned_issue_body "$FINAL_TAG" "$ORIGINAL_TAG" "$CUSTOMER" "$SLOGAN")
        update_issue_content "$current_build_id" "$cleaned_body"
    fi
}

# 主执行逻辑
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 脚本被直接执行
    if [ $# -lt 2 ]; then
        echo "用法: $0 <event_name> <event_data> [build_id]" >&2
        echo "示例: $0 workflow_dispatch '{\"inputs\":{\"tag\":\"test\"}}' 123" >&2
        exit 1
    fi
    
    local event_name="$1"
    local event_data="$2"
    local build_id="${3:-}"
    
    # 在 GitHub Actions 中，这些环境变量应该通过 secrets 或 workflow 配置提供
    # 如果本地测试需要，请设置相应的环境变量
    
    # 执行主处理函数
    process_trigger "$event_name" "$event_data" "$build_id"
    
    # 在 GitHub Actions 中，输出会自动处理
    # 本地测试时显示结果
    if [ -n "$GITHUB_ACTIONS" ]; then
        echo "Running in GitHub Actions environment"
    else
    echo "=== 处理结果 ==="
    if [ -f "$GITHUB_OUTPUT" ]; then
        cat "$GITHUB_OUTPUT"
    fi
    if [ -f "$GITHUB_ENV" ]; then
        echo "=== 环境变量 ==="
        cat "$GITHUB_ENV"
        fi
    fi
fi 
