# 代码审查报告 — spec-kit 与 speckit-gitai-integration-plan 需求符合性审查

**审查日期**: 2026-04-23
**审查对象**: `spec-kit-standalone/spec-kit` 代码库
**对比文档**: `git-ai/docs/speckit-gitai-integration-plan(3)(1).md`
**审查人**: gaoang
**审查范围**: 需求 1（自动安装 git-ai）+ 需求 2（AI 统计上传）全部实施项

---

## 审查摘要

| 维度 | 状态 |
|------|------|
| 需求 1：自动安装 git-ai | ✅ 基本符合 |
| 需求 2A：主动上传命令 | ⚠️ 存在关键偏差 |
| 需求 2B：Code Review 自动上传 | ⚠️ 存在偏差 |
| 文件同步一致性 | ⚠️ 部分不同步 |

**问题总计**: 7 个
- 🔴 严重: 2 个
- 🟡 一般: 3 个
- 🔵 优化: 2 个

---

## 一、需求 1 审查：Speckit 自动安装 git-ai

### 1.1 post-init.ps1 脚本 ✅

**文件**: `scripts/powershell/post-init.ps1` (184 行)

设计文档要求的核心行为全部实现：
- ✅ 两步检测（PATH + 默认安装路径 `~/.git-ai/bin/git-ai.exe`）
- ✅ 未安装时从官方 URL 下载安装器（默认 `https://usegitai.com/install.ps1`）
- ✅ 支持 `GIT_AI_INSTALLER_URL` 环境变量覆盖安装地址
- ✅ 安装后执行 `git-ai install-hooks` 刷新配置
- ✅ 失败只 Warning，不阻塞 `specify init`
- ✅ 支持 `-Force` 和 `-Skip` 参数

### 1.2 post-init.sh 脚本 ✅

**文件**: `scripts/bash/post-init.sh` (158 行)

bash 版本忠实翻译了 PowerShell 版本的逻辑：
- ✅ `curl`/`wget` 双下载方案
- ✅ 默认 URL 使用 `.sh` 后缀（非 `.ps1`）
- ✅ 可执行路径去除 `.exe` 后缀
- ✅ 支持 `--force`/`-f` 和 `--skip`/`-s` 参数

### 1.3 `specify_cli/__init__.py` 修改 ✅

设计文档要求在 `init()` 函数中增加 post-init 执行点，实际实现完全符合：

- ✅ 新增 `_get_post_init_command()` 辅助函数（行 1565-1579）
- ✅ 新增 `run_post_init_script()` 执行函数（行 1582-1626）
- ✅ 执行顺序正确：`save_init_options` → preset install → cleanup → **post-init** → finalize
- ✅ Tracker 包含 `"post-init"` 步骤
- ✅ 失败处理：所有异常路径只记录 Warning，不抛出异常
- ✅ 超时设置 120 秒

### 1.4 check-prerequisites.ps1 兜底 ✅

**文件**: `scripts/powershell/check-prerequisites.ps1` (行 59-72)

- ✅ 软检测 `git-ai` 命令
- ✅ 未安装时显示 Warning 框和修复命令
- ✅ 不阻塞脚本执行

### 1.5 文件副本同步 ✅

| 源文件 | 副本位置 | 状态 |
|--------|---------|------|
| `scripts/powershell/post-init.ps1` | `.specify/scripts/powershell/post-init.ps1` | ✅ 一致 |
| `scripts/powershell/post-init.ps1` | `test-verify/.specify/scripts/powershell/post-init.ps1` | ✅ 一致 |
| `scripts/powershell/upload-ai-stats.ps1` | `.specify/scripts/powershell/upload-ai-stats.ps1` | ✅ 一致 |

---

## 二、需求 2A 审查：upload-ai-stats.ps1 主动上传

### 2.1 整体实现 ✅

**文件**: `scripts/powershell/upload-ai-stats.ps1` (1581 行)

