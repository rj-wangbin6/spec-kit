---
name: developer-info-collector
description: 开发者信息收集工具。自动扫描当前目录的所有Git项目，收集开发者配置、项目信息、分支状态等。主要用于Code Review前的信息准备，快速识别review者、被review者和项目归属。
version: 1.0
license: MIT
---

# 开发者信息收集技能

## 技能用途

自动收集开发者和项目信息，用于Code Review场景：
- **识别 review 执行者**：当前开发者的Git配置信息
- **识别被 review 的代码**：提交者信息、分支状态
- **识别项目归属**：服务名、仓库地址

**核心能力**：
- 自动扫描目录及子目录（最多3层深度）找到所有Git项目
- 提取Git用户配置（用户名、邮箱）
- 获取每个项目的远程仓库地址和项目名
- 检测当前分支和本地修改状态
- 输出结构化JSON数据

## 核心工具

脚本位置：`.claude/skills/developer-info-collector/scripts/collect_info.py`

## 使用方法

### 基本用法

```powershell
# 扫描当前目录（默认深度3层）
python collect_info.py

# 指定扫描目录
python collect_info.py --base-dir "D:\projects"

# 自定义扫描深度（1-5层）
python collect_info.py --depth 2

# 指定输出文件
python collect_info.py --output developer_info.json

# 美化输出（便于阅读）
python collect_info.py --pretty
```

### 参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--base-dir` `-d` | 扫描的基础目录 | 当前目录 |
| `--depth` | 扫描深度（1-5层） | 3 |
| `--output` `-o` | 输出JSON文件路径 | `developer_info_{timestamp}.json` |
| `--pretty` `-p` | 美化JSON输出 | False |
| `--verbose` `-v` | 显示详细日志 | False |

## 输出数据结构

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
      }
    }
  ],
  "summary": {
    "total_projects": 5,
    "projects_with_changes": 2
  }
}
```

## 执行步骤

1. **扫描Git项目**
   - 从指定目录开始递归扫描（最多3层）
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

4. **数据聚合与输出**
   - 构建JSON数据结构
   - 保存到文件（带时间戳）
   - 输出统计摘要到控制台

5. **异常处理**
   - 跳过无效的Git仓库（损坏或访问失败）
   - 记录警告信息但继续处理其他项目
   - 对缺失的配置使用默认值（"Unknown"）

## 最佳实践

- **目录选择**：在你的工作目录根目录运行，避免扫描系统目录
- **深度控制**：如果项目组织较深，适当增加 `--depth` 参数
- **定期收集**：Code Review前执行，确保信息最新
- **配置检查**：确保Git用户名和邮箱已正确配置
- **权限注意**：确保有权限访问所有待扫描的Git项目

## 输出规范

- **文件名格式**：`developer_info_{YYYYMMDD_HHMMSS}.json`
- **编码格式**：UTF-8（确保中文正常显示）
- **JSON格式**：默认紧凑格式，使用 `--pretty` 美化输出
- **路径格式**：统一使用正斜杠 `/`（跨平台兼容）
- **时间格式**：ISO 8601 格式 `YYYY-MM-DD HH:MM:SS`

## 常见问题

### Q: 扫描时间过长怎么办？
A: 减小 `--depth` 参数，或指定更精确的 `--base-dir`

### Q: 找不到Git项目？
A: 检查目录路径是否正确，确保深度参数足够

### Q: 用户名显示为 "Unknown"？
A: 需要先配置Git：`git config --global user.name "你的名字"`

### Q: 远程仓库地址为空？
A: 该项目可能是本地仓库，未配置远程地址

## 版本历史

- **v1.0** (2026-03-06) - 初始版本
  - 支持自动扫描Git项目
  - 收集开发者和项目基本信息
  - 输出JSON格式数据
