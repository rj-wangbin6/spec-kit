# 开发者信息收集工具

AI驱动的两步式工作流工具，用于Code Review前的信息准备：
1. **步骤1**: 扫描Git项目，收集仓库信息和开发者列表
2. **步骤2**: AI读取步骤1输出 → 校准参数 → 收集提交记录

## 快速开始

### 步骤1：收集仓库信息

```powershell
# AI执行：扫描当前目录（默认3层深度）
python scripts/collect_info.py --pretty

# 指定目录和深度
python scripts/collect_info.py --base-dir "D:\projects" --depth 2
```

**输出**: `developer_info_20260306_144530.json`
- 包含所有仓库的基本信息
- **包含contributors列表**（供AI校准开发者名称）

### 步骤2：收集提交记录（AI传参模式）

**工作方式**：AI读取步骤1的JSON → 提取仓库信息 → 通过参数传递

```powershell
# AI根据步骤1的JSON，针对每个仓库分别调用
# 示例：用户说"查看张三的提交" → AI查contributors → 传"zhangsan"
python scripts/collect_commits.py \
  --repo-path "D:/projects/my-service" \
  --repo-name "my-service" \
  --repo-url "https://github.com/company/my-service.git" \
  --author "zhangsan" \
  --since "2026-03-01" \
  --pretty
```

**输出**: `commits_my-service_20260306_150030.json`（单个仓库的提交记录）

**关键点**：
- ❌ 步骤2不再读取JSON文件
- ✅ AI负责参数校准（根据contributors）
- ✅ 多个仓库需AI多次调用

## 主要功能

**步骤1 - 仓库信息收集**：
- ✅ 自动扫描目录及子目录找到所有Git项目（最多5层深度）
- ✅ 提取Git用户配置（用户名、邮箱、Git版本）
- ✅ 获取每个项目的远程仓库地址和项目名
- ✅ 检测当前分支名称
- ✅ 检查本地是否有未提交的修改
- ✅ 获取最近一次提交信息（作者、时间、提交信息）
- ✅ **收集所有提交者列表（contributors，供AI参数校准）**
- ✅ 输出结构化JSON数据

**步骤2 - 提交记录收集（AI驱动）**：
- ✅ AI读取步骤1的JSON，提取仓库信息通过参数传递
- ✅ AI根据contributors校准开发者名称（如：张三 → zhangsan）
- ✅ 支持按时间范围筛选（--since, --until）
- ✅ 支持按提交者筛选（--author）
- ✅ 单次处理一个仓库（多仓库由AI编排）
- ✅ 统计代码变更量（文件数、插入行、删除行）
- ✅ 支持限制提交数量（--max-count）
- ✅ 输出结构化JSON数据

## 使用场景

**Code Review 信息准备**：
- 快速识别谁在做 review（当前开发者）
- 识别 review 哪个项目（服务名、仓库地址）
- 了解项目当前状态（分支、修改状态）
- **避免参数错误**（AI自动校准开发者名称）
- 查看特定时间段的提交历史
- 统计代码变更量和活跃度

## 输出示例

### 步骤1 输出（仓库信息）

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

### 步骤2 输出（提交记录）

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

## 参数说明

### 步骤1 参数（collect_info.py）

| 参数 | 简写 | 说明 | 默认值 |
|------|------|------|--------|
| `--base-dir` | `-d` | 扫描的基础目录 | 当前目录 |
| `--depth` | - | 扫描深度（1-5层） | 3 |
| `--output` | `-o` | 输出JSON文件路径 | `developer_info_{timestamp}.json` |
| `--pretty` | `-p` | 美化JSON输出 | False |
| `--verbose` | `-v` | 显示详细日志 | False |

### 步骤2 参数（collect_commits.py）

| 参数 | 简写 | 说明 | 默认值 |
|------|------|------|--------|
| `--repo-path` | - | 仓库路径（必需，AI从步骤1获取） | 无 |
| `--repo-name` | - | 仓库名称（必需，AI从步骤1获取） | 无 |
| `--repo-url` | - | 仓库URL（可选，AI从步骤1获取） | 空字符串 |
| `--author` | `-a` | 筛选提交者（AI根据contributors校准） | 所有提交者 |
| `--since` | `-s` | 开始日期（YYYY-MM-DD） | 无限制 |
| `--until` | `-u` | 结束日期（YYYY-MM-DD） | 无限制 |
| `--max-count` | `-n` | 最大提交数 | 无限制 |
| `--output` | `-o` | 输出JSON文件路径 | `commits_{repo-name}_{timestamp}.json` |
| `--pretty` | `-p` | 美化JSON输出 | False |
| `--verbose` | `-v` | 显示详细日志 | False |

## 注意事项

## 注意事项

**步骤1**：
- 需要Git命令行工具已安装并配置在PATH中
- 确保有权限访问待扫描的目录
- 如果未配置Git用户名/邮箱，会显示 "Unknown"
- 扫描深度过大可能导致扫描时间较长，建议根据实际目录结构调整
- Contributors列表用于AI参数校准，确保Git历史记录完整

**步骤2（AI行为）**：
- AI应先读取步骤1的JSON，再调用步骤2
- AI应根据contributors校准开发者名称（避免参数错误）
- 提交记录收集时间取决于仓库大小和时间范围
- 建议AI传递 `--since` 和 `--until` 限制时间范围
- 多个仓库需AI分别调用多次，每次处理一个仓库

**数据管理**：
- 步骤1的输出文件可供AI多次读取使用
- 步骤2针对每个仓库生成独立JSON文件
- 使用 `--pretty` 参数美化输出便于查看
- 输出文件默认带时间戳，避免覆盖

## 许可证

MIT
