#!/bin/bash
# Issue 管理器脚本 - 伪面向对象模式
# 这个文件统一管理所有 issue 相关的操作，采用简单的伪面向对象设计

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh

# Issue 管理器 - 伪面向对象实现
# 使用全局变量存储实例状态

# 私有属性（全局变量）
_ISSUE_MANAGER_CURRENT_ISSUE_NUMBER=""
_ISSUE_MANAGER_CURRENT_ISSUE_DATA=""
_ISSUE_MANAGER_CURRENT_USER=""
_ISSUE_MANAGER_REPOSITORY=""

# 构造函数
issue_manager_init() {
    local issue_number="${1:-}"
    local current_user="${2:-}"
    
    _ISSUE_MANAGER_CURRENT_ISSUE_NUMBER="$issue_number"
    _ISSUE_MANAGER_CURRENT_USER="$current_user"
    _ISSUE_MANAGER_REPOSITORY="$GITHUB_REPOSITORY"
    
    debug "log" "Initializing issue manager"
    debug "var" "Issue number" "$_ISSUE_MANAGER_CURRENT_ISSUE_NUMBER"
    debug "var" "Current user" "$_ISSUE_MANAGER_CURRENT_USER"
    debug "var" "Repository" "$_ISSUE_MANAGER_REPOSITORY"
    
    # 如果有issue编号，加载issue数据
    if [ -n "$_ISSUE_MANAGER_CURRENT_ISSUE_NUMBER" ]; then
        issue_manager_load_issue_data
    fi
}

# 私有方法：加载issue数据
issue_manager_load_issue_data() {
    debug "log" "Loading issue data for issue #$_ISSUE_MANAGER_CURRENT_ISSUE_NUMBER"
    
    _ISSUE_MANAGER_CURRENT_ISSUE_DATA=$(issue_manager_get_content "$_ISSUE_MANAGER_CURRENT_ISSUE_NUMBER")
    
    if [ $? -eq 0 ]; then
        debug "success" "Issue data loaded successfully"
    else
        debug "error" "Failed to load issue data"
    fi
}

# 私有方法：获取 issue 内容
issue_manager_get_content() {
    local issue_number="$1"
    
    debug "log" "Fetching content for issue #$issue_number"
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number")
    
    if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
        debug "error" "Issue #$issue_number not found"
        return 1
    fi
    
    echo "$response"
}

