#!/bin/bash
# hybrid-lock.sh: 简单的文件锁实现，无颜色输出

# 获取锁
acquire_lock() {
    local lock_file="$1"
    local max_wait="${2:-30}"
    local waited=0
    while [ -f "$lock_file" ]; do
        echo "[LOCK] $lock_file 已被占用，等待... ($waited/$max_wait 秒)"
        sleep 1
        waited=$((waited+1))
        if [ "$waited" -ge "$max_wait" ]; then
            echo "[LOCK] 等待超时，无法获取锁: $lock_file"
            return 1
        fi
    done
    echo "[LOCK] 获取锁: $lock_file"
    touch "$lock_file"
    return 0
}

# 释放锁
release_lock() {
    local lock_file="$1"
    if [ -f "$lock_file" ]; then
        rm -f "$lock_file"
        echo "[LOCK] 释放锁: $lock_file"
    else
        echo "[LOCK] 无需释放，锁文件不存在: $lock_file"
    fi
}

# 用法说明
usage() {
    echo "用法: $0 acquire|release <lock_file> [max_wait]"
}

# 主逻辑
if [ "$#" -lt 2 ]; then
    usage
    exit 1
fi

cmd="$1"
lock_file="$2"
max_wait="$3"

case "$cmd" in
    acquire)
        acquire_lock "$lock_file" "$max_wait"
        ;;
    release)
        release_lock "$lock_file"
        ;;
    *)
        usage
        exit 1
        ;;
esac 
