---
name: developer-info-collector
description: 开发者信息收集工具。两步式工作流：1) 扫描Git项目收集仓库信息，2) 基于仓库信息收集提交记录。主要用于Code Review前的信息准备，快速识别review者、被review者和项目归属。
version: 2.0
license: MIT
---

# 红线无论如何必须遵守
1. 禁止生成脚本后执行
2. 禁止直接执行git命令
3. 过滤提交记录时,必须使用第一步获取的结果中的用户
4. 遇到问题你需要停下来确认,禁止任何情况下的盲目执行


# 开发者信息收集技能

## 技能用途

自动收集开发者和项目信息，用于Code Review场景：
- **识别 review 执行者**：当前开发者的Git配置信息
- **识别被 review 的代码**：提交者信息、分支状态、提交历史
- **识别项目归属**：服务名、仓库地址




**核心能力（两步工作流）**：

**步骤1 - 仓库信息收集**：
- 自动扫描目录及子目录（指定2层深度）找到所有Git项目
- 提取Git用户配置（用户名、邮箱）
- 获取每个项目的远程仓库地址和项目名
- 检测当前分支和本地修改状态
- 输出JSON数据到控制台

**步骤2 - 提交记录收集**：
- 基于步骤1的仓库信息
- 必须完整读取控制台输出的JSON,读取没有到最后一个字符禁止进行下一步
- 收集指定时间范围的提交记录
- 支持按提交者筛选
- 统计代码变更量（文件数、插入行、删除行）
- 输出JSON数据到控制台
- 必须遍历第一步所有仓库获取提交记录,除非用户明确指定只关注某个仓库

## 核心工具

**两步式脚本**：
- **步骤1**：`.claude/skills/developer-info-collector/scripts/collect_info.py` - 收集仓库信息
- **步骤2**：`.claude/skills/developer-info-collector/scripts/collect_commits.py` - 收集提交记录

## 使用方法

### 完整工作流

```powershell
# ========== 步骤1: 扫描仓库信息 ==========
# AI执行：扫描当前目录（默认深度3层）
python scripts/collect_info.py --pretty

# 输出示例: developer_info_20260306_144530.json
# AI读取此JSON文件，加载到上下文中

# ========== 步骤2: 收集提交记录 ==========  
# AI根据步骤1的JSON，针对每个仓库分别调用
# AI自动校准开发者名称（如：用户说"张三" → AI传"zhangsan"）

# 示例1：收集my-service仓库的zhangsan的提交
python scripts/collect_commits.py \
  --repo-path "D:/projects/my-service" \
  --repo-name "my-service" \
  --repo-url "https://github.com/company/my-service.git" \
  --author "zhangsan" \
  --since "2026-03-01" \
  --pretty

# 示例2：收集my-api仓库的lisi的提交
python scripts/collect_commits.py \
  --repo-path "D:/projects/my-api" \
  --repo-name "my-api" \
  --repo-url "https://github.com/company/my-api.git" \
  --author "lisi" \
  --since "2026-03-01" \
  --pretty

# 输出: commits_my-service_20260306_150030.json
# 输出: commits_my-api_20260306_150045.json
```

**关键变更（v2.0）**：
- ✅ 步骤1和步骤2都只输出JSON到控制台，不生成文件
- ✅ AI读取步骤1的JSON → 提取仓库信息 → 通过参数传递给步骤2
- ✅ AI负责开发者名称校准（根据contributors列表）
- ✅ 多个仓库需AI多次调用步骤2

### 步骤1 - 仓库信息收集

**脚本**: `collect_info.py`

**基本用法**:

```powershell
# 扫描当前目录（默认深度3层）
python scripts/collect_info.py

# 指定扫描目录
python scripts/collect_info.py --base-dir "D:\projects"

# 自定义扫描深度（1-5层）
python scripts/collect_info.py --depth 2

# 美化JSON输出
python scripts/collect_info.py --pretty
```