# 私有方法：更新 issue 内容
issue_manager_update_content() {
    local issue_number="$1"
    local new_body="$2"
    
    debug "log" "Updating content for issue #$issue_number"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$new_body" '{"body": $body}')
    
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

# 公共方法：添加 issue 评论
issue_manager_add_comment() {
    local issue_number="$1"
    local comment="$2"
    
    debug "log" "Adding comment to issue #$issue_number"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$comment" '{"body": $body}')
    
    # 使用GitHub API添加评论
    local response=$(curl -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/comments \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Comment added to issue #$issue_number successfully"
        return 0
    else
        debug "error" "Failed to add comment to issue #$issue_number"
        return 1
    fi
}

# 公共方法：获取 issue 评论列表
issue_manager_get_comments() {
    local issue_number="$1"
    
    debug "log" "Fetching comments for issue #$issue_number"
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/comments")
    
    echo "$response"
}

# 公共方法：检查 issue 是否存在
issue_manager_exists() {
    local issue_number="$1"
    
    debug "log" "Checking if issue #$issue_number exists"
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number")
    
    # 检查是否返回错误信息
    if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
        debug "log" "Issue #$issue_number does not exist"
        return 1
    else
        debug "log" "Issue #$issue_number exists"
        return 0
    fi
}

# 公共方法：关闭 issue
issue_manager_close() {
    local issue_number="$1"
    local reason="${2:-completed}"
    
    debug "log" "Closing issue #$issue_number with reason: $reason"
    
    local json_payload=$(jq -n --arg state "closed" --arg reason "$reason" '{"state": $state, "state_reason": $reason}')
    
    local response=$(curl -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Issue #$issue_number closed successfully"
        return 0
    else
        debug "error" "Failed to close issue #$issue_number"
        return 1
    fi
}

# 公共方法：重新打开 issue
issue_manager_reopen() {
    local issue_number="$1"
    
    debug "log" "Reopening issue #$issue_number"
    
    local json_payload=$(jq -n --arg state "open" '{"state": $state}')
    
    local response=$(curl -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Issue #$issue_number reopened successfully"
        return 0
    else
        debug "error" "Failed to reopen issue #$issue_number"
        return 1
    fi
}

# 公共方法：添加 issue 标签
issue_manager_add_labels() {
    local issue_number="$1"
    shift
    local labels=("$@")
    
    debug "log" "Adding labels to issue #$issue_number: ${labels[*]}"
    
    # 将标签数组转换为JSON数组
    local labels_json=$(printf '%s\n' "${labels[@]}" | jq -R . | jq -s .)
    local json_payload=$(jq -n --argjson labels "$labels_json" '{"labels": $labels}')
    
    local response=$(curl -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/labels \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Labels added to issue #$issue_number successfully"
        return 0
    else
        debug "error" "Failed to add labels to issue #$issue_number"
        return 1
    fi
}

# 公共方法：移除 issue 标签
issue_manager_remove_label() {
    local issue_number="$1"
    local label="$2"
    
    debug "log" "Removing label '$label' from issue #$issue_number"
    
    local response=$(curl -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/labels/$label")
    
    if [ $? -eq 0 ]; then
        debug "success" "Label '$label' removed from issue #$issue_number successfully"
        return 0
    else
        debug "error" "Failed to remove label '$label' from issue #$issue_number"
        return 1
    fi
}

# 公共方法：设置 issue 标签（替换所有现有标签）
issue_manager_set_labels() {
    local issue_number="$1"
    shift
    local labels=("$@")
    
    debug "log" "Setting labels for issue #$issue_number: ${labels[*]}"
    
    # 将标签数组转换为JSON数组
    local labels_json=$(printf '%s\n' "${labels[@]}" | jq -R . | jq -s .)
    local json_payload=$(jq -n --argjson labels "$labels_json" '{"labels": $labels}')
    
    local response=$(curl -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/labels \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Labels set for issue #$issue_number successfully"
        return 0
    else
        debug "error" "Failed to set labels for issue #$issue_number"
        return 1
    fi
}

# 公共方法：获取 issue 标签
issue_manager_get_labels() {
    local issue_number="$1"
    
    debug "log" "Fetching labels for issue #$issue_number"
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/labels")
    
    echo "$response"
}

# 公共方法：分配 issue 给用户
issue_manager_assign() {
    local issue_number="$1"
    local assignee="$2"
    
    debug "log" "Assigning issue #$issue_number to user: $assignee"
    
    local json_payload=$(jq -n --arg assignee "$assignee" '{"assignees": [$assignee]}')
    
    local response=$(curl -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/assignees \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Issue #$issue_number assigned to $assignee successfully"
        return 0
    else
        debug "error" "Failed to assign issue #$issue_number to $assignee"
        return 1
    fi
}

# 公共方法：取消分配 issue
issue_manager_unassign() {
    local issue_number="$1"
    local assignee="$2"
    
    debug "log" "Unassigning issue #$issue_number from user: $assignee"
    
    local json_payload=$(jq -n --arg assignee "$assignee" '{"assignees": [$assignee]}')
    
    local response=$(curl -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/assignees \
        -d "$json_payload")
    
    if [ $? -eq 0 ]; then
        debug "success" "Issue #$issue_number unassigned from $assignee successfully"
        return 0
    else
        debug "error" "Failed to unassign issue #$issue_number from $assignee"
        return 1
    fi
}

# 公共方法：创建 issue
issue_manager_create() {
    local title="$1"
    local body="$2"
    local labels="${3:-}"
    local assignees="${4:-}"
    
    debug "log" "Creating new issue with title: $title"
    
    local json_payload=$(jq -n \
        --arg title "$title" \
        --arg body "$body" \
        --arg labels "$labels" \
        --arg assignees "$assignees" \
        '{
            title: $title,
            body: $body,
            labels: ($labels | split(",") | map(select(length > 0))),
            assignees: ($assignees | split(",") | map(select(length > 0)))
        }')
    
    local response=$(curl -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        local new_issue_number=$(echo "$response" | jq -r '.number')
        debug "success" "Issue #$new_issue_number created successfully"
        echo "$new_issue_number"
        return 0
    else
        debug "error" "Failed to create issue"
        return 1
    fi
}

# 公共方法：搜索 issues
issue_manager_search() {
    local query="$1"
    local per_page="${2:-30}"
    local page="${3:-1}"
    
    debug "log" "Searching issues with query: $query"
    
    # URL编码查询参数
    local encoded_query=$(echo "$query" | sed 's/ /+/g')
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/search/issues?q=$encoded_query&per_page=$per_page&page=$page")
    
    echo "$response"
}

# 公共方法：获取仓库的所有 issues
issue_manager_get_repository_issues() {
    local state="${1:-open}"
    local per_page="${2:-30}"
    local page="${3:-1}"
    
    debug "log" "Fetching repository issues (state: $state, per_page: $per_page, page: $page)"
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues?state=$state&per_page=$per_page&page=$page")
    
    echo "$response"
}

# 公共方法：检查用户是否有管理员权限
issue_manager_check_admin_permission() {
    local username="$1"
    
    debug "log" "Checking admin permission for user: $username"
    
    # 检查是否为仓库所有者
    if [ "$username" = "$GITHUB_REPOSITORY_OWNER" ]; then
        debug "log" "User $username is repository owner"
        return 0
    fi
    
    # 检查是否为协作者且有管理员权限
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/collaborators/$username")
    
    local permission=$(echo "$response" | jq -r '.permissions.admin // false')
    
    if [ "$permission" = "true" ]; then
        debug "log" "User $username has admin permission"
        return 0
    else
        debug "log" "User $username does not have admin permission"
        return 1
    fi
}

# 公共方法：获取 issue 属性
issue_manager_get_property() {
    local issue_number="$1"
    local property="$2"
    
    debug "log" "Getting property '$property' for issue #$issue_number"
    
    local issue_content=$(issue_manager_get_content "$issue_number")
    
    case "$property" in
        "author"|"user")
            echo "$issue_content" | jq -r '.user.login // empty'
            ;;
        "title")
            echo "$issue_content" | jq -r '.title // empty'
            ;;
        "state")
    echo "$issue_content" | jq -r '.state // empty'
            ;;
        "created_at")
    echo "$issue_content" | jq -r '.created_at // empty'
            ;;
        "updated_at")
    echo "$issue_content" | jq -r '.updated_at // empty'
            ;;
        "closed_at")
    echo "$issue_content" | jq -r '.closed_at // empty'
            ;;
        "body")
            echo "$issue_content" | jq -r '.body // empty'
            ;;
        "locked")
            echo "$issue_content" | jq -r '.locked // false'
            ;;
        *)
            debug "error" "Unknown property: $property"
            return 1
            ;;
    esac
}

