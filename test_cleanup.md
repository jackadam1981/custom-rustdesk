# 自动清理功能测试指南

## 测试目的

验证自动清理机制能够正确处理各种异常情况。

## 测试场景

### 1. **正常情况测试**
- 队列状态正常，无异常
- 预期结果：跳过清理，继续正常流程

### 2. **锁异常测试**
- 手动设置异常锁状态
- 预期结果：自动清理异常锁

### 3. **队列重复测试**
- 手动添加重复项到队列
- 预期结果：自动移除重复项

### 4. **锁超时测试**
- 手动设置长时间占用的锁
- 预期结果：自动释放超时锁

## 测试步骤

### 准备测试环境

1. **确保Issue #1存在**
   - 检查Issue #1是否包含正确的JSON格式
   - 确保有足够的权限进行更新

2. **准备测试数据**
   - 可以手动编辑Issue #1来模拟异常情况
   - 或者通过触发工作流来产生异常

### 执行测试

1. **触发工作流**
   - 创建新的Issue或手动触发workflow
   - 观察自动清理步骤的输出

2. **检查清理结果**
   - 查看Issue #1的更新内容
   - 确认清理记录是否正确

3. **验证状态恢复**
   - 确认队列状态是否恢复正常
   - 验证后续流程是否正常进行

## 常见问题排查

### 1. **语法错误**
- 问题：`return: can only 'return' from a function or sourced script`
- 解决：已修复，使用`exit 0`替代`return`

### 2. **JSON解析错误**
- 问题：队列数据格式不正确
- 解决：添加JSON格式验证

### 3. **权限问题**
- 问题：无法更新Issue #1
- 解决：检查GitHub Token权限

### 4. **网络问题**
- 问题：API调用失败
- 解决：添加错误处理和重试机制

## 预期输出

### 正常情况
```
Starting automatic queue cleanup...
Current queue data: {"issue_queue":[],"workflow_queue":[],"current_build":null,"lock_holder":null}
Current build: null
Lock holder: null
No cleanup needed, queue is healthy
```

### 异常清理
```
Starting automatic queue cleanup...
Current queue data: {"issue_queue":[...],"workflow_queue":[],"current_build":"58","lock_holder":null}
Current build: 58
Lock holder: null
❌ Lock anomaly detected: build=58, holder=null
Performing queue cleanup...
Cleanup reasons: • 锁异常：有构建项目但无持有者
Queue cleanup completed successfully!
Cleaned issue count: 1
Cleaned workflow count: 0
Cleaned total count: 1
```

## 验证要点

1. **清理触发**：确认在异常情况下会触发清理
2. **清理效果**：确认异常状态被正确修复
3. **记录完整**：确认清理记录包含时间和原因
4. **状态恢复**：确认清理后状态正常
5. **流程继续**：确认清理后工作流正常继续

## 手动测试方法

### 模拟锁异常
编辑Issue #1，设置异常锁状态：
```json
{
  "issue_queue": [{"issue_number":"58","issue_title":"测试","user":"test","join_time":"2025-07-12T06:00:00Z"}],
  "workflow_queue": [],
  "current_build": "58",
  "lock_holder": null
}
```

### 模拟队列重复
编辑Issue #1，添加重复项：
```json
{
  "issue_queue": [
    {"issue_number":"58","issue_title":"测试1","user":"test","join_time":"2025-07-12T06:00:00Z"},
    {"issue_number":"58","issue_title":"测试2","user":"test","join_time":"2025-07-12T06:01:00Z"}
  ],
  "workflow_queue": [],
  "current_build": null,
  "lock_holder": null
}
```

### 模拟锁超时
编辑Issue #1，设置长时间占用的锁：
```json
{
  "issue_queue": [{"issue_number":"58","issue_title":"测试","user":"test","join_time":"2025-07-10T06:00:00Z"}],
  "workflow_queue": [],
  "current_build": "58",
  "lock_holder": "test"
}
```

## 成功标准

1. ✅ 自动清理步骤无语法错误
2. ✅ 异常情况被正确识别
3. ✅ 清理操作成功执行
4. ✅ 清理记录完整准确
5. ✅ 队列状态恢复正常
6. ✅ 后续流程正常进行 