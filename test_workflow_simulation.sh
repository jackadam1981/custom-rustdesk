#!/bin/bash
# 模拟GitHub Actions环境测试

echo "=== 模拟GitHub Actions环境测试 ==="
echo ""

# 设置模拟的GitHub Actions环境变量
export GITHUB_OUTPUT="/tmp/github_output"
export GITHUB_ENV="/tmp/github_env"

# 清理之前的输出文件
rm -f "$GITHUB_OUTPUT" "$GITHUB_ENV"
touch "$GITHUB_OUTPUT" "$GITHUB_ENV"

# 启用调试
export DEBUG_ENABLED=true

echo "1. 测试trigger步骤:"
echo "模拟workflow_dispatch事件..."

# 加载脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/trigger.sh

# 模拟workflow_dispatch事件数据
EVENT_NAME="workflow_dispatch"
EVENT_DATA='{"inputs":{"tag":"test","email":"test@example.com","customer":"test","slogan":"test","rendezvous_server":"192.168.1.100","api_server":"http://192.168.1.100:21114"}}'
BUILD_ID="123456"

# 执行trigger步骤
process_trigger "$EVENT_NAME" "$EVENT_DATA" "$BUILD_ID"

echo ""
echo "Trigger步骤输出:"
cat "$GITHUB_OUTPUT"
echo ""

echo "2. 检查输出变量:"
echo "should_proceed: $(grep 'should_proceed=' "$GITHUB_OUTPUT" | cut -d'=' -f2)"
echo "trigger_type: $(grep 'trigger_type=' "$GITHUB_OUTPUT" | cut -d'=' -f2)"
echo "build_id: $(grep 'build_id=' "$GITHUB_OUTPUT" | cut -d'=' -f2)"
echo "data: $(grep 'data=' "$GITHUB_OUTPUT" | cut -d'=' -f2-)"

echo ""
echo "3. 测试review步骤:"
echo "模拟review步骤..."

# 加载review脚本
source .github/workflows/scripts/review.sh

# 获取trigger输出的数据
TRIGGER_DATA=$(grep 'data=' "$GITHUB_OUTPUT" | cut -d'=' -f2-)

# 清理之前的输出文件
rm -f "$GITHUB_OUTPUT"
touch "$GITHUB_OUTPUT"

# 执行review步骤
process_review "$TRIGGER_DATA" "test-user" "test-owner"

echo ""
echo "Review步骤输出:"
cat "$GITHUB_OUTPUT"
echo ""

echo "4. 检查review输出变量:"
echo "validation_passed: $(grep 'validation_passed=' "$GITHUB_OUTPUT" | cut -d'=' -f2)"

echo ""
echo "=== 测试完成 ==="
echo ""
echo "如果should_proceed=true且validation_passed=true，"
echo "那么后续步骤应该能够正常执行。" 