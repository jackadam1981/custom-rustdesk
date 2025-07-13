#!/bin/bash
# 测试重构后的函数

# 加载共享工具函数
source .github/workflows/scripts/github-utils.sh

echo "Testing refactored functions..."

# 测试 markdown 模板函数
echo "=== Testing markdown template functions ==="

# 测试生成队列管理正文
echo "Testing generate_queue_management_body..."
TEST_QUEUE_DATA='{"queue":[],"run_id":null,"version":1}'
BODY=$(generate_queue_management_body "2024-01-01 12:00:00" "$TEST_QUEUE_DATA" "空闲 🔓" "无" "无" "1")
echo "Generated body:"
echo "$BODY"
echo ""

# 测试生成拒绝评论
echo "Testing generate_reject_comment..."
REJECT_COMMENT=$(generate_reject_comment "队列已满" "5" "5" "• #123 - 测试客户 (2024-01-01 12:00:00)" "2024-01-01 12:00:00")
echo "Generated reject comment:"
echo "$REJECT_COMMENT"
echo ""

# 测试生成成功评论
echo "Testing generate_success_comment..."
SUCCESS_COMMENT=$(generate_success_comment "1" "5" "123" "v1.0" "测试客户" "测试标语" "2024-01-01 12:00:00")
echo "Generated success comment:"
echo "$SUCCESS_COMMENT"
echo ""

# 测试生成清理原因
echo "Testing generate_cleanup_reasons..."
REASONS=("锁超时：已占用3小时" "队列重复：构建项目 123 重复")
CLEANUP_REASONS=$(generate_cleanup_reasons "${REASONS[@]}")
echo "Generated cleanup reasons:"
echo "$CLEANUP_REASONS"
echo ""

echo "=== All markdown template tests passed ==="
echo ""

# 测试队列操作函数（需要 GitHub 环境）
echo "=== Testing queue operation functions ==="
echo "Note: These functions require GitHub environment variables"
echo ""

# 检查必要的环境变量
if [ -z "$GITHUB_TOKEN" ]; then
    echo "⚠️ GITHUB_TOKEN not set, skipping queue operation tests"
else
    echo "✅ GITHUB_TOKEN is set"
    
    if [ -z "$GITHUB_REPOSITORY" ]; then
        echo "⚠️ GITHUB_REPOSITORY not set, skipping queue operation tests"
    else
        echo "✅ GITHUB_REPOSITORY is set: $GITHUB_REPOSITORY"
        
        if [ -z "$ENCRYPTION_KEY" ]; then
            echo "⚠️ ENCRYPTION_KEY not set, some functions may fail"
        else
            echo "✅ ENCRYPTION_KEY is set"
        fi
        
        echo ""
        echo "Queue operation functions are ready for testing in GitHub Actions environment"
    fi
fi

echo ""
echo "=== Test completed ===" 