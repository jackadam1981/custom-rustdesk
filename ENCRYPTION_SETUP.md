# GitHub Actions 队列参数加密方案（审核后加密版）

## 概述
- 敏感参数在**审核通过、加入队列时**首次加密，存储在队列 issue body 的 `encrypted_params` 字段。
- 加密密钥 `ENCRYPTION_KEY` 由仓库管理员**手动**设置在 Repository Variables（Settings → Secrets and variables → Actions → Variables）。
- 只有有权限的 workflow 可以解密使用，普通用户无法看到明文参数。

## 加密时机
- **触发阶段（01-trigger.yml）**：提取参数，明文传递
- **审核阶段（02-review.yml）**：进行私有IP检查等审核，明文处理
- **加入队列阶段（04-queue-join.yml）**：**首次加密所有参数**并写入队列
- **后续阶段（05-queue-wait, 06-build, 07-finish）**：解密使用参数

## 设置步骤
1. 仓库管理员在 Settings → Secrets and variables → Actions → Variables 新增变量：
   - 名称：`ENCRYPTION_KEY`
   - 值：32字节（64位十六进制字符串），可用 `openssl rand -hex 32` 生成
2. 运行 `.github/workflows/generate-aes-key.yml` 生成密钥（可选）

## 核心用法

### 1. 加入队列时加密（04-queue-join.yml）
```bash
source .github/workflows/shared/github-utils.yml

# 从review阶段获取的参数数据
REVIEW_DATA='${{ env.CURRENT_DATA }}'

# 为当前队列项加密参数
ENCRYPTED_ITEM_PARAMS=$(encrypt_params "$REVIEW_DATA")

# 创建队列项（包含自己的加密参数）
QUEUE_ITEM=$(jq -n \
  --arg build_id "$CURRENT_BUILD_ID" \
  --arg build_title "$BUILD_TITLE" \
  --arg user "$CURRENT_USER" \
  --arg join_time "$JOIN_TIME" \
  --arg trigger_type "$TRIGGER_TYPE" \
  --arg encrypted_params "$ENCRYPTED_ITEM_PARAMS" \
  '{
    build_id: $build_id,
    build_title: $build_title,
    user: $user,
    join_time: $join_time,
    trigger_type: $trigger_type,
    status: "waiting",
    encrypted_params: $encrypted_params
  }')

# 提取公开信息用于顶层显示
CURRENT_TAG=$(echo "$REVIEW_DATA" | jq -r '.tag // empty')
CURRENT_CUSTOMER=$(echo "$REVIEW_DATA" | jq -r '.customer // empty')
CURRENT_CUSTOMER_LINK=$(echo "$REVIEW_DATA" | jq -r '.customer_link // empty')
CURRENT_SLOGAN=$(echo "$REVIEW_DATA" | jq -r '.slogan // empty')
```

### 2. 后续阶段解密使用
```bash
# 获取队列数据
QUEUE_CONTENT=$(get_queue_manager_content "1")
QUEUE_DATA=$(extract_queue_json "$QUEUE_CONTENT")

# 从队列中找到当前构建项
CURRENT_QUEUE_ITEM=$(echo "$QUEUE_DATA" | \
  jq -r --arg build_id "$CURRENT_BUILD_ID" \
  '.queue[] | select(.build_id == $build_id) // empty')

# 获取并解密参数
ENCRYPTED_PARAMS=$(echo "$CURRENT_QUEUE_ITEM" | jq -r '.encrypted_params // empty')
DECRYPTED_PARAMS=$(decrypt_params "$ENCRYPTED_PARAMS")

# 提取参数
TAG=$(echo "$DECRYPTED_PARAMS" | jq -r '.tag')
SUPER_PASSWORD=$(echo "$DECRYPTED_PARAMS" | jq -r '.super_password')
```

## 工作流修改

### 需要添加 ENCRYPTION_KEY 环境变量的工作流：
- `04-queue-join.yml` - 加密存储
- `05-queue-wait.yml` - 解密使用
- `06-build.yml` - 解密使用
- `07-finish.yml` - 解密使用

### 解密调用示例：
```bash
# 在需要解密的工作流中
env:
  ENCRYPTION_KEY: ${{ secrets.ENCRYPTION_KEY }}

# 解密队列数据
QUEUE_DATA=$(extract_queue_json "$QUEUE_MANAGER_CONTENT" "true")
```

## 数据结构
- 加密前：
```json
{
  "queue": [
    {
      "build_id": "1234567890",
      "build_title": "Manual Build",
      "user": "username",
      "join_time": "2024-01-15T10:30:00+00:00",
      "trigger_type": "workflow_dispatch",
      "status": "waiting",
      "encrypted_params": "iv:base64_encrypted_data_for_this_build"
    },
    {
      "build_id": "42",
      "build_title": "Issue Build", 
      "user": "another_user",
      "join_time": "2024-01-15T10:35:00+00:00",
      "trigger_type": "issue",
      "status": "waiting",
      "encrypted_params": "iv:base64_encrypted_data_for_this_issue"
    }
  ],
  "run_id": null,
  "version": 1
}
```
- 有构建运行时：
```json
{
  "queue": [
    {
      "build_id": "1234567890",
      "build_title": "Manual Build",
      "user": "username",
      "join_time": "2024-01-15T10:30:00+00:00",
      "trigger_type": "workflow_dispatch",
      "status": "building",
      "encrypted_params": "iv:base64_encrypted_data_for_this_build"
    },
    {
      "build_id": "42",
      "build_title": "Issue Build", 
      "user": "another_user",
      "join_time": "2024-01-15T10:35:00+00:00",
      "trigger_type": "issue",
      "status": "waiting",
      "encrypted_params": "iv:base64_encrypted_data_for_this_issue"
    }
  ],
  "run_id": "1234567890",
  "version": 2,
  "tag": "v1.0.0",
  "customer": "Test Customer",
  "customer_link": "https://example.com",
  "slogan": "Custom RustDesk Build"
}
```

## 设计说明
- **每个队列项**：包含自己的完整加密参数（`encrypted_params`）
- **顶层字段**：`run_id`、`version`、`tag`、`customer`、`customer_link`、`slogan` 表示当前正在运行的构建信息
- **参数独立性**：每个构建的参数完全独立，不会相互影响
- **公开信息**：顶层显示当前运行构建的公开信息，方便查看和管理

## 注意事项
- `ENCRYPTION_KEY` 必须手动设置且妥善保管，丢失密钥将无法解密历史数据。
- 参数在审核阶段以明文处理，确保审核逻辑清晰。
- 只有在确认入队时才加密，避免不必要的加密操作。
- 后续所有阶段都使用解密后的参数，保持数据一致性。 