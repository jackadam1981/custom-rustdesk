#!/bin/bash
# Issue 管理器脚本
# 这个文件统一管理所有 issue 相关的操作
# 加载依赖脚本
source .github/workflows/scripts/issue-templates.sh

# 获取 issue 内容
get_issue_content() {
    local issue_number="$1"
    
    curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number"
}

# 更新 issue 内容
update_issue_content() {
    local issue_number="$1"
    local new_body="$2"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$new_body" '{"body": $body}')
    
    # 使用GitHub API更新issue
    curl -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number \
        -d "$json_payload"
}

# 添加 issue 评论
add_issue_comment() {
    local issue_number="$1"
    local comment="$2"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$comment" '{"body": $body}')
    
    # 使用GitHub API添加评论
    curl -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/comments \
        -d "$json_payload"
}

# 获取 issue 评论列表
get_issue_comments() {
    local issue_number="$1"
    
    curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/comments"
}

# 检查 issue 是否存在
check_issue_exists() {
    local issue_number="$1"
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number")
    
    # 检查是否返回错误信息
    if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
        return 1
    else
        return 0
    fi
}

# 关闭 issue
close_issue() {
    local issue_number="$1"
    local reason="${2:-completed}"
    
    local json_payload=$(jq -n --arg state "closed" --arg reason "$reason" '{"state": $state, "state_reason": $reason}')
    
    curl -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number \
        -d "$json_payload"
}

# 重新打开 issue
reopen_issue() {
    local issue_number="$1"
    
    local json_payload=$(jq -n --arg state "open" '{"state": $state}')
    
    curl -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number \
        -d "$json_payload"
}

# 添加 issue 标签
add_issue_labels() {
    local issue_number="$1"
    shift
    local labels=("$@")
    
    # 将标签数组转换为JSON数组
    local labels_json=$(printf '%s\n' "${labels[@]}" | jq -R . | jq -s .)
    local json_payload=$(jq -n --argjson labels "$labels_json" '{"labels": $labels}')
    
    curl -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/labels \
        -d "$json_payload"
}

# 移除 issue 标签
remove_issue_label() {
    local issue_number="$1"
    local label="$2"
    
    curl -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/labels/$label"
}

# 设置 issue 标签（替换所有现有标签）
set_issue_labels() {
    local issue_number="$1"
    shift
    local labels=("$@")
    
    # 将标签数组转换为JSON数组
    local labels_json=$(printf '%s\n' "${labels[@]}" | jq -R . | jq -s .)
    local json_payload=$(jq -n --argjson labels "$labels_json" '{"labels": $labels}')
    
    curl -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/labels \
        -d "$json_payload"
}

# 获取 issue 标签
get_issue_labels() {
    local issue_number="$1"
    
    curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/labels"
}

# 分配 issue 给用户
assign_issue() {
    local issue_number="$1"
    local assignee="$2"
    
    local json_payload=$(jq -n --arg assignee "$assignee" '{"assignees": [$assignee]}')
    
    curl -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/assignees \
        -d "$json_payload"
}

# 取消分配 issue
unassign_issue() {
    local issue_number="$1"
    local assignee="$2"
    
    local json_payload=$(jq -n --arg assignee "$assignee" '{"assignees": [$assignee]}')
    
    curl -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/assignees \
        -d "$json_payload"
}

# 创建 issue
create_issue() {
    local title="$1"
    local body="$2"
    local labels="${3:-}"
    local assignees="${4:-}"
    
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
    
    curl -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues \
        -d "$json_payload"
}

# 搜索 issues
search_issues() {
    local query="$1"
    local per_page="${2:-30}"
    local page="${3:-1}"
    
    # URL编码查询参数
    local encoded_query=$(echo "$query" | sed 's/ /+/g')
    
    curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/search/issues?q=$encoded_query&per_page=$per_page&page=$page"
}

# 获取仓库的所有 issues
get_repository_issues() {
    local state="${1:-open}"
    local per_page="${2:-30}"
    local page="${3:-1}"
    
    curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues?state=$state&per_page=$per_page&page=$page"
}

