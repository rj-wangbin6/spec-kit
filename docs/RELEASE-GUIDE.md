# Spec Kit 发布指南

> 本文档记录了 Spec Kit 项目的完整发布流程，包括版本管理、tag 创建和自动化发布。

## 📋 目录

- [发布流程概述](#发布流程概述)
- [前置条件](#前置条件)
- [标准发布流程](#标准发布流程)
- [自动化机制](#自动化机制)
- [验证发布](#验证发布)
- [常见问题](#常见问题)

---

## 发布流程概述

Spec Kit 使用基于 **Git Tag** 的自动化发布流程：

1. 开发者更新版本号并创建 Git Tag
2. Tag 推送到 GitHub 后自动触发 Release 工作流
3. 工作流构建所有代理的发布包并创建 GitHub Release

**核心原则**：一旦推送带有 `v*` 前缀的 tag，GitHub Actions 会自动完成剩余所有工作。

---

## 前置条件

### 必需条件

- [x] 有 `main` 分支的 push 权限
- [x] 所有代码改动已合并到 `main` 分支
- [x] 本地 git 仓库状态干净（无未提交的更改）

### 版本号规范

遵循语义化版本（Semantic Versioning）：

- **主版本号（Major）**：不兼容的 API 更改（例如：1.0.0 → 2.0.0）
- **次版本号（Minor）**：向后兼容的功能新增（例如：0.4.0 → 0.5.0）
- **修订号（Patch）**：向后兼容的问题修复（例如：0.4.2 → 0.4.3）

---

## 标准发布流程

### 步骤 1：确保在 main 分支上

```bash
# 切换到 main 分支
git checkout main

# 拉取最新代码
git pull origin main
```

### 步骤 2：更新版本号

编辑 `pyproject.toml` 文件，更新 `version` 字段：

```toml
[project]
name = "specify-cli"
version = "0.4.3"  # 更新这里
description = "Specify CLI, part of GitHub Spec Kit..."
```

### 步骤 3：提交版本更新

```bash
# 添加文件
git add pyproject.toml

# 提交（使用规范的提交信息）
git commit -m "chore: bump version to 0.4.3"
```

### 步骤 4：创建 Git Tag

```bash
# 创建带注释的 tag（推荐）
git tag -a v0.4.3 -m "Release v0.4.3"

# 或者创建简单 tag
git tag v0.4.3
```

**重要**：tag 名称必须以 `v` 开头（例如：`v0.4.3`），这样才能触发 Release 工作流。

### 步骤 5：推送到 GitHub

```bash
# 推送提交和 tag（一条命令）
git push origin main && git push origin v0.4.3

# 或者分开推送
git push origin main
git push origin v0.4.3
```

### 步骤 6：等待自动化发布

推送 tag 后，GitHub Actions 会自动：

1. ✅ 检测到 tag push
2. ✅ 触发 `Create Release` 工作流
3. ✅ 为所有支持的 AI 代理构建发布包（bash 和 PowerShell 版本）
4. ✅ 生成 Release Notes（从 git 提交历史）
5. ✅ 创建 GitHub Release 并上传所有资源包

**通常需要 3-5 分钟完成。**

### 步骤 7：同步到内网服务器（可选）

如果需要将新版本同步到内网服务器，在 Actions 完成后执行：

#### 7.1 运行服务器同步脚本

通过 SSH 远程执行同步脚本：

```bash
# 方式一：直接执行同步脚本（推荐）
ssh root@172.16.37.100 "cd /opt/spec-kit-packages/sync-workspace/spec-kit-repo && bash 内网同步方案/scripts/sync-spec-kit.sh"

# 方式二：如果已配置定时任务，可以手动触发
ssh root@172.16.37.100 "/opt/spec-kit-packages/sync-workspace/sync-spec-kit.sh"
```

同步脚本会自动完成：
- ✅ 拉取最新代码（包含新的 tag）
- ✅ 构建 wheel 包
- ✅ 下载跨平台依赖（Windows/macOS/Linux，Python 3.11/3.12/3.13）
- ✅ 更新发布目录

**预期输出示例：**
```
========================================
Spec Kit同步开始: 2026-04-13 09:30:07
========================================
[1/6] 检查GitHub连通性...
✓ GitHub连接正常
[2/6] 拉取最新代码...
✓ 更新成功: 15dd55b -> 88e4593
[3/6] 构建wheel包...
Successfully built dist/specify_cli-0.0.78-py3-none-any.whl
[4/6] 更新spec-kit包...
✓ 已复制: specify_cli-0.0.78-py3-none-any.whl
[5/7] 更新Windows依赖...
✓ Windows依赖更新完成
[6/7] 更新macOS依赖...
✓ macOS依赖更新完成
[7/7] 同步完成统计...
========================================
同步完成摘要:
  - Commit版本: 88e4593
  - Wheel包: specify_cli-0.0.78-py3-none-any.whl
  - 项目包大小: 2.1M
  - 依赖包数量: 36 个
  - 依赖包大小: 5.5M
  - 完成时间: 2026-04-13 09:31:24
========================================
```

#### 7.2 更新服务器文档

更新内网服务器的文档页面（index.html、CHANGELOG.html、INSTALL.html）：

```bash
# 上传更新后的文档文件
scp "内网同步方案/scripts/index.html" \
    "内网同步方案/scripts/INSTALL.html" \
    "内网同步方案/scripts/CHANGELOG.html" \
    root@172.16.37.100:/opt/spec-kit-packages/

# 验证文件已更新
ssh root@172.16.37.100 "ls -lh /opt/spec-kit-packages/*.html"
```

#### 7.3 验证服务器部署

确认新版本已成功部署：

```bash
# 检查 wheel 包
ssh root@172.16.37.100 "ls -lh /opt/spec-kit-packages/packages/spec-kit/*.whl | tail -1"

# 验证版本号（通过 HTTP 服务）
ssh root@172.16.37.100 "curl -s http://127.0.0.1:9999/index.html | grep -A 2 '当前版本'"

# 验证 CHANGELOG 更新
ssh root@172.16.37.100 "curl -s http://127.0.0.1:9999/CHANGELOG.html | grep -A 5 'v0.0.78'"
```

**服务访问地址：**
- 首页：http://172.16.37.100:9999/index.html
- 安装指南：http://172.16.37.100:9999/INSTALL.html  
- 变更日志：http://172.16.37.100:9999/CHANGELOG.html
- 项目包：http://172.16.37.100:9999/packages/spec-kit/
- 依赖包：http://172.16.37.100:9999/packages/dependencies/

---

## 自动化机制

### Release 工作流触发器

位于 `.github/workflows/release.yml`：

```yaml
on:
  push:
    tags:
      - 'v*'    # 任何以 v 开头的 tag
      - 'r*'    # 任何以 r 开头的 tag
```

### 构建的发布包

每次发布会创建以下包（针对所有支持的 AI 代理）：

- `spec-kit-template-{agent}-sh-{version}.zip` - Bash 脚本版本
- `spec-kit-template-{agent}-ps-{version}.zip` - PowerShell 脚本版本

**支持的代理**：
claude, gemini, copilot, cursor-agent, qwen, opencode, codex, windsurf, junie, kilocode, auggie, codebuddy, qodercli, roo, kiro-cli, amp, shai, tabnine, agy, bob, vibe, kimi, trae, pi, iflow

---

## 验证发布

### 1. 检查 Actions 运行状态

访问：https://github.com/rj-wangbin6/spec-kit/actions

- 查找 **Create Release** 工作流
- 确认状态为 ✅ 成功（绿色对勾）

### 2. 验证 Release 创建

访问：https://github.com/rj-wangbin6/spec-kit/releases

确认新 Release 包含：

- ✅ 正确的版本号标签（例如：v0.4.3）
- ✅ Release Notes（自动生成的变更日志）
- ✅ 所有代理的发布包（50+ 个 zip 文件）

### 3. 测试安装

选择一个发布包测试安装：

```bash
# 下载并解压
wget https://github.com/rj-wangbin6/spec-kit/releases/download/v0.4.3/spec-kit-template-claude-sh-0.4.3.zip
unzip spec-kit-template-claude-sh-0.4.3.zip

# 运行初始化脚本
cd spec-kit-template-claude-sh-0.4.3
./init.sh
```

### 4. 验证内网服务器部署（如果执行了步骤 7）

如果已同步到内网服务器，确认以下内容：

```bash
# 检查最新的 wheel 包是否存在
ssh root@172.16.37.100 "ls -lh /opt/spec-kit-packages/packages/spec-kit/*.whl | tail -1"
# 预期输出包含新版本号，例如：specify_cli-0.0.78-py3-none-any.whl

# 验证首页显示的版本号
ssh root@172.16.37.100 "curl -s http://127.0.0.1:9999/index.html | grep -A 2 '当前版本'"
# 预期输出：v0.0.78

# 或通过浏览器访问
# http://172.16.37.100:9999/index.html
```

**内网安装测试（可选）：**

```bash
# 在内网机器上测试离线安装
uv tool install specify-cli \
  --find-links http://172.16.37.100:9999/packages/spec-kit \
  --find-links http://172.16.37.100:9999/packages/dependencies \
  --no-index \
  --upgrade

# 验证安装的版本
specify version
# 应显示新版本号
```

---

## 常见问题

### Q1: 如果 tag 已经存在怎么办？

如果不小心创建了重复的 tag：

```bash
# 删除本地 tag
git tag -d v0.4.3

# 删除远程 tag
git push origin --delete v0.4.3

# 重新创建
git tag -a v0.4.3 -m "Release v0.4.3"
git push origin v0.4.3
```

### Q2: 发布工作流失败了怎么办？

1. 访问 Actions 页面查看错误日志
2. 修复问题后，可以手动重新运行工作流：
   - 点击失败的工作流
   - 点击右上角 "Re-run jobs"

### Q3: 如何发布热修复版本？

对于紧急修复：

```bash
# 从 main 创建热修复分支
git checkout -b hotfix/v0.4.4

# 修复问题
# ... 编辑代码 ...

# 提交修复
git add .
git commit -m "fix: critical bug fix"

# 合并回 main
git checkout main
git merge hotfix/v0.4.4

# 更新版本号并发布
# ... 按照标准流程 ...
```

### Q4: 版本号写错了怎么办？

如果还没有推送：

```bash
# 撤销最后一次提交（保留更改）
git reset --soft HEAD~1

# 修改版本号
# 编辑 pyproject.toml

# 重新提交
git add pyproject.toml
git commit -m "chore: bump version to 0.4.4"
```

如果已经推送但还没打 tag，直接再次提交修正即可。

### Q5: 可以删除已发布的 Release 吗？

可以，但不推荐：

1. 在 Releases 页面找到要删除的版本
2. 点击 "Delete" 按钮
3. 同时删除对应的 git tag（见 Q1）

**注意**：已下载使用该版本的用户不受影响。

### Q6: 内网服务器同步失败怎么办？

如果同步脚本执行失败，检查以下几点：

```bash
# 1. 检查服务器网络连通性
ssh root@172.16.37.100 "ping -c 3 github.com"

# 2. 检查仓库状态
ssh root@172.16.37.100 "cd /opt/spec-kit-packages/sync-workspace/spec-kit-repo && git status"

# 3. 手动拉取最新代码
ssh root@172.16.37.100 "cd /opt/spec-kit-packages/sync-workspace/spec-kit-repo && git fetch origin main && git reset --hard origin/main"

# 4. 检查同步日志
ssh root@172.16.37.100 "ls -lt /opt/spec-kit-packages/logs/sync-*.log | head -1"
ssh root@172.16.37.100 "tail -50 \$(ls -t /opt/spec-kit-packages/logs/sync-*.log | head -1)"
```

### Q7: 如何回滚内网服务器版本？

如果新版本有问题，可以回滚到旧版本：

```bash
# 1. 检查可用的历史版本
ssh root@172.16.37.100 "ls -lt /opt/spec-kit-packages/packages/spec-kit/"

# 2. 查看 git 历史
ssh root@172.16.37.100 "cd /opt/spec-kit-packages/sync-workspace/spec-kit-repo && git log --oneline -10"

# 3. 回滚到指定版本（例如 v0.0.77）
ssh root@172.16.37.100 "cd /opt/spec-kit-packages/sync-workspace/spec-kit-repo && git reset --hard v0.0.77"

# 4. 重新构建和部署
ssh root@172.16.37.100 "cd /opt/spec-kit-packages/sync-workspace/spec-kit-repo && bash 内网同步方案/scripts/sync-spec-kit.sh"
```

**注意**：历史 wheel 包会保留在 `/opt/spec-kit-packages/packages/spec-kit/` 目录中，用户可以选择安装特定版本。

---

## 发布清单

使用此清单确保每次发布顺利：

- [ ] 所有测试通过（本地运行 `pytest`）
- [ ] 代码已合并到 `main` 分支
- [ ] 更新 `pyproject.toml` 中的版本号
- [ ] 更新 `CHANGELOG.md`（可选，Release Notes 会自动生成）
- [ ] 提交版本更新：`git commit -m "chore: bump version to X.Y.Z"`
- [ ] 创建 tag：`git tag -a vX.Y.Z -m "Release vX.Y.Z"`
- [ ] 推送到 GitHub：`git push origin main && git push origin vX.Y.Z`
- [ ] 等待 GitHub Actions 完成（3-5 分钟）
- [ ] 验证 Release 页面有新版本
- [ ] 测试至少一个发布包
- [ ] **（可选）** 同步到内网服务器
  - [ ] 运行服务器同步脚本
  - [ ] 更新服务器文档（index.html、CHANGELOG.html、INSTALL.html）
  - [ ] 验证内网服务器部署（检查版本号和 wheel 包）
  - [ ] 测试内网离线安装

---

## 成功案例：v0.0.78 发布

**日期**：2026-04-13

**变更内容**：更新 developer-info-collector 技能

**操作步骤**：

```bash
# 1. 切换到 main 并更新
git checkout main
git pull origin main

# 2. 更新版本号和 CHANGELOG
# 编辑 pyproject.toml: version = "0.0.78"
# 编辑 CHANGELOG.md: 添加 v0.0.78 记录

# 3. 提交并创建 tag
git add pyproject.toml CHANGELOG.md
git commit -m "chore: bump version to 0.0.78"
git tag -a v0.0.78 -m "Release v0.0.78"

# 4. 推送到 GitHub
git push origin main
git push origin v0.0.78

# 5. 等待 GitHub Actions 完成（约 3-5 分钟）
# 访问：https://github.com/rj-wangbin6/spec-kit/actions

# 6. 同步到内网服务器
ssh root@172.16.37.100 "cd /opt/spec-kit-packages/sync-workspace/spec-kit-repo && bash 内网同步方案/scripts/sync-spec-kit.sh"

# 7. 更新服务器文档
scp "内网同步方案/scripts/index.html" \
    "内网同步方案/scripts/INSTALL.html" \
    "内网同步方案/scripts/CHANGELOG.html" \
    root@172.16.37.100:/opt/spec-kit-packages/

# 8. 验证内网部署
ssh root@172.16.37.100 "curl -s http://127.0.0.1:9999/index.html | grep -A 2 '当前版本'"
```

**结果**：
- ✅ GitHub Actions 自动触发并成功完成
- ✅ Release 成功发布：https://github.com/rj-wangbin6/spec-kit/releases/tag/v0.0.78
- ✅ 内网服务器同步完成
  - Commit 版本：88e4593
  - Wheel 包：specify_cli-0.0.78-py3-none-any.whl
  - 项目包大小：2.1M
  - 依赖包数量：36 个
  - 依赖包大小：5.5M
- ✅ 服务器文档已更新（http://172.16.37.100:9999）
- ✅ 内网离线安装测试通过

---

## 参考资源

- [语义化版本规范](https://semver.org/lang/zh-CN/)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [Git Tag 文档](https://git-scm.com/book/zh/v2/Git-基础-打标签)
- 项目内部文档：
  - `.github/workflows/RELEASE-PROCESS.md` - 详细的工作流说明
  - `.github/workflows/release.yml` - Release 工作流配置
  - `.github/workflows/release-trigger.yml` - Release Trigger 工作流配置（备用）
  - `内网同步方案/内网同步方案.md` - 内网服务器部署和同步方案
  - `内网同步方案/scripts/README.md` - 服务器脚本使用说明

---

**最后更新**：2026-04-13  
**文档版本**：1.1.0  
**适用版本**：Spec Kit v0.0.78+

