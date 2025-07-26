#!/bin/bash
# 精简调试工具脚本
# 提供统一的调试输出函数和JSON校验功能

# 调试开关 - 通过环境变量控制
DEBUG_ENABLED="${DEBUG_ENABLED:-false}"

# 调试颜色定义
DEBUG_COLOR_RED='\033[0;31m'
DEBUG_COLOR_GREEN='\033[0;32m'
DEBUG_COLOR_YELLOW='\033[1;33m'
DEBUG_COLOR_BLUE='\033[0;34m'
DEBUG_COLOR_CYAN='\033[0;36m'
DEBUG_COLOR_RESET='\033[0m'

# 统一的调试入口函数
# 用法: debug "类型" "消息" [参数]
# 类型包括: log, var, json, validate, error, warning, success
debug() {
    local debug_type="$1"
    local message="$2"
    local param1="$3"
    local param2="$4"
    
    # 检查是否启用调试
    if [ "$DEBUG_ENABLED" != "true" ]; then
        return 0
    fi
    
    # 根据类型调用相应的调试函数
    case "$debug_type" in
        "log")
            debug_log "$message"
            ;;
        "var")
            debug_var "$message" "$param1"
            ;;
        "json")
            debug_json "$message" "$param1"
            ;;
        "validate")
            debug_validate_json "$message" "$param1"
            ;;
        "error")
            debug_error "$message" "$param1"
            ;;
        "warning")
            debug_warning "$message" "$param1"
            ;;
        "success")
            debug_success "$message" "$param1"
            ;;
        *)
            debug_log "未知调试类型: $debug_type, 消息: $message" "$DEBUG_COLOR_RED"
            ;;
    esac
}

# 调试函数：基础调试输出
debug_log() {
    local message="$1"
    local color="$2"
    
    # 获取时间戳
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 输出调试信息
    if [ -n "$color" ]; then
        echo -e "${color}[DEBUG] $timestamp: $message${DEBUG_COLOR_RESET}" >&2
    else
        echo "[DEBUG] $timestamp: $message" >&2
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
        
        # 输出JSON结构信息
        local key_count=$(echo "$json_data" | jq 'keys | length' 2>/dev/null)
        local keys=$(echo "$json_data" | jq -r 'keys[]' 2>/dev/null | tr '\n' ' ')
        debug_log "JSON结构 - 键数量: $key_count, 键列表: $keys" "$DEBUG_COLOR_CYAN"
    else
        debug_log "$json_name (无效JSON或空): $json_data" "$DEBUG_COLOR_RED"
        
        # 尝试分析错误类型
        if [ -n "$json_data" ]; then
            if [[ "$json_data" =~ [^"]*:[^"]* ]]; then
                debug_log "可能的问题: 键值对缺少引号（伪JSON格式）" "$DEBUG_COLOR_YELLOW"
            fi
            if [[ "$json_data" =~ [^"]*,[^"]* ]]; then
                debug_log "可能的问题: 逗号分隔符问题" "$DEBUG_COLOR_YELLOW"
            fi
        fi
    fi
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

# JSON校验函数
debug_validate_json() {
    local step_name="$1"
    local json_data="$2"
    
    # 检查是否启用调试
    if [ "$DEBUG_ENABLED" != "true" ]; then
        return 0
    fi
    
    # 检查JSON数据是否为空
    if [ -z "$json_data" ]; then
        debug_error "JSON数据为空" "步骤: $step_name"
        return 1
    fi
    
    # 使用jq验证JSON格式
    if echo "$json_data" | jq . > /dev/null 2>&1; then
        debug_success "JSON格式正确" "步骤: $step_name"
        
        # 输出JSON结构信息
        local key_count=$(echo "$json_data" | jq 'keys | length' 2>/dev/null)
        local keys=$(echo "$json_data" | jq -r 'keys[]' 2>/dev/null | tr '\n' ' ')
        debug_log "JSON键数量: $key_count" "$DEBUG_COLOR_CYAN"
        debug_log "JSON键列表: $keys" "$DEBUG_COLOR_CYAN"
        
        return 0
    else
        debug_error "JSON语法错误" "步骤: $step_name"
        debug_log "JSON内容: $json_data" "$DEBUG_COLOR_RED"
        
        # 尝试分析错误类型
        if [[ "$json_data" =~ [^"]*:[^"]* ]]; then
            debug_warning "可能的问题" "键值对缺少引号（伪JSON格式）"
        fi
        if [[ "$json_data" =~ [^"]*,[^"]* ]]; then
            debug_warning "可能的问题" "逗号分隔符问题"
        fi
        
        return 1
    fi
}

# 初始化调试环境
init_debug_environment() {
    if [ "$DEBUG_ENABLED" = "true" ]; then
        debug_log "调试模式已启用" "$DEBUG_COLOR_GREEN"
        debug_log "环境变量检查:" "$DEBUG_COLOR_CYAN"
        debug_var "DEBUG_ENABLED" "$DEBUG_ENABLED"
        debug_var "GITHUB_REPOSITORY" "${GITHUB_REPOSITORY:-未设置}"
        debug_var "GITHUB_TOKEN" "${GITHUB_TOKEN:+已设置}"
        debug_var "ISSUE_TOKEN" "${ISSUE_TOKEN:+已设置}"
    fi
}

# 注释掉自动初始化，避免脚本加载时就输出调试信息
# init_debug_environment 