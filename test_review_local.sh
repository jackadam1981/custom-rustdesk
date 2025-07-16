#!/bin/bash

# 模拟GitHub Actions环境变量
export GITHUB_ENV="/tmp/github_env"
export GITHUB_OUTPUT="/tmp/github_output"
export GITHUB_TOKEN="test_token"
export ENCRYPTION_KEY="test_key"

# 创建临时文件
touch "$GITHUB_ENV"
touch "$GITHUB_OUTPUT"

# 清理之前的测试数据
echo "" > "$GITHUB_ENV"
echo "" > "$GITHUB_OUTPUT"

echo "=== 测试review.sh脚本 ==="
echo "模拟GitHub Actions环境变量:"
echo "GITHUB_ENV: $GITHUB_ENV"
echo "GITHUB_OUTPUT: $GITHUB_OUTPUT"
echo ""

# 加载review.sh脚本
source .github/workflows/scripts/review.sh

# 测试JSON数据
TEST_JSON='{"tag":"custom-20250715-230353","original_tag":"custom","email":"admin@example.com","customer":"test","customer_link":"","super_password":"password123","slogan":"Custom Rustdesk","rendezvous_server":"192.168.1.100","rs_pub_key":"","api_server":"http://192.168.1.100:21114"}'

echo "=== 测试process_review函数 ==="
echo "输入JSON: $TEST_JSON"
echo ""

# 调用process_review函数
process_review "$TEST_JSON" "jackadam1981" "jackadam1981"

echo ""
echo "=== 环境变量内容 ==="
if [ -f "$GITHUB_ENV" ]; then
    echo "GITHUB_ENV 内容:"
    cat "$GITHUB_ENV"
else
    echo "GITHUB_ENV 文件不存在"
fi

echo ""
echo "=== GitHub Actions输出内容 ==="
if [ -f "$GITHUB_OUTPUT" ]; then
    echo "GITHUB_OUTPUT 内容:"
    cat "$GITHUB_OUTPUT"
else
    echo "GITHUB_OUTPUT 文件不存在"
fi

echo ""
echo "=== 测试完成 ==="

# 清理临时文件
rm -f "$GITHUB_ENV" "$GITHUB_OUTPUT" 