核心功能均已实现：
- ✅ 支持 4 种使用场景（当前分支/日期范围/指定 commit/DryRun）
- ✅ 批量上传（一次请求发送多个 commit）
- ✅ snake_case → camelCase 转换
- ✅ 默认 remote URL 硬编码
- ✅ 支持 `GIT_AI_REPORT_REMOTE_URL` / `ENDPOINT + PATH` / `API_KEY` / `USER_ID` 环境变量
- ✅ X-USER-ID 多源探测链（环境变量 → VS Code MCP → IDEA MCP）
- ✅ JSONC 解析器（兼容 VS Code 带注释 JSON）
- ✅ 10 秒超时
- ✅ `-LogHttpPayload` 调试选项

### 2.2 🔴 严重问题：`Get-CommitAiFileStats` 使用了错误的数据源

**文件**: `scripts/powershell/upload-ai-stats.ps1`, 行 1039

**问题描述**:

设计文档变更日志（2026-04-19）明确指出：逐文件统计应改用 **commit-local 语义**，直接解析 `git notes --ref=ai show <sha>` + `git diff-tree --numstat`。但当前实现仍然使用旧方案：

```powershell
# ❌ 当前代码（行 1039）
$diffCommandResult = Invoke-ProcessCapture -FilePath 'git-ai' -Arguments @('diff', $CommitSha, '--json', '--include-stats')
```

**应改为**:

```powershell
# ✅ 设计文档要求的 commit-local 方案
# Step 1: git diff-tree --no-commit-id --numstat -r <sha>
# Step 2: git notes --ref=ai show <sha>
# Step 3: 解析 attestation 段（非缩进行=文件路径，缩进行=归因条目）
```

**影响说明**:

`git-ai diff` 是 provenance-traced 的，会跨 commit 追溯行的来源。例如一个纯人工 commit（21行人工，0行 AI）在逐文件统计中可能被错误标记为有 AI 行（因为某些行在更早的 commit 中由 AI 生成过）。这不符合 "这个 commit 本身有多少 AI 参与" 的业务语义。

设计文档中已给出完整的替代实现代码（见文档「需求 2 - 3.3」中的 `Get-CommitAiFileStats` 函数），可直接参考替换。

---

### 2.3 🟡 一般问题：authorshipSchemaVersion 版本号不一致

**文件**: `scripts/powershell/upload-ai-stats.ps1`, 行 1403

| 项目 | 设计文档 | 实际代码 |
|------|---------|---------|
| `authorshipSchemaVersion` | `"authorship/3.0.0"` | `"authorship/3.1.0"` |

**问题描述**: 实现中使用的版本号 `3.1.0` 高于设计文档指定的 `3.0.0`。如果这是有意升级，应同步更新设计文档；如果不是，应回退到 `3.0.0` 以保证与服务端兼容。

**建议**: 确认服务端是否已支持 `3.1.0`。若已支持，更新设计文档；否则回退版本号。

---

## 三、需求 2B 审查：Code Review 自动上传

### 3.1 🟡 一般问题：步骤编号与设计文档不一致

**文件**: `templates/commands/code-review.md`

| 功能 | 设计文档编号 | 实际编号 |
|------|------------|---------|
| 收集 AI 归因数据 | 步骤 8.3 | 步骤 8.5 |
| 上传 AI 统计 | 步骤 8.4 | 步骤 8.6 |

**原因**: 实际代码中，步骤 8.3 被用于"执行示例"（Execution example），步骤 8.4 被用于"同步完成确认"。AI 统计相关步骤被顺延到 8.5/8.6。

**影响**: 功能逻辑正确，但编号不一致可能导致团队沟通时产生混淆，尤其是在引用 agent prompt 步骤时。

**建议**: 将步骤 8.3（执行示例）和 8.4（同步确认）合并或重编号，使 AI 统计步骤回到 8.3/8.4 的位置，与设计文档保持一致。

---

### 3.2 🔴 严重问题：`.specify/templates/code-review/template.md` 副本严重过期

**文件**: `.specify/templates/code-review/template.md`

**问题描述**:

该文件是 `templates/code-review/template.md` 的 `.specify` 目录副本，但存在两个严重问题：

1. **缺失 AI 代码使用统计章节**: 源文件 `templates/code-review/template.md` 在行 182-195 包含完整的「AI 代码使用统计」表格模板，但 `.specify` 副本中完全没有该章节。

2. **文件尾部内容损坏**: 行 149 开始出现明显的文本错乱（如 `填写）填写）`、`{如有，填写需求文档来源}hrowable`），两个模板段落发生了重叠拼接。