# 公共方法：批量操作
issue_manager_batch_operation() {
    local operation="$1"
    local issue_numbers=("$@")
    shift
    local dry_run="${dry_run:-false}"
    
    debug "log" "Starting batch $operation for ${#issue_numbers[@]} issues"
    
    for issue_number in "${issue_numbers[@]}"; do
        if [ "$dry_run" = "true" ]; then
            debug "log" "DRY RUN: Would $operation issue #$issue_number"
        else
            debug "log" "Performing $operation on issue #$issue_number"
            case "$operation" in
                "delete"|"close")
                    issue_manager_close "$issue_number" "not_planned"
                    ;;
                "update")
    local new_body="$2"
                    issue_manager_update_content "$issue_number" "$new_body"
                    ;;
                *)
                    debug "error" "Unknown batch operation: $operation"
                    return 1
                    ;;
            esac
        fi
    done
    
    debug "success" "Batch $operation completed"
}

# 公共方法：获取 issue 统计信息
issue_manager_get_stats() {
    local state="${1:-all}"
    
    debug "log" "Getting issue statistics (state: $state)"
    
    local issues=$(issue_manager_get_repository_issues "$state" 100 1)
    local total_count=$(echo "$issues" | jq '. | length')
    local open_count=$(echo "$issues" | jq '[.[] | select(.state == "open")] | length')
    local closed_count=$(echo "$issues" | jq '[.[] | select(.state == "closed")] | length')
    
    echo "Total issues: $total_count"
    echo "Open issues: $open_count"
    echo "Closed issues: $closed_count"
}

