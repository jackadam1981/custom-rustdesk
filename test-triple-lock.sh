#!/bin/bash
# 三锁架构专门测试脚本
# 专注于测试三锁架构的并发安全性、锁状态管理和错误恢复

set -euo pipefail

# 脚本信息
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
  echo -e "${PURPLE}[TEST]${NC} $1"
}

# 全局变量
REPO_INFO=""
REPO_NAME=""
REPO_OWNER=""
DEFAULT_BRANCH=""
QUEUE_ISSUE_NUMBER="1"
TEST_RESULTS=()

# 检查GitHub CLI
check_gh_cli() {
  if ! command -v gh &>/dev/null; then
    log_error "GitHub CLI (gh) 未安装"
    exit 1
  fi

  if ! gh auth status &>/dev/null; then
    log_error "GitHub CLI 未认证，请运行: gh auth login"
    exit 1
  fi

  log_success "GitHub CLI 检查通过"
}

# 获取仓库信息
get_repo_info() {
  log_info "获取仓库信息..."
  REPO_INFO=$(gh repo view --json name,owner,defaultBranchRef)
  REPO_NAME=$(echo "$REPO_INFO" | jq -r '.name')
  REPO_OWNER=$(echo "$REPO_INFO" | jq -r '.owner.login')
  DEFAULT_BRANCH=$(echo "$REPO_INFO" | jq -r '.defaultBranchRef.name')

  log_info "仓库: $REPO_OWNER/$REPO_NAME"
  log_info "默认分支: $DEFAULT_BRANCH"
}

# 检查队列管理Issue是否存在
check_queue_issue() {
  log_info "检查队列管理Issue #$QUEUE_ISSUE_NUMBER..."

  if gh issue view "$QUEUE_ISSUE_NUMBER" &>/dev/null; then
    log_success "队列管理Issue #$QUEUE_ISSUE_NUMBER 存在"
    return 0
  else
    log_warning "队列管理Issue #$QUEUE_ISSUE_NUMBER 不存在，正在创建..."
    create_queue_issue
    return 0
  fi
}

