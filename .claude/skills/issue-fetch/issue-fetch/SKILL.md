---
name: issue-fetch
description: "Use when: 需要查询gerrit代码检查结果、根据 changeNumber 获取 Coverity 静态分析问题、拉取 Gerrit 变更对应的问题详情、分析 issue-fetch 技能输出。支持通过 changeNumber 查询代码检查数据。支持自动从本地 Gerrit 仓库最后一次提交中提取 Change-Id 并解析出 changeNumber。"
license: MIT
---

# Issue Fetch 技能

## 技能用途

通过 changeNumber 查询 Gerrit 提交对应的 Coverity 静态分析问题，支持自动从本地仓库提取 changeNumber。

- `data.total = 0`：无问题，代码质量良好
- `data.total > 0`：存在需修复的问题

## 核心工具

`.ai4code/skills/issue-fetch/scripts/query_ci_review.exe`


## 接口说明

```
GET http://rgci.ruijie.com.cn/rgci/report/outside/api/gerrity/gerrityCoverity/getPageData?changeNumber=<number>
```

**请求参数**：`changeNumber`（string，必需）

### 响应字段

| 字段 | 说明 |
|------|------|
| `state` | 执行状态（`"SUCCESS"` 为成功） |
| `data.total` | 问题总数 |
| `data.list` | 问题列表 |

**list 问题对象字段**：

| 字段 | 说明 |
|------|------|
| `gerritProject` | 仓库名 |
| `gerritBranch` | 分支名 |
| `file` | 文件路径 |
| `line` | 行号 |
| `errorFunction` | 函数名 |
| `changeOwner` | 提交人 |
| `ruleChecker` | 检查器类型 |
| `detailIssue` | 推理步骤数组（最后一步为具体检出问题） |

**常见检查器**：`INTEGER_OVERFLOW` / `BUFFER_OVERFLOW` / `NULL_DEREFERENCE` / `RESOURCE_LEAK` / `USE_AFTER_FREE` / `DEADCODE` / `UNINIT`

## 使用指南

### 步骤 0：自动获取 changeNumber（用户未提供时必须先执行）

**① 检查是否为 Git 仓库**
```bash
git rev-parse --is-inside-work-tree
```
失败 → 提示手动输入，终止

**② 提取 Change-Id**
```bash
git log -1 --format="%B"
```
在输出中找 `Change-Id: I...` 行；未找到 → 提示手动输入（非 Gerrit 仓库），终止

**③ 获取用户名**（优先级：`git config gerrit.username` > `user.email` 前缀 > `whoami`）

**④ SSH 查询 changeNumber**
```bash
ssh -p 29418 <username>@gerrit.ruijie.work gerrit query --format=JSON change:<change-id>
```
提取非 `"type":"stats"` 行的 `"number"` 字段值；`rowCount=0` 或连接失败 → 提示手动输入，终止

### 步骤 1–6：查询流程

> ⚠️ 示例中的 changeNumber（如 `778441`）仅为说明，**禁止**将其作为默认值或猜测值。

1. **获取 changeNumber**：用户已提供直接用；否则执行步骤 0
2. **验证参数**：changeNumber 必须为纯数字
3. **执行查询**：`query_ci_review --json <changeNumber>`
   - 退出码非 0 或含错误信息 → **立即停止，严禁重试（包括严禁去掉 `--json` 参数后重试）**，输出失败模板
4. **解析响应**：解析 JSON
5. **判断结果**：`total=0` → 无问题 ✅；`total>0` → 有问题 ⚠️
6. **格式化输出**：按输出模板展示

### 工具使用

```powershell
cd .ai4code/skills/issue-fetch/scripts
.\query_ci_review.exe --json 778441   # 查询（推荐 JSON 模式）
.\query_ci_review.exe --help          # 查看帮助
```

## 工作流程

> ⚠️ **【严禁违反】** 文档中所有 changeNumber 示例（如 `778441`、`777918` 等）均为说明示例，**绝对不允许**将其作为默认值或猜测值使用。未明确获取到 changeNumber 之前，必须先执行自动获取流程或提示用户手动输入，不得跳过。