**参数说明**:

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--base-dir` `-d` | 扫描的基础目录 | 当前目录 |
| `--depth` | 扫描深度（1-5层） | 3 |
| `--pretty` `-p` | 美化JSON输出 | False |
| `--verbose` `-v` | 显示详细日志 | False |

**输出数据结构**:

```json
{
  "scan_time": "2026-03-06 14:30:00",
  "base_directory": "D:/projects",
  "scan_depth": 3,
  "developer": {
    "name": "zhangsan",
    "email": "zhangsan@example.com",
    "git_version": "2.40.0"
  },
  "projects": [
    {
      "project_name": "my-service",
      "project_path": "D:/projects/my-service",
      "remote_url": "https://github.com/company/my-service.git",
      "current_branch": "feature/new-feature",
      "has_uncommitted_changes": true,
      "uncommitted_files": 3,
      "last_commit": {
        "hash": "abc123",
        "author": "lisi",
        "date": "2026-03-05 10:20:30",
        "message": "fix: 修复bug"
      },
      "contributors": [
        {"name": "zhangsan", "email": "zhangsan@example.com"},
        {"name": "lisi", "email": "lisi@example.com"},
        {"name": "wangwu", "email": "wangwu@example.com"}
      ]
    }
  ],
  "summary": {
    "total_projects": 5,
    "projects_with_changes": 2
  }
}
```

**contributors字段说明**：
- 列出该仓库所有提交过代码的开发者（按email去重）
- AI可根据此列表校准用户输入的开发者名称
- 例如：用户说"张三" → AI查找contributors → 匹配到"zhangsan" → 传给步骤2

### 步骤2 - 提交记录收集

**脚本**: `collect_commits.py`

**工作方式变更（v2.0）**：
- ✅ 只输出JSON到控制台，不生成文件
- ✅ AI读取步骤1的JSON后，通过命令行参数传递信息
- ✅ 单次只处理一个仓库（多仓库需AI多次调用）
- ✅ AI负责参数校准（如：用户说"张三" → AI传"zhangsan"）

**基本用法**:

```powershell
# AI从步骤1的JSON中读取仓库信息后，传递参数调用
python scripts/collect_commits.py --repo-path "D:/projects/my-service" --repo-name "my-service"

# AI根据contributors校准author参数，并添加时间范围
python scripts/collect_commits.py --repo-path "D:/projects/my-service" --repo-name "my-service" --author "zhangsan" --since "2026-03-01"

# AI传入URL（从步骤1的remote_url字段获取）用于输出展示
python scripts/collect_commits.py --repo-path "D:/projects/my-service" --repo-name "my-service" --repo-url "https://github.com/company/my-service.git" --author "zhangsan" --max-count 50 --pretty
```

**参数说明**:

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--repo-path` | 仓库路径（必需，AI从步骤1获取） | 无 |
| `--repo-name` | 仓库名称（必需，AI从步骤1获取） | 无 |
| `--repo-url` | 仓库URL（可选，AI从步骤1获取，用于输出展示） | 空字符串 |
| `--author` `-a` | 筛选提交者（AI根据contributors校准） | 所有提交者 |
| `--since` `-s` | 开始日期（YYYY-MM-DD） | 无限制 |
| `--until` `-u` | 结束日期（YYYY-MM-DD） | 无限制 |
| `--max-count` `-n` | 最大提交数 | 无限制 |

| `--pretty` `-p` | 美化JSON输出 | False |
| `--verbose` `-v` | 显示详细日志 | False |

**输出数据结构**:

```json
{
  "collection_time": "2026-03-06 15:00:00",
  "developer": {
    "name": "zhangsan",
    "email": "zhangsan@example.com"
  },
  "repository": {
    "name": "my-service",
    "path": "D:/projects/my-service",
    "url": "https://github.com/company/my-service.git",
    "current_branch": "feature/new-feature",
    "commits": [
      {
        "hash": "abc123d",
        "full_hash": "abc123def456...",
        "author_name": "zhangsan",
        "author_email": "zhangsan@example.com",
        "date": "2026-03-05 10:20:30",
        "message": "fix: 修复bug",
        "files_changed": 3,
        "insertions": 45,
        "deletions": 12
      }
    ],
    "total_commits": 15
  }
}
```

**数据结构说明**：
- `developer`: 当前执行者信息（从本地git config自动获取）
- `repository`: 单个仓库的提交记录
- 多个仓库需AI多次调用脚本，分别输出到控制台

## 执行步骤（两步工作流）

### 步骤1 执行流程

1. **扫描Git项目**
   - 从指定目录开始递归扫描（默认3层，最多5层）
   - 查找所有包含 `.git` 目录的项目
   - 记录每个项目的绝对路径

2. **获取开发者配置**
   - 执行 `git config user.name` 获取用户名
   - 执行 `git config user.email` 获取邮箱
   - 执行 `git --version` 获取Git版本

3. **收集项目信息**
   - 解析 `.git/config` 获取远程仓库地址
   - 从仓库URL提取项目名（支持HTTPS和SSH格式）
   - 执行 `git branch --show-current` 获取当前分支
   - 执行 `git status --porcelain` 检查本地修改状态
   - 执行 `git log -1` 获取最近一次提交信息
   - **执行 `git log --all --format='%an|%ae'` 获取所有提交者列表（按email去重）**

4. **数据聚合与输出**
   - 构建JSON数据结构（包含contributors）
   - 输出数据到控制台
   - 输出统计摘要到控制台

5. **异常处理**
   - 跳过无效的Git仓库（损坏或访问失败）
   - 记录警告信息但继续处理其他项目
   - 对缺失的配置使用默认值（"Unknown"）

### 步骤2 执行流程

1. **验证仓库参数**
   - 检查仓库路径是否存在
   - 验证是否为Git仓库（存在.git目录）
   - 获取当前分支信息

2. **获取开发者信息**
   - 从本地git config自动获取user.name和user.email
   - 用于标识谁在执行提交记录收集

