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

---

## 成功案例：v0.4.3 发布

**日期**：2026-04-08

**操作步骤**：

```bash
# 1. 切换到 main 并更新
git checkout main
git pull origin main

# 2. 更新版本号
# 编辑 pyproject.toml: version = "0.4.3"

# 3. 提交并创建 tag
git add pyproject.toml
git commit -m "chore: bump version to 0.4.3"
git tag -a v0.4.3 -m "Release v0.4.3"

# 4. 推送
git push origin main
git push origin v0.4.3
```

**结果**：
- ✅ GitHub Actions 自动触发
- ✅ 3 分钟内完成所有发布包构建
- ✅ Release 成功发布：https://github.com/rj-wangbin6/spec-kit/releases/tag/v0.4.3

---

## 参考资源

- [语义化版本规范](https://semver.org/lang/zh-CN/)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [Git Tag 文档](https://git-scm.com/book/zh/v2/Git-基础-打标签)
- 项目内部文档：
  - `.github/workflows/RELEASE-PROCESS.md` - 详细的工作流说明
  - `.github/workflows/release.yml` - Release 工作流配置
  - `.github/workflows/release-trigger.yml` - Release Trigger 工作流配置（备用）

---

**最后更新**：2026-04-08  
**文档版本**：1.0.0  
**适用版本**：Spec Kit v0.4.3+

