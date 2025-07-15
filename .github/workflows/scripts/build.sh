#!/bin/bash
# 构建脚本
# 这个文件处理构建逻辑和数据处�?
# 加载依赖脚本

source .github/workflows/scripts/json-validator.sh

# 提取数据
extract_build_data() {
    local input="$1"
    # 校验输入JSON格式
    if ! validate_json_detailed "$input" "build.sh-输入数据校验"; then
        echo "错误: build.sh输入的JSON格式不正确" >&2
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
    if ! validate_json_detailed "$current_data" "build.sh-处理前数据校验"; then
        echo "错误: build.sh处理前JSON格式不正确" >&2
        return 1
    fi
    local processed=$(echo "$current_data" | jq -c --arg build_time "$(date -Iseconds)" '. + {built: true, build_time: $build_time}')
    # 校验处理后JSON格式
    if ! validate_json_detailed "$processed" "build.sh-处理后数据校验"; then
        echo "错误: build.sh处理后JSON格式不正确" >&2
        return 1
    fi
    echo "CURRENT_DATA=$processed" >> $GITHUB_ENV
    echo "$processed"
}

# 输出构建数据
output_build_data() {
    local output_data="$1"
    # 校验输出JSON格式
    if ! validate_json_detailed "$output_data" "build.sh-输出数据校验"; then
        echo "错误: build.sh输出的JSON格式不正确" >&2
        return 1
    fi
    echo "data=$output_data" >> $GITHUB_OUTPUT
    echo "build_success=true" >> $GITHUB_OUTPUT
    echo "download_url=https://example.com/download/rustdesk-custom.zip" >> $GITHUB_OUTPUT
    echo "error_message=" >> $GITHUB_OUTPUT
    
    # 显示输出信息
    echo "Build output: $output_data"
}

# 主构建函数
process_build() {
    local input_data="$1"
    local pause_seconds="${2:-0}"
    
    echo "Starting build process..."
    
    # 提取数据
    local extracted_data=$(extract_build_data "$input_data")
    
    # 如果需要暂停测�?    if [ "$pause_seconds" -gt 0 ]; then
        pause_for_test "$pause_seconds"
    fi
    
    # 处理构建数据
    local processed_data=$(process_build_data "$extracted_data")
    
    # 输出构建数据
    output_build_data "$processed_data"
    
    echo "Build process completed successfully"
} 
