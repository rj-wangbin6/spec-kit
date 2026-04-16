# 内网同步方案 - 文件说明

本目录包含 Spec Kit 内网离线安装服务的所有脚本和文档。

## 📂 目录结构

```
内网同步方案/
├── log.md                    # 部署日志（重要历史记录）
├── 内网同步方案.md            # 方案设计文档（保留）
└── scripts/                   # 脚本和文档统一目录
    ├── deploy.sh             # 部署脚本
    ├── start-server.sh       # HTTP服务启动脚本
    ├── stop-server.sh        # HTTP服务停止脚本
    ├── sync-spec-kit.sh      # GitHub同步脚本
    ├── index.html            # 文档中心首页
    ├── INSTALL.html          # 安装指南（HTML）
    ├── QUICKREF.html         # 快速参考（HTML）
    ├── DEPLOYMENT-SUMMARY.html  # 部署摘要（HTML）
    └── FILES.md              # 本文档
```

## 🚀 服务器部署位置

### HTTP服务（9999端口）
```
/opt/spec-kit-packages/          # HTTP根目录
├── index.html                   # 文档中心首页
├── INSTALL.html                 # 安装指南
├── QUICKREF.html                # 快速参考
├── DEPLOYMENT-SUMMARY.html      # 部署摘要（HTML）
├── DEPLOYMENT-SUMMARY.md        # 部署摘要（Markdown，保留）
├── INSTALL.md                   # 安装指南（Markdown，保留）
├── QUICKREF.md                  # 快速参考（Markdown，保留）
├── packages/                    # 软件包目录
│   ├── spec-kit/               # 项目wheel包
│   └── dependencies/           # 依赖包
├── sync-workspace/             # GitHub同步工作区
├── logs/                       # 日志目录
```

### 服务控制脚本
```
/opt/spec-kit-server/
├── start-server.sh             # 启动HTTP服务
├── stop-server.sh              # 停止HTTP服务
└── sync-spec-kit.sh            # GitHub同步脚本
```

## 📄 文档说明

### HTML文档（推荐使用）
- **index.html** - 文档中心首页，提供所有文档的导航入口
- **INSTALL.html** - 完整的安装指南，包含详细步骤和常见问题
- **QUICKREF.html** - 快速参考卡片，提供常用命令速查
- **DEPLOYMENT-SUMMARY.html** - 部署摘要，包含服务器配置和维护信息

**优势**：
- ✅ UTF-8编码，浏览器直接打开无乱码
- ✅ 精美的样式和排版
- ✅ 更好的交互体验

### Markdown文档（保留）
- **INSTALL.md** - Markdown格式的安装指南
- **QUICKREF.md** - Markdown格式的快速参考
- **DEPLOYMENT-SUMMARY.md** - Markdown格式的部署摘要

**用途**：用于Git版本控制和编辑器查看

## 🌐 访问地址

用户可通过以下地址访问文档：

- **文档中心**: http://172.16.37.100:9999/
- **安装指南**: http://172.16.37.100:9999/INSTALL.html
- **快速参考**: http://172.16.37.100:9999/QUICKREF.html
- **部署摘要**: http://172.16.37.100:9999/DEPLOYMENT-SUMMARY.html

## 🔧 脚本使用说明

### sync-spec-kit.sh - GitHub同步脚本
自动从GitHub拉取最新代码并构建wheel包：
```bash
# 手动执行同步
/opt/spec-kit-server/sync-spec-kit.sh

# 自动同步（已配置cron）
# 每天凌晨2:00自动执行
```

### start-server.sh - 启动HTTP服务
```bash
/opt/spec-kit-server/start-server.sh
```

### stop-server.sh - 停止HTTP服务
```bash
/opt/spec-kit-server/stop-server.sh
```

## 📝 维护说明

### 更新HTML文档
1. 修改本地 `scripts/` 目录下的HTML文件
2. 使用SCP上传到服务器：
   ```bash
   scp scripts/*.html root@172.16.37.100:/opt/spec-kit-packages/
   ```

### 更新同步脚本
1. 修改本地 `scripts/sync-spec-kit.sh`
2. 上传到服务器：
   ```bash
   scp scripts/sync-spec-kit.sh root@172.16.37.100:/opt/spec-kit-server/
   ```
3. 确保脚本可执行：
   ```bash
   ssh root@172.16.37.100 "chmod +x /opt/spec-kit-server/sync-spec-kit.sh"
   ```

## ✅ 文件整理完成清单

- [x] 创建HTML版本的安装指南（INSTALL.html）
- [x] 创建HTML版本的快速参考（QUICKREF.html）
- [x] 创建文档中心首页（index.html）
- [x] 同步脚本移动到正确位置（sync-spec-kit.sh）
- [x] 所有文件上传到服务器
- [x] 验证文件可访问性

## 🔗 相关链接

- **服务器**: 172.16.37.100:9999
- **GitHub仓库**: https://github.com/rj-wangbin6/spec-kit
- **技术支持**: root@172.16.37.100

---

**最后更新**: 2026-04-08  
**维护者**: 系统管理员
