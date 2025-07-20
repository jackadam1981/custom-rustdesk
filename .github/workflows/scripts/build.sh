#!/bin/bash
# 构建脚本
# 这个文件处理构建逻辑和数据处理
# 加载依赖脚本

source .github/workflows/scripts/debug-utils.sh

# 提取数据
extract_build_data() {
    local input="$1"
    # 校验输入JSON格式
    if ! debug "validate" "build.sh-输入数据校验" "$input"; then
        debug "error" "build.sh输入的JSON格式不正确"
        return 1
    fi
    echo "CURRENT_DATA=$input" >> $GITHUB_ENV
    echo "$input"
}

# 暂停构建（用于队列测试）
pause_for_test() {
    local pause_seconds="${1:-300}"
    echo "Pausing for $pause_seconds seconds to test queue..."
    sleep "$pause_seconds"
}

# 处理构建数据
process_build_data() {
    local current_data="$1"
    # 校验输入JSON格式
    if ! debug "validate" "build.sh-处理前数据校验" "$current_data"; then
        debug "error" "build.sh处理前JSON格式不正确"
        return 1
    fi
    local processed=$(echo "$current_data" | jq -c --arg build_time "$(date -Iseconds)" '. + {built: true, build_time: $build_time}')
    # 校验处理后JSON格式
    if ! debug "validate" "build.sh-处理后数据校验" "$processed"; then
        debug "error" "build.sh处理后JSON格式不正确"
        return 1
    fi
    echo "CURRENT_DATA=$processed" >> $GITHUB_ENV
    echo "$processed"
}

# 输出构建数据
output_build_data() {
    local output_data="$1"
    # 校验输出JSON格式
    if ! debug "validate" "build.sh-输出数据校验" "$output_data"; then
        debug "error" "build.sh输出的JSON格式不正确"
        return 1
    fi
    
    # 安全地输出到 GitHub Actions
    if [ -n "$GITHUB_OUTPUT" ]; then
        echo "data=$output_data" >> $GITHUB_OUTPUT
        echo "build_success=true" >> $GITHUB_OUTPUT
        echo "download_url=https://example.com/download/rustdesk-custom.zip" >> $GITHUB_OUTPUT
        echo "error_message=" >> $GITHUB_OUTPUT
    fi
    
    # 显示输出信息
    echo "Build output: $output_data"
    echo "Build success: true"
    echo "Download URL: https://example.com/download/rustdesk-custom.zip"
}

# 主构建管理函数 - 供工作流调用
build_manager() {
    local operation="$1"
    local input_data="$2"
    local pause_seconds="${3:-0}"
    
    case "$operation" in
        "extract-data")
            extract_build_data "$input_data"
            ;;
        "process-data")
            process_build_data "$input_data"
            ;;
        "output-data")
            local output_data="$2"
            output_build_data "$output_data"
            ;;
        "pause")
            pause_for_test "$pause_seconds"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
