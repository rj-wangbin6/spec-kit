# Git技能优化说明

## 优化内容

### 🎯 核心改进：智能递归搜索

优化了 `git-commit-log` 和 `git-branch-sync` 两个技能的仓库搜索逻辑，实现更智能的多层目录搜索。

### 📋 改进前的问题

1. **固定深度限制**：默认只搜索2级子目录，可能遗漏深层项目
2. **搜索策略不够智能**：没有优先检查当前目录
3. **深度配置不灵活**：无法支持无限深度搜索

### ✅ 改进后的特性

#### 1. 智能搜索策略

```
当前目录 → 是Git项目? 
    ├─ 是 → 加入列表 ✓（不深入该项目内部）
    └─ 否 → 递归进入所有子目录
        ├─ 子目录1 → 是Git项目? 
        │   ├─ 是 → 加入列表 ✓（不深入该项目内部，但继续检查其他子目录）
        │   └─ 否 → 继续递归...
        ├─ 子目录2 → 是Git项目?
        │   └─ 是 → 加入列表 ✓
        └─ 子目录N → ...

结果：找到所有Git仓库（不是只找一个）
```

**实际示例**：
```
workspace/
  ├── frontend/.git    ← 找到 ✓ 加入列表
  ├── backend/.git     ← 找到 ✓ 加入列表
  ├── mobile/.git      ← 找到 ✓ 加入列表
  └── tools/
      ├── cli/.git     ← 找到 ✓ 加入列表
      └── scripts/.git ← 找到 ✓ 加入列表

执行 --scan-repos 后：找到5个仓库，全部处理 ✓
```

#### 2. 无限深度支持

- **默认值改为 `0`**：表示无限深度，搜索所有层级
- **灵活配置**：
  - `--scan-depth 0`：无限深度（推荐）
  - `--scan-depth 1`：只搜索当前目录
  - `--scan-depth 2`：搜索到二级子目录
  - `--scan-depth N`：自定义深度

#### 3. 智能过滤

自动跳过以下目录，提高搜索效率：
- 隐藏目录（`.xxx`）
- `node_modules`
- `venv` / `__pycache__`
- `dist` / `build`
- `.idea` / `.vscode`

#### 4. 找到后不深入仓库内部

一旦发现某个Git仓库，不再深入该仓库的子目录（避免扫描 `.git` 内部），但会继续搜索其他目录。

**重要**：这不是说"找到一个就停止"，而是"找到每个仓库后，不进入那个仓库内部"。所有仓库都会被找到！

### 📖 使用示例

#### git-commit-log

```powershell
# 无限深度搜索（推荐）
python git_commit_log.py --scan-repos --author zhangsan --since "2025-12-24" --diff

# 限制深度（性能优化）
python git_commit_log.py --scan-repos --scan-depth 3 --author zhangsan --since "2025-12-24"

# 指定基础目录
python git_commit_log.py --scan-repos --base-dir "D:\\projects" --author zhangsan
```

#### git-branch-sync

```powershell
# 无限深度搜索所有仓库并切换分支
python git_branch_sync.py --scan-repos --branch master --force

# 限制深度
python git_branch_sync.py --scan-repos --scan-depth 2 --branch develop
```

### 🔍 测试验证

运行测试脚本验证功能：

```powershell
cd .claude\skills
python test_git_search.py
```

### 📊 性能对比

| 场景 | 改进前 | 改进后 |
|------|--------|--------|
| 深层项目（4-5级） | ❌ 找不到 | ✅ 能找到 |
| 当前目录是Git项目 | 需要扫描子目录 | 立即识别 |
| 大量非代码目录 | 全部扫描 | 智能跳过 |
| 自定义深度 | 固定2级 | 0到N级可配 |

### 🎉 优势总结

1. **更智能**：从当前目录开始，逐层深入
2. **更灵活**：支持无限深度和自定义深度
3. **更高效**：智能过滤非代码目录
4. **更准确**：找到Git仓库后不再深入，避免误判

### 📝 注意事项

- 无限深度搜索在大型目录结构下可能较慢，建议合理设置深度限制
- 如果项目目录层级很深（>5层），建议直接在项目目录执行
- 使用 `--base-dir` 指定起始目录可提高搜索效率

---

**更新日期**：2026-02-10  
**版本**：v2.0
