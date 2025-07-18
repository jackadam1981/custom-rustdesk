#!/bin/bash
# 调试功能测试脚本

# 加载调试工具
source .github/workflows/scripts/debug-utils.sh

echo "=== 调试功能测试 ==="

# 测试启用调试模式
echo "测试启用调试模式:"
DEBUG_ENABLED=true
debug_enter "test_function" "param1=value1, param2=value2"
debug_success "测试成功"
debug_error "测试错误" "错误上下文"
debug_warning "测试警告" "警告上下文"
debug_var "测试变量" "这是一个很长的测试变量值，用来测试变量截断功能"
debug_json "测试JSON" '{"name":"test","value":123,"array":[1,2,3]}'
debug_api "GET" "/api/test" '{"status":"success"}' "200"
debug_queue "测试队列操作" '{"queue":[{"id":1},{"id":2}]}' "队列长度: 2"
debug_lock "乐观锁" "获取" "build-123" "成功"
debug_performance "测试操作" "$(date +%s)" "$(date +%s)"
debug_exit "test_function" 0 "测试结果"

echo ""
echo "测试禁用调试模式:"
DEBUG_ENABLED=false
debug_enter "disabled_function" "should_not_show"
debug_success "这个不应该显示"
debug_exit "disabled_function" 0

echo ""
echo "测试环境检查:"
DEBUG_ENABLED=true
debug_environment

echo "=== 调试功能测试完成 ===" 