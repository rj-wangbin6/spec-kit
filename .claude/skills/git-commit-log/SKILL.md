---
name: git-commit-log
description: Git提交记录拉取工具。查看Git提交历史、分析提交记录、查看代码差异。支持自动查找仓库、多仓库扫描、代码diff展示。默认只输出到控制台，不创建临时文件。
license: MIT
---

# Git提交记录拉取技能

## 技能用途

查看和分析Git提交记录，包括提交历史、文件变更和代码差异（diff）。

**核心能力**：
- 自动查找当前目录及所有子目录中的Git仓库
- 支持多仓库批量操作（一次查询多个项目的提交）
- 智能深度控制（0=无限深度，找到所有Git项目）
- 显示完整的代码差异（diff）

## 核心工具

脚本位置：`.claude/skills/git-commit-log/scripts/git_commit_log.py`

## 使用方法

### 基本用法

```powershell
# 自动查找当前或父目录的Git仓库
python git_commit_log.py --author zhangsan --since "2025-12-24 00:00:00"

# 扫描多个仓库
python git_commit_log.py --scan-repos --author zhangsan --since 2025-12-24

# 指定仓库路径
python git_commit_log.py --repo C:\\projects\\myrepo --author zhangsan
```

### 常用参数

| 参数 | 说明 |
|------|------|
| `--author` `-a` | 作者（用户名或邮箱，推荐只用用户名） |
| `--since` `-s` | 开始日期（推荐只用since，不要用until） |
| `--scan-repos` | 扫描多个仓库 |
| `--base-dir` | 扫描的基础目录 |
| `--scan-depth` | 扫描深度（0=无限深度，1=只扫描当前目录，2=二级子目录，默认0） |
| `--format` `-f` | 输出格式（detailed/simple/oneline/json） |
| `--max-count` `-n` | 限制数量 |
| `--diff` | **显示代码差异（git diff）** |
| `--max-diff-lines` | 最大差异行数（默认500行） |
| `--stat-only` | 只显示统计 |
| `--save` | 保存到文件 |
| `--output` `-o` | 输出文件路径 |

### 最佳实践

**查找某人今天的提交：**
```powershell
python git_commit_log.py --scan-repos --author zhangsan --since "2025-12-24 00:00:00"
```

**查看提交并显示代码差异：**
```powershell
python git_commit_log.py --scan-repos --author zhangsan --since "2025-12-24" --diff
```

**快速浏览多个仓库：**
```powershell
python git_commit_log.py --scan-repos --author zhangsan --format simple --no-stats
```

**生成详细报告（包含代码差异）：**
```powershell
python git_commit_log.py --scan-repos --author zhangsan --since 2025-12-01 --diff --save --output report.txt
```

**查看特定提交的diff（限制行数）：**
```powershell
python git_commit_log.py --author zhangsan --since 2025-12-24 --diff --max-diff-lines 200
```

## 搜索逻辑说明

### 多仓库搜索策略

```
workspace/
  ├── project1/.git     ✅ 找到，加入列表（不深入project1内部）
  ├── project2/.git     ✅ 找到，加入列表
  ├── docs/             ⏭️ 不是git项目，继续递归
  │   └── project3/.git ✅ 找到，加入列表
  └── team/
      ├── alice/
      │   └── app/.git  ✅ 找到，加入列表
      └── bob/
          └── api/.git  ✅ 找到，加入列表

结果：找到5个Git仓库，全部处理 ✓
```

**关键点**：
- 🔍 会找到所有层级的Git仓库（不是只找一个）
- 🛑 找到某个仓库后，不再进入该仓库内部（避免扫描.git目录）
- ⚡ 自动跳过 node_modules、venv 等非代码目录
- 📊 `--scan-depth 0` 表示无限深度，找到所有Git项目

## 重要提示

- ✅ 作者搜索：用 `zhangsan` 而不是 `zhangsan@example.com`
- ✅ 日期查询：只用 `--since`，不要同时用 `--until`
- ✅ 多仓库：用 `--scan-repos` 自动扫描**所有**仓库
- ✅ **智能搜索**：从当前目录开始，递归搜索所有子目录
- ✅ **无限深度**：默认`--scan-depth 0`会搜索所有层级的git仓库
- ✅ 默认不保存文件，需要时用 `--save --output`
- ✅ 代码diff：添加 `--diff` 参数查看详细代码变更
- ⚠️ diff输出较大：建议配合 `--max-diff-lines` 限制行数
- ⚠️ diff影响性能：扫描多仓库时，加diff会变慢
- 💡 **优化搜索**：如果项目目录层级很深，可设置`--scan-depth 3`限制深度

## 故障排查

**未找到Git仓库：**
- 使用 `--scan-repos` 扫描多个仓库
- 使用 `--base-dir` 指定扫描目录

**未找到提交：**
- 检查作者名是否正确（只用用户名部分）
- 检查日期范围是否合理
- 使用 `--all-branches` 查看所有分支