# 创建队列管理Issue
create_queue_issue() {
  log_info "创建队列管理Issue..."

  local current_time=$(date '+%Y-%m-%d %H:%M:%S')
  local default_queue_data='{"queue":[],"issue_locked_by":null,"queue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"queue_lock_version":1,"build_lock_version":1,"version":1}'

  local body="# 构建队列管理

**最后更新时间：** $current_time

### 三锁状态
- **Issue 锁状态：** 空闲 🔓
- **队列锁状态：** 空闲 🔓
- **构建锁状态：** 空闲 🔓

### 锁持有者
- **Issue 锁持有者：** 无
- **队列锁持有者：** 无
- **构建锁持有者：** 无

### 构建队列
- **当前数量：** 0/5
- **Issue触发：** 0/3
- **手动触发：** 0/5

---

### 队列数据
\`\`\`json
$default_queue_data
\`\`\`"

  gh issue create \
    --title "构建队列管理" \
    --body "$body" \
    --assignee "$REPO_OWNER"

  log_success "队列管理Issue创建完成"
}

# 获取队列状态
get_queue_status() {
  log_info "获取队列状态..."

  local issue_content=$(gh issue view "$QUEUE_ISSUE_NUMBER" --json body)
  local body=$(echo "$issue_content" | jq -r '.body')

  # 提取JSON数据
  local json_data=$(echo "$body" | sed -n '/```json/,/```/p' | sed '1d;$d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [ -n "$json_data" ] && echo "$json_data" | jq . >/dev/null 2>&1; then
    echo "$json_data"
  else
    log_error "无法解析队列数据"
    return 1
  fi
}

# 显示锁状态
show_lock_status() {
  local queue_data="$1"
  local test_name="${2:-当前状态}"

  local issue_locked_by=$(echo "$queue_data" | jq -r '.issue_locked_by // "无"')
  local queue_locked_by=$(echo "$queue_data" | jq -r '.queue_locked_by // "无"')
  local build_locked_by=$(echo "$queue_data" | jq -r '.build_locked_by // "无"')
  local queue_length=$(echo "$queue_data" | jq '.queue | length // 0')
  local issue_lock_version=$(echo "$queue_data" | jq -r '.issue_lock_version // 1')
  local queue_lock_version=$(echo "$queue_data" | jq -r '.queue_lock_version // 1')
  local build_lock_version=$(echo "$queue_data" | jq -r '.build_lock_version // 1')

  echo
  echo "=== $test_name ==="
  echo "Issue 锁: $issue_locked_by (版本: $issue_lock_version)"
  echo "队列锁: $queue_locked_by (版本: $queue_lock_version)"
  echo "构建锁: $build_locked_by (版本: $build_lock_version)"
  echo "队列长度: $queue_length"
  echo
}

# 手动触发工作流
trigger_manual_workflow() {
  local customer_name="$1"
  local tag_name="$2"

  log_info "手动触发工作流: $customer_name - $tag_name"

  local customer_link="https://$customer_name.com"
  local slogan="Manual Trigger for $customer_name"
  local super_password="manual123"
  local rendezvous_server="https://$customer_name.server.com"
  local rs_pub_key="manual_rs_pub_key_$(date +%s)_$RANDOM"
  local api_server="https://$customer_name.server.com/api"

  # 手动触发工作流
  gh workflow run CustomBuildRustdesk.yml \
    --ref "$DEFAULT_BRANCH" \
    --field tag="$tag_name" \
    --field customer="$customer_name" \
    --field customer_link="$customer_link" \
    --field slogan="$slogan" \
    --field super_password="$super_password" \
    --field rendezvous_server="$rendezvous_server" \
    --field rs_pub_key="$rs_pub_key" \
    --field api_server="$api_server" \
    --field email="test@example.com"

  # 获取最新触发的工作流信息
  sleep 3 # 等待工作流创建
  local workflow_result=$(gh run list --limit 1 --json id,url)
  local run_id=$(echo "$workflow_result" | jq -r '.[0].id')
  local run_url=$(echo "$workflow_result" | jq -r '.[0].url')

  log_success "手动触发工作流: Run ID $run_id"
  log_info "工作流URL: $run_url"

  echo "$run_id"
}

# 测试1: 并发构建测试
test_concurrent_builds() {
  log_test "=== 测试1: 并发构建测试 ==="
  log_info "同时触发5个构建，测试三锁架构的并发安全性"

  local test_count=5
  local pids=()
  local run_ids=()

  # 记录开始时间
  local start_time=$(date +%s)

  for i in $(seq 1 $test_count); do
    local customer_name="ConcurrentClient$i"
    local tag_name="v1.0.0-concurrent-$i"

    log_info "启动并发构建 $i: $customer_name - $tag_name"

    # 后台触发工作流
    (
      local run_id=$(trigger_manual_workflow "$customer_name" "$tag_name")
      echo "$run_id" >"/tmp/concurrent_run_$i.txt"
    ) &

    pids+=($!)
  done

  # 等待所有后台进程完成
  log_info "等待所有并发构建完成..."
  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  # 收集所有run_id
  for i in $(seq 1 $test_count); do
    if [ -f "/tmp/concurrent_run_$i.txt" ]; then
      local run_id=$(cat "/tmp/concurrent_run_$i.txt")
      run_ids+=("$run_id")
      rm "/tmp/concurrent_run_$i.txt"
    fi
  done

  # 记录结束时间
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))

  log_success "并发测试完成，耗时: ${duration}秒"
  log_info "触发的Run IDs: ${run_ids[*]}"

  # 等待一段时间后检查队列状态
  sleep 15
  local status=$(get_queue_status)
  show_lock_status "$status" "并发测试后状态"

  TEST_RESULTS+=("concurrent|$test_count|${duration}s|${run_ids[*]}")
}

# 测试2: 锁竞争测试
test_lock_contention() {
  log_test "=== 测试2: 锁竞争测试 ==="
  log_info "快速连续触发3个构建，测试锁竞争情况"

  local test_count=3
  local run_ids=()

  # 获取初始状态
  local initial_status=$(get_queue_status)
  show_lock_status "$initial_status" "锁竞争测试前状态"

  # 快速连续触发构建
  for i in $(seq 1 $test_count); do
    local customer_name="LockTestClient$i"
    local tag_name="v1.0.0-locktest-$i"

    log_info "触发锁竞争测试构建 $i: $customer_name - $tag_name"
    local run_id=$(trigger_manual_workflow "$customer_name" "$tag_name")
    run_ids+=("$run_id")

    # 短暂延迟
    sleep 2
  done

  # 等待一段时间后检查状态
  sleep 10
  local final_status=$(get_queue_status)
  show_lock_status "$final_status" "锁竞争测试后状态"

  log_success "锁竞争测试完成"
  log_info "触发的Run IDs: ${run_ids[*]}"

  TEST_RESULTS+=("lock_contention|$test_count|${run_ids[*]}")
}

# 测试3: 错误恢复测试
test_error_recovery() {
  log_test "=== 测试3: 错误恢复测试 ==="
  log_info "模拟构建失败情况，测试锁的释放和恢复"

  local customer_name="ErrorTestClient"
  local tag_name="v1.0.0-errortest"

  # 获取初始状态
  local initial_status=$(get_queue_status)
  show_lock_status "$initial_status" "错误恢复测试前状态"

  log_info "触发错误恢复测试构建: $customer_name - $tag_name"
  local run_id=$(trigger_manual_workflow "$customer_name" "$tag_name")

  # 等待一段时间
  sleep 15

  # 检查队列状态
  local status=$(get_queue_status)
  show_lock_status "$status" "错误恢复测试后状态"

  log_success "错误恢复测试完成"
  log_info "触发的Run ID: $run_id"

  TEST_RESULTS+=("error_recovery|1|$run_id")
}

# 测试4: 锁超时测试
test_lock_timeout() {
  log_test "=== 测试4: 锁超时测试 ==="
  log_info "测试锁超时机制是否正常工作"

  # 触发一个构建
  local customer_name="TimeoutTestClient"
  local tag_name="v1.0.0-timeouttest"

  log_info "触发锁超时测试构建: $customer_name - $tag_name"
  local run_id=$(trigger_manual_workflow "$customer_name" "$tag_name")

  # 等待一段时间让锁超时
  log_info "等待锁超时..."
  sleep 30

  # 检查队列状态
  local status=$(get_queue_status)
  show_lock_status "$status" "锁超时测试后状态"

  log_success "锁超时测试完成"
  log_info "触发的Run ID: $run_id"

  TEST_RESULTS+=("lock_timeout|1|$run_id")
}

# 测试5: 队列满测试
test_queue_full() {
  log_test "=== 测试5: 队列满测试 ==="
  log_info "测试队列满时的行为"

  local test_count=6 # 超过队列限制5个
  local run_ids=()

  # 获取初始状态
  local initial_status=$(get_queue_status)
  show_lock_status "$initial_status" "队列满测试前状态"

  # 快速触发超过队列限制的构建
  for i in $(seq 1 $test_count); do
    local customer_name="QueueFullClient$i"
    local tag_name="v1.0.0-queuefull-$i"

    log_info "触发队列满测试构建 $i: $customer_name - $tag_name"
    local run_id=$(trigger_manual_workflow "$customer_name" "$tag_name")
    run_ids+=("$run_id")

    # 短暂延迟
    sleep 1
  done

  # 等待一段时间后检查状态
  sleep 10
  local final_status=$(get_queue_status)
  show_lock_status "$final_status" "队列满测试后状态"

  log_success "队列满测试完成"
  log_info "触发的Run IDs: ${run_ids[*]}"

  TEST_RESULTS+=("queue_full|$test_count|${run_ids[*]}")
}

# 显示测试结果
show_test_results() {
  log_success "三锁架构测试完成！"
  echo
  echo "=== 测试结果汇总 ==="
  echo "测试项目: ${#TEST_RESULTS[@]} 个"
  echo
  echo "详细结果:"
  for result in "${TEST_RESULTS[@]}"; do
    IFS='|' read -r test_type count details <<<"$result"
    echo "  $test_type | 数量: $count | 详情: $details"
  done
  echo
  echo "请手动检查工作流状态和Issue状态"
}

# 运行所有测试
run_all_tests() {
  log_info "开始三锁架构专门测试..."

  # 检查环境
  check_gh_cli
  get_repo_info

  # 检查队列管理Issue
  check_queue_issue

  # 获取初始状态
  log_info "=== 初始状态 ==="
  local initial_status=$(get_queue_status)
  show_lock_status "$initial_status" "测试开始前状态"

  # 运行所有测试
  test_concurrent_builds
  sleep 5

  test_lock_contention
  sleep 5

  test_error_recovery
  sleep 5

  test_lock_timeout
  sleep 5

  test_queue_full
  sleep 5

  # 最终状态检查
  log_info "=== 最终状态 ==="
  local final_status=$(get_queue_status)
  show_lock_status "$final_status" "所有测试完成后状态"

  # 显示测试结果
  show_test_results
}

# 主函数
main() {
  log_info "三锁架构专门测试脚本启动..."
  run_all_tests
}

# 运行主函数
main "$@"
