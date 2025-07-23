# GitHub Secrets 配置说明

## 概述
本项目使用GitHub Secrets来存储敏感配置信息，包括默认的服务器配置和认证信息。

## 必需的 Secrets

### 1. 认证相关
- **`ISSUE_TOKEN`**: GitHub Personal Access Token，用于操作issues
- **`ENCRYPTION_KEY`**: 加密密钥，用于加密敏感数据

### 2. 默认配置参数
- **`DEFAULT_TAG`**: 默认标签
- **`DEFAULT_EMAIL`**: 默认邮箱地址
- **`DEFAULT_CUSTOMER`**: 默认客户名称
- **`DEFAULT_CUSTOMER_LINK`**: 默认客户链接
- **`DEFAULT_SUPER_PASSWORD`**: 默认超级密码
- **`DEFAULT_SLOGAN`**: 默认标语

### 3. 默认服务器配置
- **`DEFAULT_RENDEZVOUS_SERVER`**: 默认的Rendezvous服务器地址
- **`DEFAULT_RS_PUB_KEY`**: 默认的RS公钥
- **`DEFAULT_API_SERVER`**: 默认的API服务器地址

## 配置步骤

### 1. 访问仓库设置
1. 进入GitHub仓库页面
2. 点击 "Settings" 标签
3. 在左侧菜单中点击 "Secrets and variables" → "Actions"

### 2. 添加 Secrets
点击 "New repository secret" 按钮，逐个添加以下secrets：

#### 认证相关
**ISSUE_TOKEN**
- **Name**: `ISSUE_TOKEN`
- **Value**: 你的GitHub Personal Access Token
- **说明**: 需要有 `issues:write` 权限

**ENCRYPTION_KEY**
- **Name**: `ENCRYPTION_KEY`
- **Value**: 32位随机字符串
- **说明**: 用于加密敏感数据，请妥善保管

#### 默认配置参数
**DEFAULT_TAG**
- **Name**: `DEFAULT_TAG`
- **Value**: 默认标签
- **示例**: `custom`

**DEFAULT_EMAIL**
- **Name**: `DEFAULT_EMAIL`
- **Value**: 默认邮箱地址
- **示例**: `admin@yourcompany.com`

**DEFAULT_CUSTOMER**
- **Name**: `DEFAULT_CUSTOMER`
- **Value**: 默认客户名称
- **示例**: `Your Company Name`

**DEFAULT_CUSTOMER_LINK**
- **Name**: `DEFAULT_CUSTOMER_LINK`
- **Value**: 默认客户链接
- **示例**: `https://yourcompany.com`

**DEFAULT_SUPER_PASSWORD**
- **Name**: `DEFAULT_SUPER_PASSWORD`
- **Value**: 默认超级密码
- **说明**: 用于RustDesk客户端认证

**DEFAULT_SLOGAN**
- **Name**: `DEFAULT_SLOGAN`
- **Value**: 默认标语
- **示例**: `Custom RustDesk`

#### 服务器配置
**DEFAULT_RENDEZVOUS_SERVER**
- **Name**: `DEFAULT_RENDEZVOUS_SERVER`
- **Value**: 你的Rendezvous服务器地址
- **示例**: `https://your-server.com:21117`

**DEFAULT_RS_PUB_KEY**
- **Name**: `DEFAULT_RS_PUB_KEY`
- **Value**: 你的RS公钥
- **说明**: 用于RustDesk客户端认证

**DEFAULT_API_SERVER**
- **Name**: `DEFAULT_API_SERVER`
- **Value**: 你的API服务器地址
- **示例**: `https://your-api-server.com`

## 使用逻辑

### 智能兜底机制
- **当 `rendezvous_server`、`rs_pub_key` 和 `api_server` 都为空时**：使用所有secrets中的默认值
- **当关键参数已提供时**：全面使用用户提供的参数，包括空值，不应用任何默认值

### 示例场景

