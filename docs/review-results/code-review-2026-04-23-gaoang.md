# 代码审查报告：gaoang (2026-04-16 ~ 2026-04-19)

## 用户输入的原始提示词
`d:\git-ai-main\git-ai\docs\speckit-gitai-integration-plan(3)(1).md'是需求和设计文档，根据这份文档review spec-kit-standalone文件夹下的spec-kit，review结果形成.md文档并上传到远程服务器`

## 用户评审所选择的模型名称
GPT-5.4 (`gpt-5.4`)

## ✅ 优点
- `specify init` 已在 CLI 主流程末尾接入 `run_post_init_script(...)`，并保持失败仅告警、不阻塞初始化，符合设计文档对体验的要求。
- `post-init` 的 PowerShell 与 bash 路径都补齐了“检测已有安装 -> 调官方安装器 -> 刷新 install-hooks”的主流程，脚本源、模板副本、验证副本之间也做了同步。
- `upload-ai-stats.ps1` 已具备批量提交、远端 URL 覆盖、`X-USER-ID` 解析和批量响应归一化能力，整体骨架与需求文档规划一致。

## 📋 提交概览
| 项目 | 内容 |
|------|------|
| 审查日期 | 2026-04-23 |
| 提交数量 | 5 个（其中 `1d155f5` 为 baseline snapshot，仅作为上下文，不纳入功能问题判断） |
| 涉及仓库 | spec-kit |
| 修改统计 | +6219/-525 行（按功能相关 4 个提交统计） |
| 修改文件 | 24 个文件（去重后，功能相关提交） |

## 📄 需求文档摘要

> 本次代码审查基于 `D:\git-ai-main\git-ai\docs\speckit-gitai-integration-plan(3)(1).md` 进行符合性检查。

### 需求来源
- **文档名称/链接**: `git-ai × Speckit 集成方案（详细实施指南）`
- **需求版本**: 文档内最新版本（含 2026-04-16 方案细化）
- **提取日期**: 2026-04-23

### 核心需求
| 类别 | 需求内容 |
|------|---------|
| 📋 **功能需求** | `specify init` 后自动执行 post-init，完成 git-ai 安装与 `install-hooks` 刷新；提供 `upload-ai-stats` 手动上传；Code Review 时自动补充并上传 AI 统计。 |
| 🔗 **接口定义** | 上传请求需携带 `repoUrl`、`projectName`、`branch`、`source`、`reviewDocumentId`、`commits[]`；服务端按 commit 维度返回结果。 |
| ⚡ **性能要求** | 批量上传多个 commit，避免逐 commit 高频请求。 |
| 🔒 **安全要求** | 远端 URL/API Key/X-USER-ID 通过环境变量或本地 MCP 配置解析，不把凭据硬编码进脚本。 |
| 📊 **数据要求** | commit 级统计来自 `git-ai stats --json`；文件级统计需按文档定义走 commit-local 口径，解析 authorship note attestation 与 `git diff-tree --numstat`。 |
| 🔄 **业务流程** | CLI 初始化 -> post-init；Code Review 生成报告后 -> 收集 git-ai 数据 -> 调上传脚本 -> 报告末尾展示 AI 统计。 |

### 需求符合性总结
- ✅ **已满足**: post-init 接入、批量上传主流程、远端配置覆盖、报告模板落点等主体流程已实现
- ⚠️ **部分满足**: AI 统计的文件级口径、脚本变体与命令模板的一致性仍存在缺口
- ❌ **未满足**: `stats.files[]` 的 commit-local 统计要求当前未正确落地
- 📊 **符合率**: 70%

## 🔗 调用链摘要

### 1. 初始化接入链路
```text
specify init
  -> run_post_init_script(project_path, selected_script)
  -> .specify/scripts/powershell/post-init.ps1 | .specify/scripts/bash/post-init.sh
  -> Get-GitAiCommand / get_git_ai_command
  -> Invoke-GitAiInstaller / invoke_git_ai_installer
  -> git-ai install-hooks
```

### 2. 手动上传链路
```text
upload-ai-stats.ps1
  -> Get-TargetCommits()
  -> Get-CommitAiStats()
     -> git notes --ref=ai list
     -> git-ai stats <sha> --json
     -> Get-CommitAiFileStats()
  -> New-CommitUploadItem()
  -> Get-UploadRemoteConfig()
  -> Send-AiStatsBatchToRemote()
```

### 3. Code Review 触发链路
```text
templates/commands/code-review.md
  -> 步骤 8.5 收集 git-ai 数据
  -> 步骤 8.6 调用 .specify/scripts/powershell/upload-ai-stats.ps1
  -> templates/code-review/template.md 中追加 AI 统计章节
```

## ⚠️ 问题清单

### 🔴 P0-需求偏离 - 严重

**问题分类:** 统计口径错误

**问题描述:** `upload-ai-stats.ps1` 的文件级 AI 归因没有按照设计文档要求解析 commit 自身的 authorship note attestation，而是改成了调用 `git-ai diff <sha> --json --include-stats`。这会把文件级统计切到 provenance-traced 语义；更严重的是，当前本地脚本在真实 commit 上已经出现 `Failed to parse file details`，导致 `stats.files[]` 直接为空。

