#!/bin/bash
# 加密/解密工具函数
# 这个文件包含 AES 加密/解密相关的函数
# AES 加密/解密函数
# ENCRYPTION_KEY workflow 通过 ${{ secrets.ENCRYPTION_KEY }} 传入环境变量
# 加密函数：将 JSON 数据加密为 base64 字符串
encrypt_params() {
  local json_data="$1"
  local encryption_key="${ENCRYPTION_KEY}"
  
  if [ -z "$json_data" ]; then
    echo "No data to encrypt"
    return 1
  fi
  
  if [ -z "$encryption_key" ]; then
    echo "ENCRYPTION_KEY not set"
    return 1
  fi
  
  local iv=$(openssl rand -hex 16)
  local encrypted=$(echo -n "$json_data" | openssl enc -aes-256-cbc -iv "$iv" -K "$encryption_key" -base64 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "Encryption failed"
    return 1
  fi
  echo "${iv}:${encrypted}"
}

# 解密函数：将加密的 base64 字符串解密为 JSON 数据
decrypt_params() {
  local encrypted_data="$1"
  local encryption_key="${ENCRYPTION_KEY}"
  
  if [ -z "$encrypted_data" ]; then
    echo "No data to decrypt"
    return 1
  fi
  
  if [ -z "$encryption_key" ]; then
    echo "ENCRYPTION_KEY not set"
    return 1
  fi
  
  local iv=$(echo "$encrypted_data" | cut -d: -f1)
  local encrypted=$(echo "$encrypted_data" | cut -d: -f2-)
  if [ -z "$iv" ] || [ -z "$encrypted" ]; then
    echo "Invalid encrypted data format"
    return 1
  fi
  local decrypted=$(echo "$encrypted" | openssl enc -aes-256-cbc -d -iv "$iv" -K "$encryption_key" -base64 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "Decryption failed"
    return 1
  fi
  echo "$decrypted"
}

# 生成新的加密密钥（用于初始化）
generate_encryption_key() {
  openssl rand -hex 32
}

# 创建包含加密参数的队列数据
create_encrypted_queue_data() {
  local queue_data="$1"
  local sensitive_params="$2"
  
  if [ -z "$queue_data" ]; then
    echo "Queue data not provided"
    return 1
  fi
  
  # 加密敏感参数
  local encrypted_params=""
  if [ -n "$sensitive_params" ]; then
    encrypted_params=$(encrypt_params "$sensitive_params" "${ENCRYPTION_KEY}")
    if [ $? -ne 0 ]; then
      echo "Failed to encrypt parameters"
      return 1
    fi
  fi
  
  # 创建包含加密参数的队列数据
  local final_queue_data
  if [ -n "$encrypted_params" ]; then
    final_queue_data=$(echo "$queue_data" | jq --arg encrypted "$encrypted_params" '. + {"encrypted_params": $encrypted}')
  else
    final_queue_data="$queue_data"
  fi
  
  echo "$final_queue_data"
} 