3. **收集提交记录**
   - 根据筛选条件构建git log命令
   - 执行 `git log --pretty=format:...` 获取提交列表
   - 对每个提交执行 `git show --stat` 获取变更统计

4. **数据整理与输出**
   - 解析提交信息（hash、作者、日期、消息）
   - 提取变更统计（文件数、插入行、删除行）
   - 构建JSON数据结构（单个仓库）
   - 输出数据到控制台
   - 输出统计摘要到控制台

## 最佳实践

**步骤1 - 仓库扫描**：
- **目录选择**：在你的工作目录根目录运行，避免扫描系统目录
- **深度控制**：如果项目组织较深，适当增加 `--depth` 参数（最多5层）
- **定期执行**：项目结构变化时重新扫描
- **配置检查**：确保Git用户名和邮箱已正确配置
- **权限注意**：确保有权限访问所有待扫描的Git项目
- **Contributors用途**：输出的contributors列表供AI参数校准使用

**步骤2 - 提交收集（AI行为指南）**：
- **参数校准**：AI应根据contributors列表校准用户输入的开发者名称
- **时间范围**：合理设置 `--since` 和 `--until`，避免处理过多历史记录
- **URL传递**：建议从步骤1的remote_url字段获取并传入--repo-url参数
- **多仓库处理**：需要处理多个仓库时，AI应分别调用多次
- **参数来源**：所有仓库信息（path, name, url）都应从步骤1的JSON中读取
- **参数来源**：所有仓库信息（path, name, url）都应从步骤1的JSON中读取

**数据管理**：
- 步骤1和步骤2都输出JSON到控制台
- AI需读取并解析控制台输出的JSON数据
- 使用 `--pretty` 参数美化输出，便于阅读

## 输出规范

**步骤1 输出**：
- **输出位置**：控制台（JSON格式）
- **JSON格式**：默认紧凑格式，使用 `--pretty` 美化输出
- **路径格式**：统一使用正斜杠 `/`（跨平台兼容）
- **时间格式**：ISO 8601 格式 `YYYY-MM-DD HH:MM:SS`
- **Contributors**：按email去重，保留原始name和email

**步骤2 输出**：
- **输出位置**：控制台（JSON格式）
- **JSON格式**：默认紧凑格式，使用 `--pretty` 美化输出
- **时间格式**：ISO 8601 格式 `YYYY-MM-DD HH:MM:SS`
- **哈希格式**：默认显示短哈希（7位），完整哈希存储在 `full_hash` 字段
- **单仓库**：每次只输出一个仓库的数据

## 常见问题

### 步骤1 相关

**Q: 扫描时间过长怎么办？**  
A: 减小 `--depth` 参数2层，或指定更精确的 `--base-dir`

**Q: 找不到Git项目？**  
A: 检查目录路径是否正确，确保深度参数足够

**Q: 用户名显示为 "Unknown"？**  
A: 需要先配置Git：`git config --global user.name "你的名字"`

**Q: 远程仓库地址为空？**  
A: 该项目可能是本地仓库，未配置远程地址

**Q: Contributors列表为空？**  
A: 该仓库可能没有提交记录，或git log命令执行失败

### 步骤2 相关

**Q: 提交记录收集很慢？**  
A: 使用 `--since` 限制时间范围，或使用 `--max-count` 限制数量

**Q: 找不到某个仓库的提交？**  
A: 检查该仓库是否有提交记录，或者筛选条件是否过于严格

**Q: 变更统计数据不准确？**  
A: 某些类型的提交（如合并提交）统计可能不完整，属于正常现象

**Q: AI如何校准开发者名称？**  
A: AI应读取步骤1输出的contributors列表，匹配用户输入的名字到实际的Git提交者名称

**Q: 为什么不能直接读取JSON文件？**  
A: v2.0设计理念是让AI作为中间层，负责参数校准和多仓库编排，避免脚本处理复杂的参数映射逻辑

**Q: 如何处理多个仓库？**  
A: AI应针对每个仓库分别调用步骤2，生成独立的JSON文件

## 版本历史

- **v2.0** (2026-03-06) - AI驱动的两步工作流
  - **步骤1改进**: 新增contributors收集（所有提交者列表）
  - **步骤2重构**: 移除JSON文件依赖，改为参数传递模式
  - **新增**: AI负责开发者名称校准（根据contributors）
  - **新增**: 单仓库处理模式（多仓库由AI编排）
  - **新增**: 支持按时间范围筛选提交
  - **新增**: 支持按提交者筛选
  - **新增**: 提交变更统计（文件数、插入行、删除行）
  - **改进**: 步骤2从git config自动获取执行者信息
  - **破坏性变更**: 步骤2参数完全重构（需要AI传递所有参数）

- **v1.0** (2026-03-06) - 初始版本
  - 支持自动扫描Git项目
  - 收集开发者和项目基本信息
  - 输出JSON格式数据
