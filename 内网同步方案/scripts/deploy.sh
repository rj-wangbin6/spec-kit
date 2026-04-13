#!/bin/bash

# spec-kit 离线包分发系统 - 快速部署脚本
# 用途：一键创建所有必要的目录和脚本
# 使用方法：在服务器上执行 bash deploy.sh

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo -e "${BLUE}spec-kit 离线包分发系统 - 快速部署${NC}"
echo "========================================"
echo ""

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用root用户运行此脚本${NC}"
    exit 1
fi

# 步骤1: 创建目录结构
echo -e "${YELLOW}[1/5] 创建目录结构...${NC}"

# spec-kit包服务根目录
mkdir -p /opt/spec-kit-packages/packages/spec-kit
mkdir -p /opt/spec-kit-packages/packages/dependencies
mkdir -p /opt/spec-kit-packages/sync-workspace/spec-kit-repo
mkdir -p /opt/spec-kit-packages/sync-workspace/temp-deps
mkdir -p /opt/spec-kit-packages/logs

# 服务器管理目录
mkdir -p /opt/spec-kit-server

echo -e "${GREEN}✓ 目录创建完成${NC}"
echo "  /opt/spec-kit-packages/"
echo "  /opt/spec-kit-server/"
echo ""

# 步骤2: 设置权限
echo -e "${YELLOW}[2/5] 设置目录权限...${NC}"
chmod 755 /opt/spec-kit-packages/packages
chmod 755 /opt/spec-kit-packages/sync-workspace
chmod 755 /opt/spec-kit-packages/logs
chmod 755 /opt/spec-kit-server
echo -e "${GREEN}✓ 权限设置完成${NC}"
echo ""

# 步骤3: 创建启动脚本
echo -e "${YELLOW}[3/5] 创建HTTP服务启动脚本...${NC}"

# 从当前目录复制脚本（如果存在）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/start-server.sh" ]; then
    cp "$SCRIPT_DIR/start-server.sh" /opt/spec-kit-server/
    chmod +x /opt/spec-kit-server/start-server.sh
    echo -e "${GREEN}✓ 已复制 start-server.sh${NC}"
else
    echo -e "${YELLOW}! 未找到 start-server.sh，请手动创建${NC}"
fi

if [ -f "$SCRIPT_DIR/stop-server.sh" ]; then
    cp "$SCRIPT_DIR/stop-server.sh" /opt/spec-kit-server/
    chmod +x /opt/spec-kit-server/stop-server.sh
    echo -e "${GREEN}✓ 已复制 stop-server.sh${NC}"
else
    echo -e "${YELLOW}! 未找到 stop-server.sh，请手动创建${NC}"
fi

echo ""

# 步骤4: 检查依赖工具
echo -e "${YELLOW}[4/5] 检查依赖工具...${NC}"

# 检查Git
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | cut -d' ' -f3)
    echo -e "${GREEN}✓ Git ${GIT_VERSION}${NC}"
else
    echo -e "${RED}✗ Git未安装${NC}"
    echo "  安装命令: apt-get install git -y"
fi

# 检查Python
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    echo -e "${GREEN}✓ Python ${PYTHON_VERSION}${NC}"
else
    echo -e "${RED}✗ Python3未安装${NC}"
    echo "  安装命令: apt-get install python3 -y"
fi

# 检查uv
if command -v uv &> /dev/null; then
    UV_VERSION=$(uv --version | cut -d' ' -f2)
    echo -e "${GREEN}✓ uv ${UV_VERSION}${NC}"
else
    echo -e "${YELLOW}! uv未安装（需要手动安装）${NC}"
    echo "  安装命令: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

echo ""

# 步骤5: 测试端口
echo -e "${YELLOW}[5/5] 检查端口可用性...${NC}"

# 检查9999端口
if netstat -tuln 2>/dev/null | grep -q ":9999 "; then
    echo -e "${RED}✗ 端口9999已被占用${NC}"
    netstat -tuln | grep ":9999 "
else
    echo -e "${GREEN}✓ 端口9999可用${NC}"
fi

# 检查8888端口（现有服务）
if netstat -tuln 2>/dev/null | grep -q ":8888 "; then
    echo -e "${GREEN}✓ 端口8888运行正常（现有服务）${NC}"
else
    echo -e "${YELLOW}! 端口8888未监听（现有服务未启动？）${NC}"
fi

echo ""
echo "========================================"
echo -e "${GREEN}部署完成！${NC}"
echo "========================================"
echo ""
echo "下一步操作："
echo ""
echo "1. 安装uv工具（如果未安装）："
echo "   curl -LsSf https://astral.sh/uv/install.sh | sh"
echo "   source \$HOME/.cargo/env"
echo ""
echo "2. 启动HTTP服务："
echo "   /opt/spec-kit-server/start-server.sh"
echo ""
echo "3. 创建同步脚本："
echo "   编辑 /opt/spec-kit-packages/sync-workspace/sync-spec-kit.sh"
echo ""
echo "4. 配置定时任务："
echo "   crontab -e"
echo "   添加: 0 * * * * /opt/spec-kit-packages/sync-workspace/sync-spec-kit.sh"
echo ""
echo "5. 手动测试同步："
echo "   cd /opt/spec-kit-packages/sync-workspace"
echo "   bash sync-spec-kit.sh"
echo ""
echo "访问地址: http://172.16.37.100:9999"
echo ""
