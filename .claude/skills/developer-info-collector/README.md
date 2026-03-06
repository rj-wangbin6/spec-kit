# 开发者信息收集工具

自动扫描当前目录的所有Git项目，收集开发者配置、项目信息、分支状态等，为Code Review准备信息。

## 快速开始

```powershell
# 扫描当前目录（默认3层深度）
python scripts/collect_info.py

# 指定目录和深度
python scripts/collect_info.py --base-dir "D:\projects" --depth 2

# 美化输出
python scripts/collect_info.py --pretty

# 显示详细日志
python scripts/collect_info.py -v
```

## 主要功能

- ✅ 自动扫描目录及子目录找到所有Git项目（最多5层深度）
- ✅ 提取Git用户配置（用户名、邮箱、Git版本）
- ✅ 获取每个项目的远程仓库地址和项目名
- ✅ 检测当前分支名称
- ✅ 检查本地是否有未提交的修改
- ✅ 获取最近一次提交信息（作者、时间、提交信息）
- ✅ 输出结构化JSON数据

## 使用场景

**Code Review 信息准备**：
- 快速识别谁在做 review（当前开发者）
- 识别 review 哪个项目（服务名、仓库地址）
- 了解项目当前状态（分支、修改状态）
- 查看最近提交者信息

## 输出示例

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

## 参数说明

| 参数 | 简写 | 说明 | 默认值 |
|------|------|------|--------|
| `--base-dir` | `-d` | 扫描的基础目录 | 当前目录 |
| `--depth` | - | 扫描深度（1-5层） | 3 |
| `--output` | `-o` | 输出JSON文件路径 | `developer_info_{timestamp}.json` |
| `--pretty` | `-p` | 美化JSON输出 | False |
| `--verbose` | `-v` | 显示详细日志 | False |

## 注意事项

- 需要Git命令行工具已安装并配置在PATH中
- 确保有权限访问待扫描的目录
- 如果未配置Git用户名/邮箱，会显示 "Unknown"
- 扫描深度过大可能导致扫描时间较长，建议根据实际目录结构调整

## 许可证

MIT