# 检查用户是否有管理员权限
check_admin_permission() {
    local username="$1"
    
    # 检查是否为仓库所有者
    if [ "$username" = "$GITHUB_REPOSITORY_OWNER" ]; then
        return 0
    fi
    
    # 检查是否为协作者且有管理员权限
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/collaborators/$username")
    
    local permission=$(echo "$response" | jq -r '.permissions.admin // false')
    
    if [ "$permission" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# 获取 issue 创建者
get_issue_author() {
    local issue_number="$1"
    
    local issue_content=$(get_issue_content "$issue_number")
    echo "$issue_content" | jq -r '.user.login // empty'
}

# 获取 issue 标题
get_issue_title() {
    local issue_number="$1"
    
    local issue_content=$(get_issue_content "$issue_number")
    echo "$issue_content" | jq -r '.title // empty'
}

# 获取 issue 状态
get_issue_state() {
    local issue_number="$1"
    
    local issue_content=$(get_issue_content "$issue_number")
    echo "$issue_content" | jq -r '.state // empty'
}

# 获取 issue 创建时间
get_issue_created_at() {
    local issue_number="$1"
    
    local issue_content=$(get_issue_content "$issue_number")
    echo "$issue_content" | jq -r '.created_at // empty'
}

# 获取 issue 更新时间
get_issue_updated_at() {
    local issue_number="$1"
    
    local issue_content=$(get_issue_content "$issue_number")
    echo "$issue_content" | jq -r '.updated_at // empty'
}

# 获取 issue 关闭时间
get_issue_closed_at() {
    local issue_number="$1"
    
    local issue_content=$(get_issue_content "$issue_number")
    echo "$issue_content" | jq -r '.closed_at // empty'
}

# 批量删除 issues
batch_delete_issues() {
    local issue_numbers=("$@")
    local dry_run="${dry_run:-false}"
    
    echo "Starting batch delete of ${#issue_numbers[@]} issues..."
    
    for issue_number in "${issue_numbers[@]}"; do
        if [ "$dry_run" = "true" ]; then
            echo "DRY RUN: Would delete issue #$issue_number"
        else
            echo "Deleting issue #$issue_number..."
            close_issue "$issue_number" "not_planned"
        fi
    done
    
    echo "Batch delete completed"
}

# 批量更新 issues
batch_update_issues() {
    local issue_numbers=("$@")
    local new_body="$2"
    local dry_run="${dry_run:-false}"
    
    echo "Starting batch update of ${#issue_numbers[@]} issues..."
    
    for issue_number in "${issue_numbers[@]}"; do
        if [ "$dry_run" = "true" ]; then
            echo "DRY RUN: Would update issue #$issue_number"
        else
            echo "Updating issue #$issue_number..."
            update_issue_content "$issue_number" "$new_body"
        fi
    done
    
    echo "Batch update completed"
}

# 获取 issue 统计信息
get_issue_stats() {
    local state="${1:-all}"
    
    local issues=$(get_repository_issues "$state" 100 1)
    local total_count=$(echo "$issues" | jq '. | length')
    local open_count=$(echo "$issues" | jq '[.[] | select(.state == "open")] | length')
    local closed_count=$(echo "$issues" | jq '[.[] | select(.state == "closed")] | length')
    
    echo "Total issues: $total_count"
    echo "Open issues: $open_count"
    echo "Closed issues: $closed_count"
}

# 检查 issue 是否被锁定
is_issue_locked() {
    local issue_number="$1"
    
    local issue_content=$(get_issue_content "$issue_number")
    local locked=$(echo "$issue_content" | jq -r '.locked // false')
    
    if [ "$locked" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# 锁定 issue
lock_issue() {
    local issue_number="$1"
    local reason="${2:-resolved}"
    
    local json_payload=$(jq -n --arg reason "$reason" '{"lock_reason": $reason}')
    
    curl -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/lock \
        -d "$json_payload"
}

# 解锁 issue
unlock_issue() {
    local issue_number="$1"
    
    curl -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/lock
} 
