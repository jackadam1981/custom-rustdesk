#!/bin/bash

# JSON校验工具函数
# 用于在每一步校验JSON格式，帮助定位JSON破坏的位置

# JSON校验函数
# 参数1: JSON字符串
# 参数2: 步骤名称（用于日志标识）
validate_json() {
    local json_data="$1"
    local step_name="$2"
    
    echo "校验JSON格式 - 步骤: $step_name"
    
    # 检查是否为空
    if [[ -z "$json_data" ]]; then
        echo "步骤 $step_name: JSON数据为空"
        return 1
    fi
    
    # 使用jq校验JSON格式
    if echo "$json_data" | jq . >/dev/null 2>&1; then
        echo "步骤 $step_name: JSON格式正确"
        return 0
    else
        echo "步骤 $step_name: JSON格式错误"
        echo "JSON内容: $json_data"
        return 1
    fi
}

# JSON校验并输出详细信息
validate_json_detailed() {
    local json_data="$1"
    local step_name="$2"
    
    echo "详细校验JSON格式 - 步骤: $step_name"
    
    # 检查是否为空
    if [[ -z "$json_data" ]]; then
        echo "步骤 $step_name: JSON数据为空"
        return 1
    fi
    
    # 检查基本语法
    if ! echo "$json_data" | jq . >/dev/null 2>&1; then
        echo "步骤 $step_name: JSON语法错误"
        echo "JSON内容: $json_data"
        
        # 尝试分析错误类型
        if [[ "$json_data" =~ [^"]*:[^"]* ]]; then
            echo "可能的问题: 键值对缺少引号（伪JSON格式）"
        fi
        if [[ "$json_data" =~ [^"]*,[^"]* ]]; then
            echo "可能的问题: 逗号分隔符问题"
        fi
        return 1
    fi
    
    # 输出JSON结构信息
    local key_count=$(echo "$json_data" | jq 'keys | length' 2>/dev/null)
    local keys=$(echo "$json_data" | jq -r 'keys[]' 2>/dev/null | tr '\n' ' ')
    
    echo "步骤 $step_name: JSON格式正确"
    echo "JSON包含 $key_count 个键: $keys"
    
    return 0
}

# 校验环境变量中的JSON
validate_env_json() {
    local env_var_name="$1"
    local step_name="$2"
    
    echo "校验环境变量JSON - 变量: $env_var_name, 步骤: $step_name"
    
    local json_data="${!env_var_name}"
    
    if [[ -z "$json_data" ]]; then
        echo "步骤 $step_name: 环境变量 $env_var_name 为空"
        return 1
    fi
    
    validate_json_detailed "$json_data" "$step_name"
}

# 校验文件中的JSON
validate_file_json() {
    local file_path="$1"
    local step_name="$2"
    
    echo "校验文件JSON - 文件: $file_path, 步骤: $step_name"
    
    if [[ ! -f "$file_path" ]]; then
        echo "步骤 $step_name: 文件 $file_path 不存在"
        return 1
    fi
    
    local json_data=$(cat "$file_path")
    
    if [[ -z "$json_data" ]]; then
        echo "步骤 $step_name: 文件 $file_path 内容为空"
        return 1
    fi
    
    validate_json_detailed "$json_data" "$step_name"
}

# 输出JSON到文件并校验
output_and_validate_json() {
    local json_data="$1"
    local output_var="$2"
    local step_name="$3"
    
    echo "输出并校验JSON - 变量: $output_var, 步骤: $step_name"
    
    # 先校验JSON格式
    if ! validate_json_detailed "$json_data" "$step_name"; then
        return 1
    fi
    
    # 输出到GitHub Actions输出变量
    echo "$output_var<<EOF" >> "$GITHUB_OUTPUT"
    echo "$json_data" >> "$GITHUB_OUTPUT"
    echo "EOF" >> "$GITHUB_OUTPUT"
    
    echo "步骤 $step_name: JSON已输出到变量 $output_var"
    return 0
}

# 安全地设置JSON变量（避免shell解析问题）
safe_set_json_var() {
    local var_name="$1"
    local json_data="$2"
    
    # 使用printf安全地设置变量，避免shell解析问题
    printf -v "$var_name" '%s' "$json_data"
    
    echo "安全设置JSON变量: $var_name"
    echo "JSON长度: ${#json_data}"
}

# 安全地从GitHub Actions输出读取JSON
safe_read_github_output() {
    local var_name="$1"
    local github_output="$2"
    
    echo "从GitHub Actions输出读取JSON: $github_output"
    
    # 使用printf安全地设置变量
    printf -v "$var_name" '%s' "$github_output"
    
    local json_data="${!var_name}"
    echo "读取的JSON长度: ${#json_data}"
    
    # 检查是否为空
    if [[ -z "$json_data" ]]; then
        echo "GitHub Actions输出为空: $github_output"
        return 1
    fi
    
    return 0
}

# 从GitHub Actions输出读取并校验JSON
read_and_validate_output() {
    local output_var="$1"
    local step_name="$2"
    
    echo "读取并校验输出JSON - 变量: $output_var, 步骤: $step_name"
    
    # 这里需要根据实际的工作流调用方式来实现
    # 通常是通过环境变量或文件传递
    local json_data="${!output_var}"
    
    if [[ -z "$json_data" ]]; then
        echo "步骤 $step_name: 输出变量 $output_var 为空"
        return 1
    fi
    
    validate_json_detailed "$json_data" "$step_name"
}

# 主函数 - 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 测试函数
    echo "JSON校验工具测试"
    echo "=================="
    
    # 测试正确的JSON
    test_json='{"name":"test","value":123,"array":[1,2,3]}'
    validate_json_detailed "$test_json" "测试1-正确JSON"
    
    # 测试错误的JSON
    test_bad_json='{name:test,value:123}'
    validate_json_detailed "$test_bad_json" "测试2-错误JSON"
    
    # 测试空JSON
    validate_json_detailed "" "测试3-空JSON"
fi 