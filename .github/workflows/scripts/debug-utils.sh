#!/bin/bash
# 调试工具脚本
# 提供统一的调试输出函数和环境变量控制

# 调试开关 - 通过环境变量控制
DEBUG_ENABLED="${DEBUG_ENABLED:-false}"

# 调试颜色定义
DEBUG_COLOR_RED='\033[0;31m'
DEBUG_COLOR_GREEN='\033[0;32m'
DEBUG_COLOR_YELLOW='\033[1;33m'
DEBUG_COLOR_BLUE='\033[0;34m'
DEBUG_COLOR_PURPLE='\033[0;35m'
DEBUG_COLOR_CYAN='\033[0;36m'
DEBUG_COLOR_RESET='\033[0m'

# 调试函数：基础调试输出
debug_log() {
    local message="$1"
    local color="$2"
    
    # 检查是否启用调试
    if [ "$DEBUG_ENABLED" != "true" ]; then
        return 0
    fi
    
    # 获取时间戳
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 输出调试信息
    if [ -n "$color" ]; then
        echo -e "${color}[DEBUG] $timestamp: $message${DEBUG_COLOR_RESET}" >&2
    else
        echo "[DEBUG] $timestamp: $message" >&2
    fi
}

# 调试函数：函数入口
debug_enter() {
    local function_name="$1"
    local params="$2"
    debug_log "进入函数: $function_name" "$DEBUG_COLOR_GREEN"
    if [ -n "$params" ]; then
        debug_log "参数: $params" "$DEBUG_COLOR_CYAN"
    fi
}

# 调试函数：函数退出
debug_exit() {
    local function_name="$1"
    local exit_code="$2"
    local result="$3"
    
    if [ "$exit_code" -eq 0 ]; then
        debug_log "函数 $function_name 成功退出 (code: $exit_code)" "$DEBUG_COLOR_GREEN"
    else
        debug_log "函数 $function_name 失败退出 (code: $exit_code)" "$DEBUG_COLOR_RED"
    fi
    
    if [ -n "$result" ]; then
        debug_log "返回值: $result" "$DEBUG_COLOR_CYAN"
    fi
}

# 调试函数：变量输出
debug_var() {
    local var_name="$1"
    local var_value="$2"
    local max_length="${3:-100}"
    
    if [ ${#var_value} -gt "$max_length" ]; then
        local preview="${var_value:0:$max_length}..."
        debug_log "$var_name: $preview (长度: ${#var_value})" "$DEBUG_COLOR_YELLOW"
    else
        debug_log "$var_name: $var_value" "$DEBUG_COLOR_YELLOW"
    fi
}

# 调试函数：JSON数据输出
debug_json() {
    local json_name="$1"
    local json_data="$2"
    
    if [ -n "$json_data" ] && echo "$json_data" | jq . > /dev/null 2>&1; then
        debug_log "$json_name (有效JSON): $json_data" "$DEBUG_COLOR_BLUE"
    else
        debug_log "$json_name (无效JSON或空): $json_data" "$DEBUG_COLOR_RED"
    fi
}

# 调试函数：API调用
debug_api() {
    local method="$1"
    local url="$2"
    local response="$3"
    local http_code="$4"
    
    debug_log "API调用: $method $url" "$DEBUG_COLOR_PURPLE"
    if [ -n "$http_code" ]; then
        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
            debug_log "HTTP响应码: $http_code (成功)" "$DEBUG_COLOR_GREEN"
        else
            debug_log "HTTP响应码: $http_code (失败)" "$DEBUG_COLOR_RED"
        fi
    fi
    if [ -n "$response" ]; then
        debug_json "API响应" "$response"
    fi
}

# 调试函数：队列操作
debug_queue() {
    local operation="$1"
    local queue_data="$2"
    local additional_info="$3"
    
    debug_log "队列操作: $operation" "$DEBUG_COLOR_BLUE"
    if [ -n "$additional_info" ]; then
        debug_log "附加信息: $additional_info" "$DEBUG_COLOR_CYAN"
    fi
    debug_json "队列数据" "$queue_data"
}

# 调试函数：锁操作
debug_lock() {
    local lock_type="$1"
    local operation="$2"
    local build_id="$3"
    local status="$4"
    
    debug_log "锁操作: $lock_type - $operation" "$DEBUG_COLOR_PURPLE"
    debug_log "构建ID: $build_id, 状态: $status" "$DEBUG_COLOR_CYAN"
}

# 调试函数：错误信息
debug_error() {
    local error_message="$1"
    local context="$2"
    
    debug_log "错误: $error_message" "$DEBUG_COLOR_RED"
    if [ -n "$context" ]; then
        debug_log "上下文: $context" "$DEBUG_COLOR_RED"
    fi
}

# 调试函数：警告信息
debug_warning() {
    local warning_message="$1"
    local context="$2"
    
    debug_log "警告: $warning_message" "$DEBUG_COLOR_YELLOW"
    if [ -n "$context" ]; then
        debug_log "上下文: $context" "$DEBUG_COLOR_YELLOW"
    fi
}

# 调试函数：成功信息
debug_success() {
    local success_message="$1"
    local details="$2"
    
    debug_log "成功: $success_message" "$DEBUG_COLOR_GREEN"
    if [ -n "$details" ]; then
        debug_log "详情: $details" "$DEBUG_COLOR_GREEN"
    fi
}

# 调试函数：性能监控
debug_performance() {
    local operation="$1"
    local start_time="$2"
    local end_time="$3"
    
    if [ -n "$start_time" ] && [ -n "$end_time" ]; then
        local duration=$((end_time - start_time))
        debug_log "性能: $operation 耗时 ${duration}秒" "$DEBUG_COLOR_CYAN"
    fi
}

# 调试函数：环境检查
debug_environment() {
    debug_log "环境变量检查:" "$DEBUG_COLOR_BLUE"
    debug_var "DEBUG_ENABLED" "$DEBUG_ENABLED"
    debug_var "GITHUB_REPOSITORY" "$GITHUB_REPOSITORY"
    debug_var "GITHUB_TOKEN" "$([ -n "$GITHUB_TOKEN" ] && echo "已设置" || echo "未设置")"
    debug_var "ISSUE_TOKEN" "$([ -n "$ISSUE_TOKEN" ] && echo "已设置" || echo "未设置")"
}

# 调试函数：初始化
debug_init() {
    if [ "$DEBUG_ENABLED" = "true" ]; then
        debug_log "调试模式已启用" "$DEBUG_COLOR_GREEN"
        debug_environment
    else
        # 静默模式，不输出任何调试信息
        return 0
    fi
}

# 自动初始化调试环境
debug_init 