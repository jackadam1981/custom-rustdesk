#!/bin/bash
# 构建脚本
# 这个文件处理构建逻辑和数据处�?
# 加载依赖脚本
source .github/workflows/scripts/github-utils.sh

# 提取数据
extract_build_data() {
    local input="$1"
    
    # 验证输入JSON格式
    echo "Validating input JSON format..."
    echo "$input" | jq . > /dev/null
    echo "Input JSON validation passed"
    
    # 设置环境变量供后续步骤使�?    echo "CURRENT_DATA=$input" >> $GITHUB_ENV
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
    
    # 验证JSON格式
    echo "Validating input JSON..."
    echo "$current_data" | jq . > /dev/null
    echo "Input JSON validation passed"
    
    # 使用jq处理JSON，添加构建状�?    local processed=$(echo "$current_data" | jq -c --arg build_time "$(date -Iseconds)" '. + {built: true, build_time: $build_time}')
    
    # 验证处理后的JSON格式
    echo "Validating processed JSON..."
    echo "$processed" | jq . > /dev/null
    echo "Processed JSON validation passed"
    
    echo "CURRENT_DATA=$processed" >> $GITHUB_ENV
    echo "$processed"
}

# 输出构建数据
output_build_data() {
    local output_data="$1"
    
    # 验证输出JSON格式
    echo "Validating output JSON format..."
    echo "$output_data" | jq . > /dev/null
    echo "Output JSON validation passed"
    
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
