#!/bin/bash
# 触发器和参数提取脚本 - 伪面向对象模式
# 这个文件处理事件触发和参数提取逻辑，采用简单的伪面向对象设计

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# Trigger 管理器 - 处理触发事件和参数提取

# 私有方法：从 workflow_dispatch 事件中提取参数
trigger_extract_workflow_dispatch_params() {
    local event_data="$1"
    
    debug "log" "Extracting parameters from workflow_dispatch event"
    
    # 添加详细的debug输出
    debug "var" "Event data length" "${#event_data}"
    debug "log" "Event data content:"
    echo "$event_data" | jq '.' | while IFS= read -r line; do
        debug "log" "  $line"
    done
    
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
    
    # 添加提取结果的debug输出
    debug "var" "Workflow dispatch - tag" "$tag"
    debug "var" "Workflow dispatch - email" "$email"
    debug "var" "Workflow dispatch - customer" "$customer"
    debug "var" "Workflow dispatch - customer_link" "$customer_link"
    debug "var" "Workflow dispatch - super_password" "$super_password"
    debug "var" "Workflow dispatch - slogan" "$slogan"
    debug "var" "Workflow dispatch - rendezvous_server" "$rendezvous_server"
    debug "var" "Workflow dispatch - rs_pub_key" "$rs_pub_key"
    debug "var" "Workflow dispatch - api_server" "$api_server"
    
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
trigger_extract_issue_params() {
    local event_data="$1"
    
    debug "log" "Extracting parameters from issue event"
    
    # 从事件数据中提取 issue 信息
    local build_id=$(echo "$event_data" | jq -r '.issue.number // empty')
    local issue_body=$(echo "$event_data" | jq -r '.issue.body // empty')
    
    # 添加详细的debug输出
    debug "var" "Issue number" "$build_id"
    debug "var" "Issue body length" "${#issue_body}"
    debug "log" "Issue body content:"
    echo "$issue_body" | while IFS= read -r line; do
        debug "log" "  $line"
    done
    
    # 使用新格式提取参数（JSON格式）
    debug "log" "New Extracting parameters from issue body"
    local tag=$(echo "$issue_body" | jq -r '.tag // empty' 2>/dev/null)
    local email=$(echo "$issue_body" | jq -r '.email // empty' 2>/dev/null)
    local customer=$(echo "$issue_body" | jq -r '.customer // empty' 2>/dev/null)
    local customer_link=$(echo "$issue_body" | jq -r '.customer_link // empty' 2>/dev/null)
    local super_password=$(echo "$issue_body" | jq -r '.super_password // empty' 2>/dev/null)
    local slogan=$(echo "$issue_body" | jq -r '.slogan // empty' 2>/dev/null)
    local rendezvous_server=$(echo "$issue_body" | jq -r '.rendezvous_server // empty' 2>/dev/null)
    local rs_pub_key=$(echo "$issue_body" | jq -r '.rs_pub_key // empty' 2>/dev/null)
    local api_server=$(echo "$issue_body" | jq -r '.api_server // empty' 2>/dev/null)
    
    # 添加JSON格式提取的debug输出
    debug "var" "JSON tag" "$tag"
    debug "var" "JSON email" "$email"
    debug "var" "JSON customer" "$customer"
    debug "var" "JSON rendezvous_server" "$rendezvous_server"
    debug "var" "JSON api_server" "$api_server"
    
    # 如果新格式提取失败，尝试旧格式
    if [ -z "$tag" ]; then
        debug "log" "Old Extracting parameters from issue body"
        # 改进的正则表达式，匹配到行尾或下一个参数
        tag=$(echo "$issue_body" | sed -n 's/.*tag:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
        debug "log" "Using legacy format for tag extraction: $tag"
    fi
    if [ -z "$email" ]; then
        email=$(echo "$issue_body" | sed -n 's/.*email:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
        debug "var" "Legacy email" "$email"
    fi
    if [ -z "$customer" ]; then
        customer=$(echo "$issue_body" | sed -n 's/.*customer:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
        debug "var" "Legacy customer" "$customer"
    fi
    if [ -z "$customer_link" ]; then
        customer_link=$(echo "$issue_body" | sed -n 's/.*customer_link:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
        debug "var" "Legacy customer_link" "$customer_link"
    fi
    if [ -z "$super_password" ]; then
        super_password=$(echo "$issue_body" | sed -n 's/.*super_password:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
        debug "var" "Legacy super_password" "$super_password"
    fi
    if [ -z "$slogan" ]; then
        slogan=$(echo "$issue_body" | sed -n 's/.*slogan:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
        debug "var" "Legacy slogan" "$slogan"
    fi
    if [ -z "$rendezvous_server" ]; then
        rendezvous_server=$(echo "$issue_body" | sed -n 's/.*rendezvous_server:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
        debug "var" "Legacy rendezvous_server" "$rendezvous_server"
    fi
    if [ -z "$rs_pub_key" ]; then
        rs_pub_key=$(echo "$issue_body" | sed -n 's/.*rs_pub_key:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
        debug "var" "Legacy rs_pub_key" "$rs_pub_key"
    fi
    if [ -z "$api_server" ]; then
        api_server=$(echo "$issue_body" | sed -n 's/.*api_server:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
        debug "var" "Legacy api_server" "$api_server"
    fi
        
    # 添加最终提取结果的debug输出
    debug "var" "Final tag" "$tag"
    debug "var" "Final email" "$email"
    debug "var" "Final customer" "$customer"
    debug "var" "Final rendezvous_server" "$rendezvous_server"
    debug "var" "Final api_server" "$api_server"
    
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
trigger_apply_default_values() {
    local event_data="$1"
    
    debug "log" "Applying default values"
    
    # 根据事件类型从不同路径提取参数
    local tag=""
    local email=""
    local customer=""
    local customer_link=""
    local super_password=""
    local slogan=""
    local rendezvous_server=""
    local rs_pub_key=""
    local api_server=""
    
    # 检查是否为workflow_dispatch事件
    if echo "$event_data" | jq -e '.inputs' > /dev/null 2>&1; then
        # workflow_dispatch事件
        debug "log" "Applying defaults for workflow_dispatch event"
        tag=$(echo "$event_data" | jq -r '.inputs.tag // empty')
        email=$(echo "$event_data" | jq -r '.inputs.email // empty')
        customer=$(echo "$event_data" | jq -r '.inputs.customer // empty')
        customer_link=$(echo "$event_data" | jq -r '.inputs.customer_link // empty')
        super_password=$(echo "$event_data" | jq -r '.inputs.super_password // empty')
        slogan=$(echo "$event_data" | jq -r '.inputs.slogan // empty')
        rendezvous_server=$(echo "$event_data" | jq -r '.inputs.rendezvous_server // empty')
        rs_pub_key=$(echo "$event_data" | jq -r '.inputs.rs_pub_key // empty')
        api_server=$(echo "$event_data" | jq -r '.inputs.api_server // empty')
        
        debug "var" "Workflow dispatch defaults - tag" "$tag"
        debug "var" "Workflow dispatch defaults - email" "$email"
        debug "var" "Workflow dispatch defaults - customer" "$customer"
        debug "var" "Workflow dispatch defaults - rendezvous_server" "$rendezvous_server"
        debug "var" "Workflow dispatch defaults - api_server" "$api_server"
    else
        # issues事件，从环境变量中读取（因为issue参数已经在extract-issue中设置）
        # 如果参数为空，使用默认值
        debug "var" "TAG from env" "$TAG"
        debug "var" "EMAIL from env" "$EMAIL"
        debug "var" "CUSTOMER from env" "$CUSTOMER"
        debug "var" "RENDEZVOUS_SERVER from env" "$RENDEZVOUS_SERVER"
        debug "var" "API_SERVER from env" "$API_SERVER"
        
        tag="${TAG:-${DEFAULT_TAG:-}}"
        email="${EMAIL:-${DEFAULT_EMAIL:-}}"
        customer="${CUSTOMER:-${DEFAULT_CUSTOMER:-}}"
        customer_link="${CUSTOMER_LINK:-${DEFAULT_CUSTOMER_LINK:-}}"
        super_password="${SUPER_PASSWORD:-${DEFAULT_SUPER_PASSWORD:-}}"
        slogan="${SLOGAN:-${DEFAULT_SLOGAN:-}}"
        rendezvous_server="${RENDEZVOUS_SERVER:-${DEFAULT_RENDEZVOUS_SERVER:-}}"
        rs_pub_key="${RS_PUB_KEY:-${DEFAULT_RS_PUB_KEY:-}}"
        api_server="${API_SERVER:-${DEFAULT_API_SERVER:-}}"
        
        debug "var" "After defaults - tag" "$tag"
        debug "var" "After defaults - email" "$email"
        debug "var" "After defaults - customer" "$customer"
        debug "var" "After defaults - rendezvous_server" "$rendezvous_server"
        debug "var" "After defaults - api_server" "$api_server"
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

# 私有方法：处理 tag 时间戳
trigger_process_tag_timestamp() {
    local event_data="$1"
    
    # 从event_data中提取tag
    local tag=""
    if echo "$event_data" | jq -e '.inputs' > /dev/null 2>&1; then
        # workflow_dispatch事件
        tag=$(echo "$event_data" | jq -r '.inputs.tag // empty')
    else
        # issues事件，从环境变量中读取
        tag="$TAG"
    fi
    
    debug "log" "Processing tag timestamp for: $tag"
    
    # 如果tag已经包含时间戳，直接返回
    if [[ "$tag" =~ ^.*-[0-9]{8}-[0-9]{6}$ ]]; then
        debug "log" "Tag already contains timestamp"
        echo "$tag"
        return 0
    fi
    
    # 生成时间戳
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    local final_tag="${tag}-${timestamp}"
    
    debug "var" "Generated timestamp" "$timestamp"
    debug "var" "Final tag" "$final_tag"
    
    echo "$final_tag"
}

# 私有方法：生成最终JSON数据
trigger_generate_final_data() {
    local event_data="$1"
    local final_tag="$2"
    
    debug "log" "Generating final JSON data"
    
    # 从event_data中提取参数
    local tag=""
    local email=""
    local customer=""
    local customer_link=""
    local super_password=""
    local slogan=""
    local rendezvous_server=""
    local rs_pub_key=""
    local api_server=""
    
    if echo "$event_data" | jq -e '.inputs' > /dev/null 2>&1; then
        # workflow_dispatch事件
        debug "log" "Generating final data for workflow_dispatch event"
        tag=$(echo "$event_data" | jq -r '.inputs.tag // empty')
        email=$(echo "$event_data" | jq -r '.inputs.email // empty')
        customer=$(echo "$event_data" | jq -r '.inputs.customer // empty')
        customer_link=$(echo "$event_data" | jq -r '.inputs.customer_link // empty')
        super_password=$(echo "$event_data" | jq -r '.inputs.super_password // empty')
        slogan=$(echo "$event_data" | jq -r '.inputs.slogan // empty')
        rendezvous_server=$(echo "$event_data" | jq -r '.inputs.rendezvous_server // empty')
        rs_pub_key=$(echo "$event_data" | jq -r '.inputs.rs_pub_key // empty')
        api_server=$(echo "$event_data" | jq -r '.inputs.api_server // empty')
        
        debug "var" "Generate workflow dispatch - tag" "$tag"
        debug "var" "Generate workflow dispatch - email" "$email"
        debug "var" "Generate workflow dispatch - customer" "$customer"
        debug "var" "Generate workflow dispatch - rendezvous_server" "$rendezvous_server"
        debug "var" "Generate workflow dispatch - api_server" "$api_server"
    else
        # issues事件，从环境变量中读取
        debug "var" "Generate - TAG from env" "$TAG"
        debug "var" "Generate - EMAIL from env" "$EMAIL"
        debug "var" "Generate - CUSTOMER from env" "$CUSTOMER"
        debug "var" "Generate - RENDEZVOUS_SERVER from env" "$RENDEZVOUS_SERVER"
        debug "var" "Generate - API_SERVER from env" "$API_SERVER"
        
        tag="$TAG"
        email="$EMAIL"
        customer="$CUSTOMER"
        customer_link="$CUSTOMER_LINK"
        super_password="$SUPER_PASSWORD"
        slogan="$SLOGAN"
        rendezvous_server="$RENDEZVOUS_SERVER"
        rs_pub_key="$RS_PUB_KEY"
        api_server="$API_SERVER"
        
        debug "var" "Generate - final tag" "$tag"
        debug "var" "Generate - final email" "$email"
        debug "var" "Generate - final customer" "$customer"
        debug "var" "Generate - final rendezvous_server" "$rendezvous_server"
        debug "var" "Generate - final api_server" "$api_server"
    fi
    
    # 从event_data中提取build_id
    local build_id=""
    if echo "$event_data" | jq -e '.inputs' > /dev/null 2>&1; then
        # workflow_dispatch事件，使用run_id
        build_id="$GITHUB_RUN_ID"
    else
        # issues事件，使用issue number
        build_id=$(echo "$event_data" | jq -r '.issue.number // empty')
    fi
    
    # 确定触发类型
    local trigger_type=""
    if echo "$event_data" | jq -e '.inputs' > /dev/null 2>&1; then
        trigger_type="workflow_dispatch"
    else
        trigger_type="issue"
    fi
    
    debug "var" "Trigger type" "$trigger_type"
    
    # 生成JSON数据（包含build_id和trigger_type）
    local data=$(jq -c -n \
        --arg build_id "$build_id" \
        --arg tag "$final_tag" \
        --arg original_tag "$tag" \
        --arg email "$email" \
        --arg customer "$customer" \
        --arg customer_link "$customer_link" \
        --arg super_password "$super_password" \
        --arg slogan "$slogan" \
        --arg rendezvous_server "$rendezvous_server" \
        --arg rs_pub_key "$rs_pub_key" \
        --arg api_server "$api_server" \
        --arg trigger_type "$trigger_type" \
        '{build_id: $build_id, tag: $tag, original_tag: $original_tag, email: $email, customer: $customer, customer_link: $customer_link, super_password: $super_password, slogan: $slogan, rendezvous_server: $rendezvous_server, rs_pub_key: $rs_pub_key, api_server: $api_server, trigger_type: $trigger_type}')
    
    debug "var" "Generated JSON data" "$data"
    echo "$data"
}

# 私有方法：更新 issue 内容
trigger_update_issue_content() {
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
trigger_clean_issue_content() {
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
trigger_output_to_github() {
    local final_data="$1"
    
    debug "log" "Outputting to GitHub Actions"
    
    # 从final_data中提取build_id
    local build_id=$(echo "$final_data" | jq -r '.build_id // empty')
    
    # 调试：输出详细信息
    debug "var" "Final data to output" "$final_data"
    debug "var" "Build ID extracted" "$build_id"
    debug "var" "GITHUB_OUTPUT file" "$GITHUB_OUTPUT"
    
    # 使用GitHub Actions的fromJSON函数从final_data中提取字段
    # 这些变量将在工作流中通过fromJSON设置
    echo "data=$final_data" >> $GITHUB_OUTPUT
    echo "build_id=$build_id" >> $GITHUB_OUTPUT
    
    # 调试：验证输出是否成功
    debug "log" "Output file contents:"
    cat "$GITHUB_OUTPUT" | while IFS= read -r line; do
        debug "log" "  $line"
    done
    
    debug "success" "Output written to GitHub Actions"
    
    # 显示输出信息
    debug "var" "Trigger output: $final_data"
}

# 主 Trigger 管理函数 - 供工作流调用
# 参数说明：
#   operation: 操作类型
#   arg1-arg4: 根据操作类型传递的不同参数
trigger_manager() {
    local operation="$1"
    local arg1="$2"
    local arg2="$3"
    local arg3="$4"
    local arg4="$5"
    
    case "$operation" in
        # 从 workflow_dispatch 事件中提取参数
        # arg1: event_data (GitHub事件数据)
        "extract-workflow-dispatch")
            trigger_extract_workflow_dispatch_params "$arg1"
            ;;
        
        # 从 issue 事件中提取参数
        # arg1: event_data (GitHub事件数据)
        "extract-issue")
            trigger_extract_issue_params "$arg1"
            ;;
        
        # 应用默认值（使用secrets兜底）
        # arg1: event_data (GitHub事件数据)
        "apply-defaults")
            trigger_apply_default_values "$arg1"
            ;;
        
        # 处理tag时间戳
        # arg1: event_data (GitHub事件数据)
        "process-tag")
            trigger_process_tag_timestamp "$arg1"
            ;;
        
        # 生成最终JSON数据
        # arg1: event_data (GitHub事件数据)
        # arg2: final_tag (处理后的tag)
        "generate-data")
            trigger_generate_final_data "$arg1" "$arg2"
            ;;
        
        # 更新issue内容
        # arg1: issue_number (issue编号)
        # arg2: cleaned_body (清理后的issue内容)
        "update-issue")
            trigger_update_issue_content "$arg1" "$arg2"
            ;;
        
        # 清理issue内容（移除敏感信息）
        # arg1: final_tag (最终tag)
        # arg2: original_tag (原始tag)
        # arg3: customer (客户名称)
        # arg4: slogan (标语)
        "clean-issue")
            trigger_clean_issue_content "$arg1" "$arg2" "$arg3" "$arg4"
            ;;
        
        # 输出到GitHub Actions
        # arg1: final_data (最终JSON数据)
        "output-to-github")
            trigger_output_to_github "$arg1"
            ;;
        
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