当用户请求查询gerrit代码检查结果时：

1. **获取 changeNumber**：
   - 若用户已明确提供 changeNumber → 直接使用，跳至步骤 2
   - 若用户未提供（包括用户说"帮我查询"、"查一下结果"等模糊请求）→ **必须**执行**自动获取流程**（见"使用指南 → 步骤 0"），禁止使用任何示例值或凭空猜测：
     - 检测当前目录是否为 Git 仓库
     - 从最后一次 commit message 提取 `Change-Id`
     - 从 git config 获取 Gerrit 用户名
     - 通过 `ssh -p 29418 <username>@gerrit.ruijie.work gerrit query` 查询 changeNumber
     - 自动获取失败时，提示用户手动提供 changeNumber，**立即停止，不得继续执行查询**
2. **验证参数**：检查 changeNumber 是否格式正确（纯数字）
3. **执行查询**：调用 `query_ci_review --json <changeNumber>` 获取纯 JSON 输出
   - 若命令退出码非 0 或输出包含错误信息（如超时、连接失败等）→ **立即停止，严禁重试（包括严禁去掉 `--json` 参数后再次执行同一命令）**，直接按"输出模板 → 请求失败"格式输出错误提示，结束本次技能执行
4. **解析响应**：解析 JSON 响应数据
5. **判断结果**：
   - 如果 `data.total = 0`：无问题，代码质量良好 ✅
   - 如果 `data.total > 0`：存在问题，需要分析和修复 ⚠️
6. **格式化输出**：按照输出模板展示结果（见下方）

## 输出模板

### 当请求失败时（退出码非 0 / 超时 / 连接错误）

> **立即终止，不重试**，直接输出以下信息：

```
❌ 查询失败：changeNumber <编号>

错误信息：<工具输出的原始错误>

请检查是否在内网办公环境，还有其他问题请联系技能发行人。
```

### 当 total = 0（无问题）时

```
✅ 查询完成：changeNumber <编号>

状态：SUCCESS
问题总数：0
结论：代码质量良好，无需修复
```

### 当 total > 0（有问题）时

```
⚠️ 查询完成：changeNumber <编号>

状态：<state值>
问题总数：<total值>

【问题 1】
- 检查器类型：<ruleChecker>（如 INTEGER_OVERFLOW）
- 仓库：<gerritProject>
- 分支：<gerritBranch>
- 文件：<file>
- 行号：<line>
- 函数：<errorFunction>
- 提交人：<changeOwner>
- 问题推理：<detailIssue 数组，展示推理步骤>
  * 步骤1：<description> (行<line>)
  * 步骤2：<description> (行<line>)
  * ...
  * 最后一步为具体检出问题

【问题 2】
...（如果有多个问题，依次列出）

结论：发现 <total> 个问题需要修复
```

### 输出示例

#### 示例1：无问题
```
✅ 查询完成：changeNumber 777918

状态：SUCCESS
问题总数：0
结论：代码质量良好，无需修复
```

#### 示例2：有问题
```
⚠️ 查询完成：changeNumber 778441

状态：SUCCESS
问题总数：2

【问题 1】
- 检查器类型：INTEGER_OVERFLOW（整数溢出）
- 仓库：wlan_sdk_athlea
- 分支：master
- 文件：wlan_sdk_athlea/ruijie/service/dp/ais/rjwlan_ais.c
- 行号：732
- 函数：rjwlan_ais_get_scan
- 提交人：leiqibin
- 问题推理：
  * 步骤1：条件 'count > 0' 为真 (行728)
  * 步骤2：表达式 'count * size' 发生整数溢出 (行732)

【问题 2】
- 检查器类型：NULL_DEREFERENCE（空指针解引用）
- 仓库：wlan_sdk_athlea
- 分支：master
- 文件：wlan_sdk_athlea/ruijie/service/dp/utils/rjwlan_utils.c
- 行号：89
- 函数：validate_input
- 提交人：leiqibin
- 问题推理：
  * 步骤1：分配返回NULL (行85)
  * 步骤2：解引用NULL指针 'ptr' (行89)

结论：发现 2 个问题需要修复
建议：优先修复 INTEGER_OVERFLOW（高危）问题
```

