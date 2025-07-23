#!/bin/bash

# 调试 issue 参数提取
echo "=== 调试 Issue 参数提取 ==="

# 加载脚本
source .github/workflows/scripts/trigger.sh

# 启用调试模式
export DEBUG_ENABLED=true

# 测试数据1：模板文本
echo "--- 测试1：模板文本 ---"
export EVENT_DATA='{"action":"opened","issue":{"number":84,"body":"### 构建参数\n\ntag: 标签名称\nemail: 邮件地址\ncustomer: 客户名称\ncustomer_link: 客户链接\nsuper_password: 超级密码\nslogan: 标语\nrendezvous_server: 服务器地址\nrs_pub_key: 公钥\napi_server: API服务器地址"}}'

echo "调用 extract-issue..."
trigger_manager "extract-issue" "$EVENT_DATA"
echo "退出码: $?"

echo ""
echo "--- 测试2：实际参数 ---"
export EVENT_DATA='{"action":"opened","issue":{"number":84,"body":"### 构建参数\n\ntag: custom\nemail: admin@example.com\ncustomer: test\ncustomer_link: \nsuper_password: password123\nslogan: Custom Rustdesk\nrendezvous_server: 192.168.1.100\nrs_pub_key: \napi_server: http://192.168.1.100:21114"}}'

echo "调用 extract-issue..."
trigger_manager "extract-issue" "$EVENT_DATA"
echo "退出码: $?"

echo ""
echo "--- 测试3：空参数 ---"
export EVENT_DATA='{"action":"opened","issue":{"number":84,"body":"### 构建参数\n\ntag: \nemail: \ncustomer: \ncustomer_link: \nsuper_password: \nslogan: \nrendezvous_server: \nrs_pub_key: \napi_server: "}}'

echo "调用 extract-issue..."
trigger_manager "extract-issue" "$EVENT_DATA"
echo "退出码: $?"
