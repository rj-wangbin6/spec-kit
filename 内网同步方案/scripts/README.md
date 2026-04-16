# spec-kit 离线包分发系统 - 服务器脚本

本目录包含用于在内网服务器上部署和管理spec-kit离线包分发系统的脚本。

## 📁 文件清单

### 核心脚本

| 文件 | 用途 | 安装位置 |
|------|------|----------|
| `deploy.sh` | 快速部署脚本，一键创建所有目录和配置 | 临时运行 |
| `start-server.sh` | HTTP服务启动脚本 | `/opt/spec-kit-server/` |
| `stop-server.sh` | HTTP服务停止脚本 | `/opt/spec-kit-server/` |

## 🚀 快速开始

### 步骤1: 上传脚本到服务器

```bash
# 方法A: 使用scp
scp -r scripts/* root@172.16.37.100:/tmp/spec-kit-scripts/

# 方法B: 使用git克隆
ssh root@172.16.37.100
cd /tmp
git clone https://github.com/rj-wangbin6/spec-kit.git
cd spec-kit/内网同步方案/scripts/
```

### 步骤2: 执行部署脚本

```bash
ssh root@172.16.37.100
cd /tmp/spec-kit-scripts/  # 或 /tmp/spec-kit/内网同步方案/scripts/

# 添加执行权限
chmod +x *.sh

# 运行部署脚本
bash deploy.sh
```

**部署脚本会自动完成：**
- ✅ 创建 `/opt/spec-kit-packages/` 目录结构
- ✅ 创建 `/opt/spec-kit-server/` 管理目录
- ✅ 复制启动/停止脚本
- ✅ 设置正确的权限
- ✅ 检查依赖工具
- ✅ 验证端口可用性

### 步骤3: 启动服务

```bash
# 启动HTTP服务（9999端口）
/opt/spec-kit-server/start-server.sh

# 验证服务运行
curl http://172.16.37.100:9999/

# 查看日志
tail -f /opt/spec-kit-server/server.log
```

### 步骤4: 管理服务

```bash
# 停止服务
/opt/spec-kit-server/stop-server.sh

# 重启服务
/opt/spec-kit-server/stop-server.sh && /opt/spec-kit-server/start-server.sh

# 查看PID
cat /opt/spec-kit-server/server.pid

# 检查进程
ps aux | grep "http.server.*9999"
```

## 📋 详细说明

### deploy.sh - 快速部署脚本

**功能：**
- 创建所有必要的目录结构
- 设置正确的权限
- 复制启动脚本到指定位置
- 检查依赖工具（Git、Python、uv）
- 验证端口可用性

**使用方法：**
```bash
# 必须使用root用户
sudo bash deploy.sh
```

**输出示例：**
```
========================================
spec-kit 离线包分发系统 - 快速部署
========================================

[1/5] 创建目录结构...
✓ 目录创建完成

[2/5] 设置目录权限...
✓ 权限设置完成

[3/5] 创建HTTP服务启动脚本...
✓ 已复制 start-server.sh
✓ 已复制 stop-server.sh

[4/5] 检查依赖工具...
✓ Git 2.34.1
✓ Python 3.10.12
! uv未安装（需要手动安装）

[5/5] 检查端口可用性...
✓ 端口9999可用
✓ 端口8888运行正常（现有服务）

========================================
部署完成！
========================================
```

---

### start-server.sh - 启动HTTP服务

**功能：**
- 启动Python http.server（9999端口）
- 检查端口是否被占用
- 记录进程PID
- 输出访问地址

**特性：**
- ✅ 自动检测服务是否已运行
- ✅ 端口冲突检测
- ✅ 启动成功验证
- ✅ 彩色输出便于识别

**使用方法：**
```bash
/opt/spec-kit-server/start-server.sh
```

**输出示例：**
```
========================================
spec-kit HTTP File Server
========================================
端口: 9999
工作目录: /opt/spec-kit-packages
日志文件: /opt/spec-kit-server/server.log
PID文件: /opt/spec-kit-server/server.pid
========================================
✓ 服务启动成功！
  PID: 12345
  访问地址: http://172.16.37.100:9999
```

---

### stop-server.sh - 停止HTTP服务

**功能：**
- 优雅地停止HTTP服务
- 超时后强制杀死进程
- 清理PID文件

**特性：**
- ✅ 优雅关闭（SIGTERM）
- ✅ 5秒超时后强制杀死（SIGKILL）
- ✅ 自动清理残留PID文件

**使用方法：**
```bash
/opt/spec-kit-server/stop-server.sh
```

**输出示例：**
```
正在停止服务 (PID: 12345)...
✓ 服务已成功停止
服务已完全停止
```

## 🔧 故障排查

### 问题1: 端口已被占用

**症状：**
```
错误: 端口 9999 已被占用
```

**解决方案：**
```bash
# 查找占用端口的进程
netstat -tuln | grep :9999
lsof -i :9999

# 杀死占用进程
kill <PID>

# 或者修改端口号（编辑start-server.sh中的PORT变量）
```

---

### 问题2: 权限不足

**症状：**
```
bash: /opt/spec-kit-server/start-server.sh: Permission denied
```

**解决方案：**
```bash
# 添加执行权限
chmod +x /opt/spec-kit-server/start-server.sh
chmod +x /opt/spec-kit-server/stop-server.sh
```

---

### 问题3: Python未找到

**症状：**
```
错误: 未找到python3命令
```

**解决方案：**
```bash
# Ubuntu/Debian
apt-get update
apt-get install python3 -y

# CentOS/RHEL
yum install python3 -y
```

---

### 问题4: 服务启动后立即退出

**检查日志：**
```bash
tail -20 /opt/spec-kit-server/server.log
```

**常见原因：**
- 工作目录不存在
- 端口被占用
- Python版本不兼容

## 📚 相关文档

- **完整方案文档：** `../内网同步方案.md`
- **服务器IP：** 172.16.37.100
- **服务端口：** 9999（spec-kit专用）
- **现有服务端口：** 8888（保持不变）

## 🆘 获取帮助

如遇问题，请检查：
1. `/opt/spec-kit-server/server.log` - 服务日志
2. `/opt/spec-kit-packages/logs/sync.log` - 同步日志
3. `crontab -l` - 定时任务配置

## 📝 版本信息

- **版本：** 1.0
- **更新日期：** 2026-04-08
- **兼容系统：** Ubuntu 22.04 LTS