# 公共方法：锁定 issue
issue_manager_lock() {
    local issue_number="$1"
    local reason="${2:-resolved}"
    
    debug "log" "Locking issue #$issue_number with reason: $reason"
    
    local json_payload=$(jq -n --arg reason "$reason" '{"lock_reason": $reason}')
    
    local response=$(curl -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/lock \
        -d "$json_payload")
    
    if [ $? -eq 0 ]; then
        debug "success" "Issue #$issue_number locked successfully"
        return 0
    else
        debug "error" "Failed to lock issue #$issue_number"
        return 1
    fi
}

# 公共方法：解锁 issue
issue_manager_unlock() {
    local issue_number="$1"
    
    debug "log" "Unlocking issue #$issue_number"
    
    local response=$(curl -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/lock)
    
    if [ $? -eq 0 ]; then
        debug "success" "Issue #$issue_number unlocked successfully"
        return 0
    else
        debug "error" "Failed to unlock issue #$issue_number"
        return 1
    fi
}

# 主 Issue 管理函数 - 供工作流调用
issue_manager() {
    local operation="$1"
    local issue_number="${2:-}"
    local current_user="${3:-}"
    shift 3
    
    # 初始化 Issue 管理器
    issue_manager_init "$issue_number" "$current_user"
    
    case "$operation" in
        "get-content")
            issue_manager_get_content "$issue_number"
            ;;
        "update-content")
            local new_body="$1"
            issue_manager_update_content "$issue_number" "$new_body"
            ;;
        "add-comment")
            local comment="$1"
            issue_manager_add_comment "$issue_number" "$comment"
            ;;
        "get-comments")
            issue_manager_get_comments "$issue_number"
            ;;
        "exists")
            issue_manager_exists "$issue_number"
            ;;
        "close")
            local reason="${1:-completed}"
            issue_manager_close "$issue_number" "$reason"
            ;;
        "reopen")
            issue_manager_reopen "$issue_number"
            ;;
        "add-labels")
            issue_manager_add_labels "$issue_number" "$@"
            ;;
        "remove-label")
            local label="$1"
            issue_manager_remove_label "$issue_number" "$label"
            ;;
        "set-labels")
            issue_manager_set_labels "$issue_number" "$@"
            ;;
        "get-labels")
            issue_manager_get_labels "$issue_number"
            ;;
        "assign")
            local assignee="$1"
            issue_manager_assign "$issue_number" "$assignee"
            ;;
        "unassign")
            local assignee="$1"
            issue_manager_unassign "$issue_number" "$assignee"
            ;;
        "create")
            local title="$1"
            local body="$2"
            local labels="${3:-}"
            local assignees="${4:-}"
            issue_manager_create "$title" "$body" "$labels" "$assignees"
            ;;
        "search")
            local query="$1"
            local per_page="${2:-30}"
            local page="${3:-1}"
            issue_manager_search "$query" "$per_page" "$page"
            ;;
        "get-repository-issues")
            local state="${1:-open}"
            local per_page="${2:-30}"
            local page="${3:-1}"
            issue_manager_get_repository_issues "$state" "$per_page" "$page"
            ;;
        "check-admin")
            local username="$1"
            issue_manager_check_admin_permission "$username"
            ;;
        "get-property")
            local property="$1"
            issue_manager_get_property "$issue_number" "$property"
            ;;
        "batch-operation")
            local batch_op="$1"
            shift
            issue_manager_batch_operation "$batch_op" "$@"
            ;;
        "get-stats")
            local state="${1:-all}"
            issue_manager_get_stats "$state"
            ;;
        "lock")
            local reason="${1:-resolved}"
            issue_manager_lock "$issue_number" "$reason"
            ;;
        "unlock")
            issue_manager_unlock "$issue_number"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
}

