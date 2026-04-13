#!/bin/bash

# spec-kit HTTP文件服务器启动脚本
# 端口：9999
# 工作目录：/opt/spec-kit-packages
# 安装位置：/opt/spec-kit-server/start-server.sh

PORT=9999
WORK_DIR="/opt/spec-kit-packages"
LOG_FILE="/opt/spec-kit-server/server.log"
PID_FILE="/opt/spec-kit-server/server.pid"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否已经运行
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo -e "${YELLOW}服务已经在运行中 (PID: $PID)${NC}"
        echo -e "访问地址: http://172.16.37.100:$PORT"
        exit 1
    else
        echo -e "${YELLOW}检测到残留PID文件，正在清理...${NC}"
        rm "$PID_FILE"
    fi
fi

# 检查工作目录是否存在
if [ ! -d "$WORK_DIR" ]; then
    echo -e "${RED}错误: 工作目录不存在: $WORK_DIR${NC}"
    echo "请先创建目录: mkdir -p $WORK_DIR"
    exit 1
fi

# 检查端口是否被占用
if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
    echo -e "${RED}错误: 端口 $PORT 已被占用${NC}"
    echo "请检查是否有其他服务占用该端口"
    netstat -tuln | grep ":$PORT "
    exit 1
fi

# 检查Python是否安装
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}错误: 未找到python3命令${NC}"
    exit 1
fi

# 启动服务
echo "========================================"
echo -e "${GREEN}spec-kit HTTP File Server${NC}"
echo "========================================"
echo "端口: $PORT"
echo "工作目录: $WORK_DIR"
echo "日志文件: $LOG_FILE"
echo "PID文件: $PID_FILE"
echo "========================================"

cd "$WORK_DIR" || exit 1
nohup python3 -m http.server $PORT --bind 0.0.0.0 > "$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > "$PID_FILE"

# 等待服务启动
sleep 1

# 验证服务是否成功启动
if ps -p "$SERVER_PID" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 服务启动成功！${NC}"
    echo "  PID: $SERVER_PID"
    echo "  访问地址: http://172.16.37.100:$PORT"
    echo ""
    echo "管理命令:"
    echo "  查看日志: tail -f $LOG_FILE"
    echo "  停止服务: /opt/spec-kit-server/stop-server.sh"
    echo "  检查状态: curl http://172.16.37.100:$PORT"
else
    echo -e "${RED}✗ 服务启动失败${NC}"
    echo "请查看日志: $LOG_FILE"
    rm "$PID_FILE"
    exit 1
fi