**场景1：完全使用默认值**
```bash
# 输入：所有参数都为空
# 输出：使用所有secrets中的默认值
TAG="custom"
EMAIL="admin@yourcompany.com"
CUSTOMER="Your Company"
RENDEZVOUS_SERVER="https://your-server.com:21117"
API_SERVER="https://your-api-server.com"
```

**场景2：全面使用用户参数**
```bash
# 输入：用户提供了所有参数
TAG="user-tag"
EMAIL="user@example.com"
CUSTOMER="user-customer"
RENDEZVOUS_SERVER="user-server"
API_SERVER="user-api"

# 输出：全面使用用户提供的参数，不替换任何默认值
TAG="user-tag"
EMAIL="user@example.com"
CUSTOMER="user-customer"
RENDEZVOUS_SERVER="user-server"
API_SERVER="user-api"
```

**场景3：用户参数包含空值**
```bash
# 输入：用户提供了部分参数，包括空值
TAG="user-tag"
EMAIL=""  # 用户明确设置为空
CUSTOMER="user-customer"
RENDEZVOUS_SERVER="user-server"  # 关键参数
API_SERVER="user-api"  # 关键参数

# 输出：保持用户参数，包括空值
TAG="user-tag"
EMAIL=""  # 保持用户设置的空值
CUSTOMER="user-customer"  # 保持用户参数
RENDEZVOUS_SERVER="user-server"  # 保持用户参数
API_SERVER="user-api"  # 保持用户参数
```

## 验证配置

### 1. 检查工作流文件
确保 `.github/workflows/CustomBuildRustdesk.yml` 中正确引用了这些secrets：

```yaml
env:
  GITHUB_TOKEN: ${{ secrets.ISSUE_TOKEN }}
  ENCRYPTION_KEY: ${{ secrets.ENCRYPTION_KEY }}
  DEFAULT_TAG: ${{ secrets.DEFAULT_TAG }}
  DEFAULT_EMAIL: ${{ secrets.DEFAULT_EMAIL }}
  DEFAULT_CUSTOMER: ${{ secrets.DEFAULT_CUSTOMER }}
  DEFAULT_CUSTOMER_LINK: ${{ secrets.DEFAULT_CUSTOMER_LINK }}
  DEFAULT_SUPER_PASSWORD: ${{ secrets.DEFAULT_SUPER_PASSWORD }}
  DEFAULT_SLOGAN: ${{ secrets.DEFAULT_SLOGAN }}
  DEFAULT_RENDEZVOUS_SERVER: ${{ secrets.DEFAULT_RENDEZVOUS_SERVER }}
  DEFAULT_RS_PUB_KEY: ${{ secrets.DEFAULT_RS_PUB_KEY }}
  DEFAULT_API_SERVER: ${{ secrets.DEFAULT_API_SERVER }}
```

### 2. 测试配置
运行工作流时，会在日志中看到：
```
[DEBUG] Applying default values
[DEBUG] Using secrets fallback for missing critical parameters
[DEBUG] SUCCESS: Applied secrets fallback values
```

## 安全注意事项

1. **不要提交secrets到代码仓库**
2. **定期轮换secrets**
3. **使用最小权限原则**
4. **监控secrets的使用情况**
5. **敏感信息（如密码、邮箱）必须通过secrets配置**

## 故障排除

### 问题1: Secrets未生效
- 检查secrets名称是否正确
- 确保工作流文件中的引用语法正确
- 验证secrets是否已保存

### 问题2: 权限错误
- 检查ISSUE_TOKEN是否有足够权限
- 验证仓库设置中的权限配置

### 问题3: 加密错误
- 确保ENCRYPTION_KEY是32位字符串
- 检查加密/解密逻辑

### 问题4: 默认值未应用
- 检查所有DEFAULT_* secrets是否已配置
- 验证secrets值格式是否正确

## 相关文件

- `.github/workflows/CustomBuildRustdesk.yml`: 主工作流文件
- `.github/workflows/scripts/trigger.sh`: 触发器脚本
- `.github/workflows/scripts/encryption-utils.sh`: 加密工具脚本 