# 兼容性函数 - 保持向后兼容
get_issue_content() {
    issue_manager "get-content" "$1" "" ""
}

update_issue_content() {
    issue_manager "update-content" "$1" "" "$2"
}

add_issue_comment() {
    issue_manager "add-comment" "$1" "" "$2"
}

get_issue_comments() {
    issue_manager "get-comments" "$1" "" ""
}

check_issue_exists() {
    issue_manager "exists" "$1" "" ""
}

close_issue() {
    local reason="${2:-completed}"
    issue_manager "close" "$1" "" "$reason"
}

reopen_issue() {
    issue_manager "reopen" "$1" "" ""
}

add_issue_labels() {
    local issue_number="$1"
    shift
    issue_manager "add-labels" "$issue_number" "" "$@"
}

remove_issue_label() {
    issue_manager "remove-label" "$1" "" "$2"
}

set_issue_labels() {
    local issue_number="$1"
    shift
    issue_manager "set-labels" "$issue_number" "" "$@"
}

get_issue_labels() {
    issue_manager "get-labels" "$1" "" ""
}

assign_issue() {
    issue_manager "assign" "$1" "" "$2"
}

unassign_issue() {
    issue_manager "unassign" "$1" "" "$2"
}

create_issue() {
    issue_manager "create" "" "" "$1" "$2" "$3" "$4"
}

search_issues() {
    issue_manager "search" "" "" "$1" "$2" "$3"
}

get_repository_issues() {
    issue_manager "get-repository-issues" "" "" "$1" "$2" "$3"
}

check_admin_permission() {
    issue_manager "check-admin" "" "" "$1"
}

get_issue_author() {
    issue_manager "get-property" "$1" "" "author"
}

get_issue_title() {
    issue_manager "get-property" "$1" "" "title"
}

get_issue_state() {
    issue_manager "get-property" "$1" "" "state"
}

get_issue_created_at() {
    issue_manager "get-property" "$1" "" "created_at"
}

get_issue_updated_at() {
    issue_manager "get-property" "$1" "" "updated_at"
}

get_issue_closed_at() {
    issue_manager "get-property" "$1" "" "closed_at"
}

batch_delete_issues() {
    local issue_numbers=("$@")
    issue_manager "batch-operation" "" "" "delete" "${issue_numbers[@]}"
}

batch_update_issues() {
    local issue_numbers=("$@")
    local new_body="$2"
    issue_manager "batch-operation" "" "" "update" "${issue_numbers[@]}" "$new_body"
}

get_issue_stats() {
    issue_manager "get-stats" "" "" "$1"
}

is_issue_locked() {
    local locked=$(issue_manager "get-property" "$1" "" "locked")
    if [ "$locked" = "true" ]; then
        return 0
    else
        return 1
    fi
}

lock_issue() {
    issue_manager "lock" "$1" "" "$2"
}

unlock_issue() {
    issue_manager "unlock" "$1" "" ""
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <operation> [issue_number] [current_user] [additional_params...]"
        echo "Operations: get-content, update-content, add-comment, get-comments, exists, close, reopen,"
        echo "           add-labels, remove-label, set-labels, get-labels, assign, unassign, create,"
        echo "           search, get-repository-issues, check-admin, get-property, batch-operation,"
        echo "           get-stats, lock, unlock"
        exit 1
    fi
    
    operation="$1"
    issue_number="${2:-}"
    current_user="${3:-}"
    shift 3
    
    issue_manager "$operation" "$issue_number" "$current_user" "$@"
fi