**影响**: 当用户通过 `.specify` 目录中的模板生成 Code Review 报告时，报告将缺失 AI 统计表格，且可能包含乱码内容。

**修复方案**: 从 `templates/code-review/template.md` 完整复制到 `.specify/templates/code-review/template.md`，确保二者一致。

---

### 3.3 🟡 一般问题：AI 统计表格列定义不一致

**对比位置**:
- `templates/commands/code-review.md` (行 685-700) — Agent 指令中的表格定义
- `templates/code-review/template.md` (行 186-189) — 报告模板中的表格定义

| 列名 | code-review.md (Agent 指令) | template.md (报告模板) |
|------|---------------------------|----------------------|
| AI 归因列 | `AI归因新增` (单列合并) | `纯 AI 接受 (ai_accepted)` + `混编 (mixed_additions)` (双列拆分) |

**问题描述**: Agent 在生成报告时参考 `code-review.md` 的表格格式，但最终报告模板期望的是双列拆分格式。这可能导致 Agent 生成的报告与模板预期不匹配。

**建议**: 统一两处表格列定义，建议采用设计文档中的单列合并方案（`AI归因新增 = aiAdditions`），因为这与 `git-ai stats` 的输出字段直接对应，更简洁。

---

### 3.4 `.github/agents/speckit.code-review.agent.md` 文件内容异常

**说明**: 该文件实际内容为一份已生成的代码审查报告（审查对象为 `op-api` 项目，开发者张艺锋，日期 2026-04-13），而非 Agent prompt 定义文件。这属于仓库文件管理问题，不直接影响功能（实际 Agent prompt 位于 `templates/commands/code-review.md`）。

---

## 四、其他发现

### 4.1 🔵 优化建议：缺少 `--skip-post-init` CLI 级别参数

`post-init.ps1` 脚本本身支持 `-Skip` 参数，但 `specify init` CLI 没有暴露对应的 `--skip-post-init` 选项。用户无法在 CLI 层面跳过 post-init 执行（例如在 CI 环境中不需要安装 git-ai 时）。

**建议**: 在 `init()` 函数中增加 `--skip-post-init` 可选参数，传递给 `run_post_init_script()`。

---

### 4.2 🔵 优化建议：缺少正式测试套件

`pyproject.toml` 声明了 `testpaths = ["tests"]`，但实际 `tests/` 目录不存在。整个代码库没有 Python 单元测试或集成测试。

**建议**: 至少为以下核心模块补充测试：
- `_get_post_init_command()` 路径解析逻辑
- `run_post_init_script()` 的各失败分支
- `agents.py` 的 `CommandRegistrar` 注册逻辑

---

## 五、需求符合性总结

| 设计文档要求 | 实现状态 | 关键偏差 |
|-------------|---------|---------|
| Phase 1.1：创建 post-init 模板源脚本 | ✅ 完成 | — |
| Phase 1.2：同步仓库内副本 | ✅ 完成 | — |
| Phase 1.3：修改 `init()` 流程 | ✅ 完成 | — |
| Phase 1.4：check-prerequisites 兜底 | ✅ 完成 | — |
| Phase 2.1：创建 upload-ai-stats.ps1 | ⚠️ 基本完成 | `Get-CommitAiFileStats` 数据源不符 |
| Phase 2.2：验证 `git-ai stats` 输出 | ✅ 完成 | — |
| Phase 2.3：配置 remote URL | ✅ 完成 | 默认 URL 已内置 |
| Phase 3.1：Code Review Agent 追加步骤 | ⚠️ 基本完成 | 步骤编号偏移 (8.5/8.6 vs 8.3/8.4) |
| Phase 3.2：报告模板追加 AI 统计 | ⚠️ 部分完成 | `.specify` 副本未同步，列定义不一致 |
| Phase 3.3：降级场景 | ✅ 完成 | git-ai 缺失时正确跳过 |

---

**审查结论**: 需求 1（自动安装 git-ai）实现质量高，完全符合设计文档。需求 2 整体框架完整，但存在 2 个严重问题需要优先修复：(1) `Get-CommitAiFileStats` 数据源需从 `git-ai diff` 切换到 authorship note 直接解析；(2) `.specify` 目录下的 Code Review 报告模板需要同步更新。
