#!/bin/bash

# spec-kit HTTP文件服务器停止脚本
# 安装位置：/opt/spec-kit-server/stop-server.sh

PID_FILE="/opt/spec-kit-server/server.pid"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查PID文件是否存在
if [ ! -f "$PID_FILE" ]; then
    echo -e "${YELLOW}服务未运行或PID文件不存在${NC}"
    echo "PID文件路径: $PID_FILE"
    exit 1
fi

# 读取PID
PID=$(cat "$PID_FILE")

# 检查进程是否存在
if ps -p "$PID" > /dev/null 2>&1; then
    echo "正在停止服务 (PID: $PID)..."
    
    # 尝试优雅关闭
    kill "$PID"
    
    # 等待进程结束
    TIMEOUT=5
    while [ $TIMEOUT -gt 0 ] && ps -p "$PID" > /dev/null 2>&1; do
        sleep 1
        TIMEOUT=$((TIMEOUT-1))
    done
    
    # 如果进程还在运行，强制杀死
    if ps -p "$PID" > /dev/null 2>&1; then
        echo -e "${YELLOW}进程未响应，强制终止...${NC}"
        kill -9 "$PID"
        sleep 1
    fi
    
    # 最终检查
    if ps -p "$PID" > /dev/null 2>&1; then
        echo -e "${RED}✗ 无法停止服务 (PID: $PID)${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ 服务已成功停止${NC}"
        rm "$PID_FILE"
    fi
else
    echo -e "${YELLOW}进程不存在 (PID: $PID)，清理PID文件${NC}"
    rm "$PID_FILE"
fi

echo "服务已完全停止"