## 字段提取规则

从JSON响应中提取以下字段进行展示：

**顶层字段**：
- `state` - 任务执行状态（必需）
- `data.total` - 问题总数（必需）

**问题列表字段**（从 `data.list` 数组中）：
- `ruleChecker` - Coverity检查器类型（必需）
- `gerritProject` - 业务仓库名（必需）
- `gerritBranch` - Git分支（必需）
- `file` - 代码文件路径（必需）
- `line` - 问题所在行号（必需）
- `errorFunction` - 问题函数名（必需）
- `changeOwner` - 提交人（必需）
- `detailIssue` - 问题推理步骤数组（必需，展示完整推理链）

**重要提示**：
- 必须展示 `detailIssue` 的完整推理步骤，最后一步是具体问题
- 如果有多个问题，需要逐个列出所有问题
- 不要只输出原始JSON，要按照模板格式化

### 自动化分析修复流程（在Copilot中）

当检测到问题时（`total > 0`），可以进一步处理：

1. **定位问题**：
   - 文件路径：`file`
   - 代码行号：`line`
   - 问题函数：`errorFunction`

2. **分析问题**：
   - 检查器类型：`ruleChecker`（如 INTEGER_OVERFLOW）
   - 推理详情：`detailIssue`（查看最后一步了解具体问题）

3. **修复建议**：
   - 根据 `ruleChecker` 类型提供针对性修复方案
   - 参考 `detailIssue` 的推理步骤理解问题根因
   - 生成修复代码或修改建议

4. **验证修复**：
   - 重新提交代码
   - 再次查询确认 `total = 0`

## 环境要求

### 直接使用已编译的 exe

**Windows 环境无需额外安装运行依赖。** 已提供的 `query_ci_review.exe` 可以直接运行。

## 故障排查

### 请求失败统一处理规则

**无论何种原因导致 `query_ci_review` 执行失败（超时、网络不通、HTTP 错误等），一律：**
1. **不重试，不用任何其他参数组合再次执行**（包括严禁去掉 `--json` 参数后重试）
2. 输出统一错误提示（错误信息来源于 `--json` 命令本身的输出，无需额外执行其他命令）：
   ```
   ❌ 查询失败：changeNumber <编号>

   错误信息：<工具输出的原始错误>

   请检查是否在内网办公环境，还有其他问题请联系技能发行人。
   ```
3. 终止本次技能执行

### 常见问题

1. **连接超时 / 网络不可达**
   - 原因：不在内网办公环境，或 CI 服务器不可达
   - 处理：按上方统一规则输出错误提示，**不重试**

2. **changeNumber 不存在或无扫描数据**
   ```
   {"state": "SUCCESS", "data": {"total": 0, "list": []}}
   ```
   - 原因：指定的 changeNumber 不存在、尚未产生扫描结果，或没有评审数据
   - 解决方案：确认 changeNumber 正确，检查该变更是否有 Coverity 扫描

### 调试技巧

```bash
# 使用curl命令直接测试接口（需内网环境）
curl "http://rgci.ruijie.com.cn/rgci/report/outside/api/gerrity/gerrityCoverity/getPageData?changeNumber=777918"
```

## 注意事项

1. **网络访问**：确保可以访问 `rgci.ruijie.com.cn` 域名
2. **参数验证**：changeNumber应该是有效的数字
3. **错误处理**：程序会捕获网络错误和JSON解析错误
4. **内存管理**：使用完curl句柄后会自动清理
5. **编码问题**：响应数据使用UTF-8编码，Windows控制台可能需要设置编码

## 扩展功能建议

可以在脚本中添加以下功能：
- 支持批量查询多个changeNumber
- 添加JSON美化输出选项
- 支持导出结果到CSV文件
- 添加缓存机制减少重复查询
- 支持配置文件管理API地址和参数
