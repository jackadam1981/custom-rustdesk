#!/bin/bash
# 测试分离式脚本功能

echo "Testing separated scripts structure..."

# 测试加密工具
echo "=== Testing encryption-utils.sh ==="
if [ -f ".github/workflows/shared/encryption-utils.sh" ]; then
    echo "✅ encryption-utils.sh exists"
    # 测试函数是否存在
    source .github/workflows/scripts/encryption-utils.sh
    if command -v encrypt_params >/dev/null 2>&1; then
        echo "✅ encrypt_params function available"
    else
        echo "❌ encrypt_params function not found"
    fi
    if command -v decrypt_params >/dev/null 2>&1; then
        echo "✅ decrypt_params function available"
    else
        echo "❌ decrypt_params function not found"
    fi
else
    echo "❌ encryption-utils.sh not found"
fi

echo ""

# 测试 issue 模板
echo "=== Testing issue-templates.sh ==="
if [ -f ".github/workflows/shared/issue-templates.sh" ]; then
    echo "✅ issue-templates.sh exists"
    # 测试函数是否存在
    source .github/workflows/scripts/issue-templates.sh
    if command -v generate_queue_management_body >/dev/null 2>&1; then
        echo "✅ generate_queue_management_body function available"
    else
        echo "❌ generate_queue_management_body function not found"
    fi
    if command -v generate_reject_comment >/dev/null 2>&1; then
        echo "✅ generate_reject_comment function available"
    else
        echo "❌ generate_reject_comment function not found"
    fi
else
    echo "❌ issue-templates.sh not found"
fi

echo ""

# 测试队列管理
echo "=== Testing queue-manager.sh ==="
if [ -f ".github/workflows/shared/queue-manager.sh" ]; then
    echo "✅ queue-manager.sh exists"
    # 测试函数是否存在
    source .github/workflows/scripts/queue-manager.sh
    if command -v join_queue >/dev/null 2>&1; then
        echo "✅ join_queue function available"
    else
        echo "❌ join_queue function not found"
    fi
    if command -v wait_for_queue_turn >/dev/null 2>&1; then
        echo "✅ wait_for_queue_turn function available"
    else
        echo "❌ wait_for_queue_turn function not found"
    fi
    if command -v extract_queue_json >/dev/null 2>&1; then
        echo "✅ extract_queue_json function available"
    else
        echo "❌ extract_queue_json function not found"
    fi
else
    echo "❌ queue-manager.sh not found"
fi

echo ""

# 测试模板生成
echo "=== Testing template generation ==="
if [ -f ".github/workflows/shared/issue-templates.sh" ]; then
    source .github/workflows/scripts/issue-templates.sh
    
    # 测试生成队列管理正文
    echo "Testing generate_queue_management_body..."
    TEST_QUEUE_DATA='{"queue":[],"run_id":null,"version":1}'
    BODY=$(generate_queue_management_body "2024-01-01 12:00:00" "$TEST_QUEUE_DATA" "空闲 🔓" "无" "无" "1")
    if [ -n "$BODY" ]; then
        echo "✅ generate_queue_management_body works"
    else
        echo "❌ generate_queue_management_body failed"
    fi
    
    # 测试生成拒绝评论
    echo "Testing generate_reject_comment..."
    REJECT_COMMENT=$(generate_reject_comment "队列已满" "5" "5" "• #123 - 测试客户 (2024-01-01 12:00:00)" "2024-01-01 12:00:00")
    if [ -n "$REJECT_COMMENT" ]; then
        echo "✅ generate_reject_comment works"
    else
        echo "❌ generate_reject_comment failed"
    fi
else
    echo "❌ Cannot test templates - issue-templates.sh not found"
fi

echo ""

# 检查依赖关系
echo "=== Checking dependencies ==="
echo "queue-manager.sh depends on:"
echo "  - encryption-utils.sh (for encrypt_params)"
echo "  - issue-templates.sh (for generate_* functions)"
echo ""
echo "issue-templates.sh depends on:"
echo "  - none (standalone)"
echo ""
echo "encryption-utils.sh depends on:"
echo "  - none (standalone)"

echo ""
echo "=== Test completed ===" 