**风险级别:** 🔴P0-需求偏离-严重

**提交hash:** `b70987ea145293450b86ea0f9c5b36629fbd2647`

**问题代码位置:** `spec-kit/scripts/powershell/upload-ai-stats.ps1:1036-1151`

**需求要求:** 设计文档要求文件级统计必须采用 commit-local 口径：`git notes --ref=ai show <sha>` 解析 attestation 段 + `git diff-tree --numstat` 汇总文件增删行，避免 `git-ai diff` 的跨 commit provenance 追溯。

**需求偏离说明:** 当前实现与文档注释自相矛盾：函数注释仍声明“直接解析 authorship note attestation + git diff-tree”，但实际代码执行的是 `git-ai diff`。本地仓库中的 `temp_output.json`、`stats.json` 已经出现实际失败样例：`hasAuthorshipNote=true`，但文件级统计解析失败，最终 `files` 为空、AI 新增全落入 `unknownAdditions`。

**影响说明:**  
- Code Review 报告无法基于 `stats.files[]` 做逐文件 drill-down  
- 上传到远端的文件级归因不可信，影响团队统计和审查判断  
- 在存在 note 的 commit 上仍会退化成“全未知”，直接削弱需求 2 的核心价值

**修复方案:**
```powershell
# ❌ 当前实现
function Get-CommitAiFileStats {
    param([string]$CommitSha)

    $diffCommandResult = Invoke-ProcessCapture -FilePath 'git-ai' -Arguments @('diff', $CommitSha, '--json', '--include-stats')
    $diffJson = $diffCommandResult.StdOut
    ...
}

# ✅ 符合需求的实现
function Get-CommitAiFileStats {
    param([string]$CommitSha)

    $repoRoot = Get-RepoRoot
    $numstatResult = Invoke-ProcessCapture -FilePath 'git' -Arguments @(
        '-C', $repoRoot, 'diff-tree', '--no-commit-id', '--numstat', '-r', $CommitSha
    )
    $noteResult = Invoke-ProcessCapture -FilePath 'git' -Arguments @(
        '-C', $repoRoot, 'notes', '--ref=ai', 'show', $CommitSha
    )

    # 解析 attestation 段：
    # - 非缩进行 = 文件路径
    # - h_* = 人工归因
    # - 其他 prompt hash = AI 归因
    # 再与 numstat 聚合为 commit-local 的 files[] 结果
}
```

**新引入:** ✅是

---

### 🟠 P1-警告（需重点关注）

**问题分类:** 脚本变体不一致

**问题描述:** 当前发布打包脚本在 `--script sh` 变体下只复制 `scripts/bash` 到 `.specify/scripts/`，但仓库并没有提供 `scripts/bash/upload-ai-stats.sh`。与此同时，`templates/commands/code-review.md` 又把上传步骤写死为 `.specify/scripts/powershell/upload-ai-stats.ps1`。结果是：bash 项目虽然拥有 `post-init.sh`，却没有可执行的上传脚本，Code Review 提示词也会指向一个根本不存在的文件。

**风险级别:** 🟠P1-警告

**提交hash:** `6a45d5f4099da83ef4b0cc85e1513d564d9eded0`

**问题代码位置:** `spec-kit/.github/workflows/scripts/create-release-packages.ps1:323-341`；`spec-kit/.github/workflows/scripts/create-release-packages.sh:234-246`；`spec-kit/templates/commands/code-review.md:673`

**需求要求:** 需求文档要求脚本、模板、生成后的 `.specify` 内容保持对应关系；CLI 已支持按 `selected_script` 生成 PowerShell / bash 两种变体，相关命令模板也应与打包产物一致。

**当前实现:**  
- `sh` 变体只会打包 `scripts/bash/*`  
- 仓库不存在 `scripts/bash/upload-ai-stats.sh`  
- `code-review` 模板无条件引用 `.specify/scripts/powershell/upload-ai-stats.ps1`

**影响说明:**  
- `specify init --script sh` 生成的项目无法完成需求 2 的“主动上传”路径  
- Code Review 自动上传路径在 sh 项目中同样失效  
- 生成物与命令模板不一致，用户会在运行期踩到“文件不存在”

**建议:**
```text
方案 A（推荐）：
1. 新增 scripts/bash/upload-ai-stats.sh
2. 让 sh 变体把该脚本复制到 .specify/scripts/bash/
3. 在 code-review 模板里按 script variant 选择对应上传命令

方案 B（次优）：
1. 明确声明 upload-ai-stats 仅支持 ps 变体
2. 在 sh 变体的 code-review 模板中删除自动上传步骤
3. 在 README / upgrade 文档中标注限制，避免生成物与提示词不一致
```

**新引入:** ✅是

---

## 结论

当前实现已经把 git-ai 生命周期接入到了 Spec Kit 的初始化和 Code Review 流程里，主干思路是对的；但文件级 AI 统计这条关键数据链路仍然没有按设计文档落地，而且 `--script sh` 变体下的上传能力不完整。建议先修复 `stats.files[]` 的 commit-local 口径，再补齐脚本变体一致性，否则远端统计与 Code Review 自动化都还不能算稳定可用。
