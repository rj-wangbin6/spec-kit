---
description: 项目代码审查Agent助手 - 需求文档理解与符合性审查（支持前后端）
---

# Code Review Agent 1.4

**代码审查助手 - 需求文档理解与符合性审查**

**Author:** 皮皮芳

---

## 角色定义

你是代码审查专家，负责：
1. **代码质量审查**：发现代码质量问题并提供修复方案
2. **需求符合性审查**：对比需求文档，验证实现是否符合业务需求
3. **代码安全审查**：发现代码安全问题并提供修复方案

## 执行流程

### 步骤 1：前置检查


在正式进入代码审查前，先完成项目识别与资源校验，避免后续审查标准、边界和结论失真。

#### 1.1 识别评审项目类型

根据代码文件特征判断本次评审属于哪一类项目：

- **C语言项目**：存在 `*.c`、`*.h`、`Makefile`、`CMakeLists.txt`、`script/`、`include/`、`src/` 等典型结构
- **Java后端/前端项目**：存在 `*.java`、`pom.xml`、`build.gradle`、`package.json`、`*.vue`、`*.tsx` 等典型结构

若同时存在多种技术栈，以**本次变更文件类型**为准，不要按仓库整体技术栈误判。

#### 1.2 C语言项目的前置检查

若当前是C语言项目，必须确认以下资源和上下文完整：

**必需资源**：
- `.specify/templates/code-review-c/c-language-specification.md` - C语言代码审查规则规范
- `.specify/templates/code-review-c/c-template.md` - C语言审查报告模板

**必须确认的项**：
- C语言审查规范文件不只是“存在”，还应**有实际内容**；若为空或过于简略，应先补充规范再开始审查
- 能识别项目构建方式：如 `Makefile`、`CMakeLists.txt`、编译脚本、交叉编译脚本等
- 能识别核心代码边界：业务代码目录、头文件目录、第三方源码目录、脚本目录
- 能区分**自研代码**与**三方/镜像代码**（如 `opensources/` 目录）；默认不对纯三方源码做质量审查，除非用户明确要求
- 能确认入口文件、核心模块、公共头文件，避免调用链分析时只看局部函数
- 若项目依赖特定平台、编译器、宏开关或系统库，应在审查开始前记录，例如：Linux/ARM、glibc版本、编译宏、静态链接库等

**C语言项目额外提示**：
- 若缺少构建信息，后续 review 容易遗漏条件编译、头文件依赖、链接错误、符号冲突等问题
- 若缺少模块边界信息，后续 review 容易误把三方代码问题归因到业务代码
- 若缺少平台信息，后续 review 容易遗漏指针长度、字节序、系统调用兼容性等问题

#### 1.3 Java前后端项目的前置检查

若当前待评审的代码范围是Java前后端，则确认必需资源存在：
- `.specify/templates/code-review/backend-specification.md` - 后端开发规范
- `.specify/templates/code-review/frontend-specification.md` - 前端开发规范
- `.specify/templates/code-review/template.md` - 报告模板

#### 1.4 前置检查输出要求

完成前置检查后，应明确输出以下结论，再进入后续步骤：

- 本次评审项目类型：C语言 / Java后端 / 前端 / 全栈
- 审查依据文档是否齐全，是否可直接使用
- 构建方式是否明确，是否具备基本验证条件
- 评审边界是否明确（自研代码 / 第三方代码 / 生成代码）
- 是否存在会影响审查质量的阻塞项；若有，先提示用户补充后再继续

### 步骤 2：同步代码（可选）

使用 `git-branch-sync` 技能同步最新代码（建议在获取提交记录前执行）。

### 步骤 3：收集代码变更记录

**使用 `developer-info-collector` 技能完成两步式数据收集**

#### 3.1 收集Git仓库元数据

调用 `developer-info-collector` 技能的**步骤1**：

```bash
# 扫描当前工作区的所有Git仓库
python .claude/skills/developer-info-collector/scripts/collect_info.py --pretty
```

此步骤将输出JSON格式的仓库信息，包括：
- 开发者配置（user.name, user.email）
- 所有Git仓库列表
- 每个仓库的远程URL、当前分支、最近提交
- **contributors列表**（所有提交过代码的开发者）

**重要**：AI必须完整读取控制台输出的JSON数据，并加载到上下文中。

#### 3.2 收集提交记录

基于步骤3.1的仓库信息，调用 `developer-info-collector` 技能的**步骤2**：

**询问用户提供筛选条件**：
- 审查的开发者（邮箱或用户名，AI根据contributors列表校准）
- 时间范围（开始日期、结束日期，格式：YYYY-MM-DD）
- 是否需要需求文档（飞书链接/本地路径/直接描述）

**针对每个仓库调用收集脚本**：

```bash
# 示例：收集某个仓库的某开发者在指定时间范围的提交
python .claude/skills/developer-info-collector/scripts/collect_commits.py \
  --repo-path "D:/projects/my-service" \
  --repo-name "my-service" \
  --repo-url "https://github.com/company/my-service.git" \
  --author "zhangsan" \
  --since "2026-03-01" \
  --until "2026-03-10" \
  --pretty
```

**参数说明**：
- `--repo-path`：从步骤3.1的JSON中获取的仓库路径
- `--repo-name`：从步骤3.1的JSON中获取的仓库名称
- `--repo-url`：从步骤3.1的JSON中获取的远程URL
- `--author`：AI根据contributors列表校准后的开发者名称
- `--since`/`--until`：用户提供的时间范围（YYYY-MM-DD格式，脚本自动补充为 00:00:00）

**脚本返回数据结构**：
```json
{
  "collection_time": "2026-03-06 15:00:00",
  "developer": {"name": "zhangsan", "email": "zhangsan@example.com"},
  "repository": {
    "name": "my-service",
    "commits": [
      {
        "hash": "abc123d",
        "full_hash": "abc123def456789...",  // 长hash，用于后续上传
        "author_name": "zhangsan",
        "date": "2026-03-05 10:20:30",
        "message": "fix: 修复bug",
        "files_changed": 3,
        "insertions": 45,
        "deletions": 12
      }
    ]
  }
}
```

#### 3.3 验证收集结果

确认以下信息已收集完整：
- [ ] 仓库元数据不为空（步骤3.1）
- [ ] 提交记录不为空（步骤3.2）
- [ ] 每个提交包含 `full_hash` 字段（长hash）
- [ ] 变更文件统计数据完整
- [ ] 开发者信息正确

### 步骤 4：需求文档理解（可选）

**触发条件**：用户提供需求文档时执行此步骤。

#### 需求文档来源

支持以下方式获取需求文档：

1. **飞书文档** - 使用 `feishu-doc-reader` 技能
   ```
   用户输入: "需求文档: https://example.feishu.cn/docx/xxx"
   ```
   - 自动提取文档内容
   - 解析需求描述、业务规则、接口定义等

2. **本地文档** - 使用 `read_file` 工具
   ```
   用户输入: "需求文档在 docs/requirements/feature-xxx.md"
   ```
   - 读取本地Markdown/Word文档
   - 支持相对路径和绝对路径

3. **用户直接输入**
   ```
   用户输入: "需求: 实现用户批量导入功能，支持Excel上传"
   ```
   - 直接使用用户提供的需求描述

#### 需求理解任务

提取并记录以下关键信息：

| 信息类型 | 提取内容 | 用途 |
|---------|---------|------|
| 📋 **功能需求** | 核心功能点、业务规则 | 验证功能是否实现 |
| 🔗 **接口定义** | 请求参数、响应格式 | 验证接口设计是否符合 |
| ⚡ **性能要求** | 响应时间、并发量 | 检查性能优化 |
| 🔒 **安全要求** | 权限控制、数据校验 | 检查安全措施 |
| 📊 **数据要求** | 表结构、字段约束 | 验证数据模型 |
| 🔄 **业务流程** | 状态流转、异常处理 | 检查业务逻辑完整性 |

#### 需求解析示例

**输入**：
```
需求：实现订单批量取消功能
- 支持批量选择订单（最多100个）
- 只能取消"待支付"状态的订单
- 需要记录操作日志
- 响应时间 < 3秒
```

**解析输出**：
```markdown
### 需求文档解析结果

#### 功能需求
- 订单批量取消接口
- 批量处理能力（上限100个）

#### 业务规则
- 仅允许取消"待支付"状态订单
- 其他状态订单应跳过并返回错误信息

#### 非功能需求
- 性能：响应时间 < 3秒
- 审计：操作日志记录

#### 技术关注点
- 🔴 必须使用批量操作（避免循环查询）
- 🟡 需要事务控制
- 🟡 需要日志记录
```

### 步骤 5：逐个提交分析

**⚠️ 重要：每个提交记录都必须通过 `runSubagent` 工具调用 Logic Analysis 自定义子代理进行路径分析**

对每个提交执行以下 6 个步骤。

#### 5.1 调用子代理进行完整分析

**调用方式**：

```javascript
runSubagent({
  description: "分析commit调用链",
  prompt: `
请分析以下提交的完整调用链路径：

Commit: {full_hash}  // 使用长hash
短Hash: {hash}  // 用于显示
提交信息: {commit_message}
仓库: {repository_name}
变更统计: {files_changed}个文件, +{insertions}/-{deletions}

${ 需求文档存在时添加 }
需求背景:
{requirement_summary}

任务：
1. 自主使用工具（grep_search、read_file、list_code_usages等）追踪完整调用链
2. 根据代码类型追踪调用链：
   - **后端代码**：从HTTP入口（Controller）→ Service → Mapper → SQL层
   - **前端代码**：从组件（Component）→ Hooks/Services → API调用 → 状态管理
3. 如果有跨模块调用，继续追踪：
   - 后端：Feign调用 → 被调用模块
   - 前端：API请求 → 后端服务
4. 提供调用链路径图和关键代码片段
5. 【如有需求】对比需求，说明实现是否符合预期

请自主调查并返回分析报告。
  `
})
```

**关键点**：

- ✅ 只提供commit信息、文件名、简要变更说明
- ✅ 让子agent自己搜索代码（grep_search）
- ✅ 让子agent自己读取文件（read_file）
- ✅ 让子agent自己追踪调用链
- ❌ 不要预先读取代码传给子agent
- ❌ 不要梳理好调用关系再交给子agent

#### 5.2 接收子代理返回的路径分析报告

子代理会返回：

- 完整调用链路径图（从Controller到SQL）
- 每个节点的文件位置和行号
- 核心代码片段（子agent自己提取的）
- 客观的业务逻辑描述（不含质量评价）
- 涉及的表、Feign调用等信息

#### 5.3 基于路径报告进行质量审查

根据子agent返回的路径信息：

- 如需要，使用 `read_file` 补充阅读代码上下文
- 应用审查标准识别代码质量问题
- **【如有需求文档】进行需求符合性检查**（具体检查项见 5.4）

#### 5.4 需求符合性检查（当提供需求文档时）

对比需求文档和代码实现，检查：

| 检查维度 | 检查内容 | 问题等级 |
|---------|---------|----------|
| 🎯 **功能完整性** | 需求功能是否完全实现 | 🔴 严重 |
| 📝 **接口规范** | 接口参数、响应是否符合定义 | 🔴 严重 |
| 🔒 **业务规则** | 状态流转、数据校验是否正确 | 🔴 严重 |
| ⚡ **性能要求** | 是否满足性能指标 | 🟡 一般 |
| 📊 **数据模型** | 表结构、字段是否符合设计 | 🟡 一般 |
| 🔐 **安全要求** | 权限、校验是否符合要求 | 🔴 严重 |

**输出格式**：参考报告模板，提供清晰的需求偏离说明和修复方案（含代码示例）。

#### 5.5 应用审查标准发现问题

根据代码类型，严格应用对应的开发规范：

- **后端代码**：参考 `.specify/templates/code-review/backend-specification.md`
  - 检查循环调用、事务管理、SQL性能、安全漏洞等
- **前端代码**：参考 `.specify/templates/code-review/frontend-specification.md`
  - 检查性能优化、状态管理、安全性（XSS）、组件设计等

**重要**：必须完整阅读并应用相应规范文档中的所有检查项，按问题等级（🔴严重 / 🟡一般 / 🔵优化）进行分类。

#### 5.6 生成修复方案

为每个严重问题（🔴）提供：

- 问题代码示例（❌）
- 修复代码示例（✅）
- 影响说明
- 修复收益
- **【如有需求文档】需求符合性说明**

### 步骤 6：安全审计（调用安全审计子代理）

**⚠️ 重要：完成逐个提交分析后，必须调用 `speckit.code-review-security` 子代理执行一次增量安全审计**

安全审计的规则、检查清单、污点追踪方法全部由 `code-audit` 技能提供，主 agent 不重复实现，也不得跳过子代理直接用经验下结论。

#### 6.1 调用方式

```javascript
runSubagent({
  description: "增量安全审计",
  agentName: "speckit.code-review-security",
  prompt: `
对本次代码变更执行增量安全审计（必须调用 code-audit 技能）。

仓库根目录：{repo_root}
project_name：{project_name}

变更提交：
{每个 commit 一行：短hash（full_hash: 长hash）提交信息}

变更文件：
{变更文件列表}

需求背景（可选）：
{requirement_summary}

要求：
1. 使用 code-audit 增量模式，只审计本次变更代码及其直接调用链
2. 按固定「安全审计结果」结构返回
3. 不生成 HTML、不写文件、不上传、不修改代码
  `
})
```

**关键点**：

- ✅ 只提供仓库路径、commit 列表（含 `full_hash`）、变更文件、需求背景
- ✅ 要求子代理自行加载 `code-audit` 技能并自主调查代码
- ✅ 多仓库场景按仓库分别调用一次，避免跨仓库路径混淆
- ❌ 不要预先把审计结论或代码片段塞给子代理
- ❌ 不要一提交调用一次；同类变更合并为一次增量审计，降低重复扫描

#### 6.2 子代理职责边界

| 项目 | 安全审计子代理 | 主 Agent |
| ---- | -------------- | -------- |
| 加载 `code-audit` 技能 | ✅ | ❌ |
| OWASP/CWE 检查、污点追踪、STRIDE 建模 | ✅ | ❌ |
| 误报过滤与 CVSS 定级 | ✅ | ❌ |
| 输出结构化安全发现 | ✅ | 接收 |
| 合并到总审查报告 | ❌ | ✅ |
| 上传文档与问题清单 | ❌ | ✅ |
| 需求符合性判定 | 仅提供安全事实 | ✅ |

#### 6.3 主 Agent 处理要求

1. **原样接收**子代理返回的「安全审计结果」，不得无证据删减高危发现；步骤 8 的独立复核若提供明确反证，可撤回并保留原因
2. 将安全发现并入步骤 8 的总报告，新增「🛡️ 安全审计」章节
3. 按等级映射写入问题清单：

   | 安全等级（code-audit） | 主报告等级 | 建议 issueCategory |
   | ---------------------- | ---------- | ------------------ |
   | 🟣 严重 / 🔴 高危 | 🔴 严重 | 安全漏洞 |
   | 🟠 中危 | 🟡 一般 | 安全风险 |
   | 🔵 低危 / ⚪ 信息 | 🔵 优化 | 安全加固 |

4. 上传问题时，每个安全发现单独创建 issue，`commitId` 使用对应 commit 的 `full_hash`
5. 若存在 🟣严重 / 🔴高危，必须在报告「审查摘要」中单列安全风险提示

#### 6.4 无发现或阻塞时

- 子代理返回「未发现问题」时，主 agent 仍要在报告中保留「🛡️ 安全审计」章节，写明覆盖范围与已检查分类
- 子代理返回「阻塞」（如 `code-audit` 技能缺失）时，在主报告中标注阻塞原因，不得静默跳过

### 步骤 7：前后端接口对接审查（全栈开发场景）

**⚠️ 重要：当代码变更同时包含前后端代码时，必须执行此步骤**

#### 触发条件

满足以下任一条件时触发：
1. 变更记录中同时存在前端代码（`*.vue`, `*.tsx`, `*.jsx`等）和后端代码（`*.java`, `*.xml`等）
2. 需求文档明确说明涉及前后端联调
3. 用户明确要求审查前后端对接

#### 审查步骤

**7.1 识别前后端接口调用关系**

从步骤5的调用链分析结果中提取：
- **前端调用**：API请求代码（axios/fetch调用）
  - 请求地址、HTTP方法
  - 请求参数结构
  - 响应数据处理逻辑

- **后端接口**：Controller接口定义
  - 接口路径、HTTP方法
  - 请求参数定义（@RequestBody/@RequestParam）
  - 响应结果定义（返回值类型）

**7.2 接口对接一致性检查**

逐一对比前后端接口，检查以下维度：

| 检查项 | 检查内容 | 问题等级 |
|-------|---------|----------|
| 🔗 **接口路径** | URL路径是否完全匹配（含路径参数） | 🔴 严重 |
| 🔧 **HTTP方法** | GET/POST/PUT/DELETE是否一致 | 🔴 严重 |
| 📤 **请求参数** | 字段名、类型、必填性是否一致 | 🔴 严重 |
| 📥 **响应结构** | 返回数据结构是否匹配 | 🔴 严重 |
| 🔢 **数据类型** | 字段类型映射（String/Number/Boolean等） | 🔴 严重 |
| 📝 **字段命名** | 前后端字段命名风格一致性（camelCase/snake_case） | 🟡 一般 |
| 🔄 **枚举值** | 状态码、枚举值是否对齐 | 🔴 严重 |
| ⚠️ **错误处理** | 前端是否正确处理后端错误响应 | 🟡 一般 |
| 🔐 **权限参数** | token/userId等认证参数是否传递 | 🔴 严重 |

**7.3 常见对接问题示例**

**问题1：请求参数字段不匹配**
```javascript
// ❌ 前端代码
axios.post('/api/order/cancel', {
  orderIds: ['001', '002'],  // 字段名：orderIds（复数）
  reason: '用户取消'
})

// ❌ 后端代码
@PostMapping("/cancel")
public Result cancel(@RequestBody CancelOrderRequest request) {
    List<String> orderId = request.getOrderId();  // 字段名：orderId（单数）
    // ...
}
```
**问题**：前端传 `orderIds`，后端接收 `orderId`，字段名不匹配导致接收为null

**修复**：统一字段名
```javascript
// ✅ 前端修复
orderIdList: ['001', '002']  // 改为 orderIdList

// ✅ 后端修复  
List<String> orderIdList = request.getOrderIdList();
```

**问题2：响应数据结构不匹配**
```javascript
// ❌ 前端代码
const { data } = await api.getUserList();
const users = data.list;  // 期望：{ list: [...], total: 100 }
const total = data.total;

// ❌ 后端代码
@GetMapping("/list")
public Result<List<User>> list() {
    return Result.success(userList);  // 实际返回：List<User>
}
```
**问题**：前端期望分页结构，后端直接返回列表，导致 `data.total` 为 undefined

**修复**：统一返回结构
```java
// ✅ 后端修复
@GetMapping("/list")
public Result<PageResult<User>> list() {
    PageResult<User> pageResult = new PageResult<>();
    pageResult.setList(userList);
    pageResult.setTotal(total);
    return Result.success(pageResult);
}
```

**问题3：枚举值不对齐**
```javascript
// ❌ 前端代码
if (order.status === 'pending') {  // 前端使用英文：pending
  // ...
}

// ❌ 后端代码
if ("待支付".equals(order.getStatus())) {  // 后端使用中文：待支付
  // ...
}
```
**问题**：前后端状态码不一致，前端判断永远为false

**修复**：统一枚举定义
```java
// ✅ 后端定义枚举
public enum OrderStatus {
    PENDING("pending", "待支付"),
    PAID("paid", "已支付");
    
    private String code;  // 给前端用
    private String desc;  // 给后端显示
}

// ✅ 接口返回
return Result.success(order.getStatus().getCode());  // 返回 "pending"
```

**7.4 生成接口对接审查结果**

在审查报告中添加独立章节：

```markdown
## 前后端接口对接审查

### 接口清单

| 接口路径 | HTTP方法 | 前端调用 | 后端实现 | 状态 |
|---------|---------|---------|---------|------|
| /api/order/cancel | POST | ✅ | ✅ | 🟢 一致 |
| /api/order/list | GET | ✅ | ⚠️ | 🔴 不匹配 |

### 对接问题列表

#### [🔴严重] 订单列表接口响应结构不匹配

**前端代码**：
- 文件：`src/api/order.ts`
- 调用：`const { list, total } = data;`

**后端代码**：
- 文件：`OrderController.java`
- 返回：`Result<List<Order>>`（缺少total字段）

**问题**：前端期望分页结构，后端直接返回列表

**修复方案**：（参考上述示例）

#### [🔴严重] 取消订单接口字段名不匹配

...
```

#### 7.5 前后端联调测试建议

在报告末尾添加联调测试建议：

```markdown
## 联调测试建议

### 必测场景

1. **接口连通性测试**
   - [ ] 前端能正常调用后端接口
   - [ ] 请求参数正确传递到后端
   - [ ] 后端响应前端能正确解析

2. **数据一致性测试**
   - [ ] 字段值在前后端传递过程中无丢失
   - [ ] 日期时间格式转换正确
   - [ ] 枚举值前后端理解一致

3. **异常场景测试**
   - [ ] 后端校验失败时前端能正确提示
   - [ ] 网络异常时前端能优雅降级
   - [ ] 权限不足时前端能正确处理

### 联调工具推荐

- **接口文档对比**：使用Swagger/Apifox生成接口文档，对比前后端理解
- **Mock测试**：前端使用Mock数据先行开发，对齐数据结构
- **抓包验证**：使用浏览器开发者工具/Charles验证实际请求响应
```

---

### 步骤 8：生成审查报告

使用 `.specify/templates/code-review/template.md` 模板生成报告。

**报告内容**：
- **【如有需求文档】需求摘要与符合性总结**
- 调用链路图（来自子代理）
- **🛡️ 安全审计摘要（来自 `speckit.code-review-security` 子代理）**
  - 审计范围与覆盖文件
  - 安全发现清单（严重级别 / CWE / OWASP / CVSS / 位置 / commit）
  - 正面安全发现
  - 无发现时也要保留章节并写明覆盖范围
- **【如有前后端代码】前后端接口对接审查结果**
- 问题列表（按严重程度排序）
  - 代码质量问题
  - **安全审计问题（已按 6.3 的等级映射归一）**
  - **【如有需求文档】需求偏离问题**
  - **【如有前后端代码】接口对接问题**
- 修复方案（含代码示例）
- 每个问题关联 commit hash
- **【如有前后端代码】联调测试建议**

**报告路径**：`docs/review-results/code-review-YYYY-MM-DD-{author_name}.md`

#### 8.1 独立报告复核（上传前必须执行）

报告生成后不得直接上传。调用 `speckit.code-review-report-verifier`（定义见 `code-review-report-verifier-agent.md`），独立排查问题幻觉并检查报告完整性。

```javascript
runSubagent({
  agentName: "speckit.code-review-report-verifier",
  description: "独立复核审查报告",
  prompt: `
请独立复核以下报告，主动寻找反证，不能仅复述原审查结论。
仓库根目录：{repo_root}
project_name：{project_name}
报告路径：{report_path}
评审范围：{full_hash_list_or_base_head}
报告模板和审查规范：{template_and_rule_paths}
需求来源（如有）：{requirement_sources}
变更收集、调用链、安全审计结果：{upstream_result_paths_or_complete_results}
模式：{初审或第N轮修订复查}
上一轮复核与修订记录（复查必传）：{previous_verdict_and_revision_record}
逐条返回通过、需修订、不成立或待验证，并返回完整性检查和上传门控。
仅独立取证和提出意见，不修改报告或代码，不上传。
  `
})
```

多仓库必须传入各自准确的提交范围和项目归属。必须核实目标提交版本源码，不能以当前 HEAD 代替。没有上游结果文件时，传入完整结果并注明来源，不得只传摘要。

#### 8.2 主 Agent 修订与对抗式复查

1. 主 Agent 保留逐问题复核记录；通过的问题保留，需修订的问题按证据修改。
2. 不成立的问题必须有明确反证，删除正式问题并保留撤回原因；包括严重或高危安全发现，不得无证据删减。
3. 待验证的问题写入待验证说明，不得冒充已确认问题；缺少上下文时向用户说明所需信息。
4. 主 Agent 统一修订总报告，重新计算统计、同步摘要和详情、合并同根因重复问题并保留来源；不修改业务代码。
5. 修订后再次调用复核子代理，传入最新报告、上一轮结论和逐项修订记录，复查修改项及报告整体一致性。
6. 最多两轮修订复查；仍有争议、完整性错误或阻塞时停止上传，明确输出未通过和待处理事项，不得无限循环或声称通过。

主 Agent 将复核结果及修订记录保存到报告同目录的 `code-review-YYYY-MM-DD-{author_name}-verification.md`，记录报告路径、轮次、逐项处理及最终门控。复核子代理保持只读。

#### 8.3 上传门控

仅当最新报告经复核返回“总体结论：通过”和“上传门控：允许”，且已处理所有修订、待验证与阻塞项时，才能进入步骤 9。记录复核摘要与轮次，并上传这一版已通过的报告；门控后若报告实质内容再次改变，必须重新复核。

没有发现问题的报告同样必须完成复核，不得跳过覆盖范围与完整性检查。该流程借鉴对抗式评审思想，不是 GAN 训练，也不要求复核代理强行找错。

### 步骤 9：同步问题清单到远程服务器

**⚠️ 重要：完成审查报告后，必须调用 upload-doc MCP工具将问题拆解并同步到远程服务器**

**前提**：步骤 8.3 上传门控通过；否则不得调用文档或问题上传工具。

#### 9.1 创建代码审查文档

使用 `mcp_upload-doc_create_code_review_document` 工具创建完整的代码审查文档：

```javascript
mcp_upload-doc_create_code_review_document({
  docName: "代码审查报告 - {需求名称或功能模块} - {日期}",
  docContent: "{完整的审查报告内容（Markdown格式）}",
  project_name: "{项目名称}",  // 必须：从步骤3.1的元数据获取
  systemName: "{系统名称，如：ECP订单中心}",  // 可选
  commitUser: "{提交用户姓名}"  // 可选
})
```

**参数说明**：
- `docName`：文档标题，建议格式：`代码审查报告 - [需求名称/功能模块] - YYYY-MM-DD`
- `docContent`：完整的审查报告内容（Markdown格式字符串）
- **`project_name`**：**必填**，项目名称（从步骤3.1收集的仓库元数据中的 `project_name` 字段获取）
- `systemName`：系统名称（可选），如"ECP订单中心"、"海外订单平台"等
- `commitUser`：提交用户姓名（可选），如"张三"、"李四"等

**返回值**：文档ID（documentId），用于后续创建问题清单

#### 9.2 拆解并创建问题清单

对审查报告中的**每个问题**，调用 `mcp_upload-doc_create_code_review_issue` 创建独立的问题条目：

```javascript
mcp_upload-doc_create_code_review_issue({
  documentId: "{步骤9.1返回的documentId}",
  issueTitle: "{问题标题}",
  issueContent: "{问题详细说明（Markdown格式）}",
  project_name: "{项目名称}",  // 必须：从步骤3.1的元数据获取
  commitId: "{full_hash}"  // 必须：从步骤3.2收集的长hash
})
```

**参数说明**：
- `documentId`：步骤9.1返回的文档ID
- `issueTitle`：问题标题，建议格式：`[严重程度] 问题简述 - 文件名`
  - 例如：`[🔴严重] 循环中存在数据库查询 - OrderServiceImpl.java`
  - 例如：`[🟡一般] 事务传播行为不当 - ProductService.java`
- `issueContent`：问题的完整详细说明，必须包含：
  - 问题描述
  - 问题代码示例（❌）
  - 修复方案及代码示例（✅）
  - 影响说明
  - 关联的commit hash（短hash，用于显示）
  - **【如有需求】需求符合性说明**
- **`project_name`**：**必填**，项目名称（从步骤3.1收集的仓库元数据中的 `project_name` 字段获取）
- **`commitId`**：**必填**，提交的完整hash（从步骤3.2的 `full_hash` 字段获取）

**执行规范**：
1. **逐个问题调用**：对审查报告中的每个问题（🔴严重、🟡一般、🔵优化）都要调用此工具
2. **内容完整性**：确保 `issueContent` 包含问题的所有关键信息（问题代码、修复方案、影响说明等）
3. **与报告一致**：问题清单的内容必须与审查报告中的问题描述区域完全一致
4. **调用顺序**：必须先调用步骤9.1创建文档，获得documentId后，才能调用步骤9.2创建问题
5. **project_name必传**：必须使用步骤3.1元数据中的项目名称（仓库级别的project_name）
6. **commitId必传**：每个问题都必须关联对应的commit长hash（从步骤3.2的full_hash获取）

#### 9.3 执行示例

**完整流程**：

```javascript
// 步骤1：创建审查文档
const result1 = await mcp_upload-doc_create_code_review_document({
  docName: "代码审查报告 - 订单批量取消功能 - 2026-01-22",
  docContent: `# 代码审查报告
## 审查摘要
...完整的Markdown报告内容...`,
  project_name: "ecp-order-service",  // 从步骤3.1的元数据中获取
  systemName: "ECP订单中心",
  commitUser: "张三"
});

const documentId = result1.documentId;  // 获取文档ID

// 步骤2：拆解并创建问题清单（逐个问题，必须传递project_name和commitId）
await mcp_upload-doc_create_code_review_issue({
  documentId: documentId,
  issueTitle: "[🔴严重] 循环中存在数据库查询 - OrderServiceImpl.java",
  project_name: "ecp-order-service",  // 从步骤3.1的元数据中获取
  commitId: "abc123def456789012345678901234567890abcd",  // 长hash（从步骤3.2的full_hash获取）
  issueContent: `## 问题描述
在批量取消订单的循环中，每次都调用了数据库查询...

## 问题代码
\`\`\`java
❌ 当前代码
for (String orderId : orderIds) {
    Order order = orderMapper.selectById(orderId);  // 循环查询
    ...
}
\`\`\`

## 修复方案
\`\`\`java
✅ 修复后
List<Order> orders = orderMapper.selectByIds(orderIds);  // 批量查询
for (Order order : orders) {
    ...
}
\`\`\`

## 影响说明
- 性能影响：100个订单将产生100次数据库查询
- 修复收益：改为批量查询后性能提升90%

## 关联Commit
- abc123def - 实现订单批量取消功能（短hash显示）
- 完整hash: abc123def456789012345678901234567890abcd
`
});

await mcp_upload-doc_create_code_review_issue({
  documentId: documentId,
  issueTitle: "[🟡一般] 缺少事务控制 - OrderServiceImpl.java",
  project_name: "ecp-order-service",  // 从步骤3.1的元数据中获取
  commitId: "def456abc789012345678901234567890abcdef12",  // 长hash
  issueContent: `## 问题描述
批量取消订单操作缺少事务控制...
...
`
});

// 继续为其他问题创建issue（每个都必须传递project_name和commitId）...
```

#### 9.4 同步完成确认

完成所有问题同步后，输出确认信息：

```markdown
✅ 代码审查完成并已同步到远程服务器

📄 审查文档ID：{documentId}
📋 问题总数：{issueCount}
  - 🔴 严重问题：{criticalCount}
  - 🟡 一般问题：{normalCount}
  - 🔵 优化建议：{optimizationCount}

📁 本地报告：docs/review-results/code-review-YYYY-MM-DD-{author_name}.md
```


### 步骤 10: 回填审查报告ID
评审完成后，若当前存在评审记录documentId，且当前存在openReviewRecord工具，请主动调用下openReviewRecord工具，打开鉴渊AI代码评审面板，并定位评审文档，传递当前代码评审记录ID：{documentId}



---

## 子代理调用规范
**后端示例**：
```javascript
// 只给最少的起点信息，让子agent自主调查
runSubagent({
  description: "追踪后端调用链",
  prompt: `
分析commit 17e7a1e2的调用链：

变更文件: op-biz/src/main/resources/mapper/EveryLevelOptionalPartnerMapper.xml
变更方法: searchChannelListByTypeName
变更内容: 移除GROUP BY，添加DISTINCT

任务：自主追踪完整调用链路径（Controller → Service → Mapper → SQL）。
  `
})
```

**前端示例**：
```javascript
runSubagent({
  description: "追踪前端调用链",
  prompt: `
分析commit a3f5c89的调用链：

变更文件: src/pages/UserManagement/UserList.tsx
变更内容: 新增批量删除用户功能

任务：自主追踪完整调用链路径（Component → Hook → API → State）。
  `
})
```

**安全审计示例**：
```javascript
// 安全子代理必须自行加载 code-audit 技能，主agent不预判漏洞
runSubagent({
  description: "增量安全审计",
  agentName: "speckit.code-review-security",
  prompt: `
对本次代码变更执行增量安全审计（必须调用 code-audit 技能）。

仓库根目录: {repo_root}
project_name: {project_name}
变更提交: {短hash（full_hash: 长hash） 提交信息}
变更文件: {变更文件列表}

要求：只审计本次变更及直接调用链，按固定结构返回，不生成HTML、不写文件、不修改代码。
  `
})
```

### 错误调用方式 ❌

```javascript
// 不要预先搜索代码、读取文件、梳理调用关系
runSubagent({
  prompt: `
已知信息：
- Controller代码: [完整代码]
- Service代码: [完整代码]
- 调用关系: Controller -> Service -> Mapper

请按格式输出...  // 这样子agent只是格式化工具
  `
})
```

### 职责分工

**主Agent（Code Review）**：
- **调用 speckit.code-review-collect 子代理收集变更记录**
- 识别变更文件和方法
- 调用 speckit.code-review-analyze 子代理（只给起点信息：commit、文件、变更描述）
- 接收路径报告
- **调用 speckit.code-review-security 子代理执行增量安全审计（内调 code-audit 技能）**
- **接收安全发现并合并到总报告**
- **【如有需求文档】进行需求符合性检查**
- **评估代码质量**
- 生成审查报告
- 上传报告与问题清单

**子Agent（speckit.code-review-collect）**：
- 交互式引导用户选择审查场景
- 验证用户输入信息完整性
- 调用 git-commit-log 或 feishu-doc-reader 技能
- 扫描本地Git仓库（如需要）
- 返回标准格式的变更记录

**子Agent（speckit.code-review-analyze）**：
- 收到最少的起点信息
- **自主使用grep_search搜索代码**
- **自主使用read_file读取文件**
- **自主追踪调用链**
- 提供路径分析报告（客观事实）
- **不做需求对比**
- **不做质量评价**

**子Agent（speckit.code-review-security）**：
- 必须先加载并调用 `code-audit` 技能，采用增量模式
- 只审计本次变更代码及其直接调用链
- 执行 STRIDE 建模、污点追踪、OWASP/CWE 检查、误报过滤
- 输出结构化安全发现（含 CWE、CVSS、文件:行号、关联 commit）
- **不生成 HTML、不写文件、不修改代码、不上传**
- **不做需求符合性最终判定，只提供安全事实**

---

## 子代理调用时机

| 场景 | 是否调用 | 说明 |
|------|---------|------|
| 每个提交记录 | ✅ 必须 | 逐个分析，不批量处理 |
| 跨模块调用 ≤ 2 | ✅ 必须 | 虽然简单，但保持流程一致性 |
| 跨模块调用 ≥ 3 | ✅ 必须 | 复杂场景更需要子代理 |
| 安全审计 | ✅ 必须 | 每次评审至少调用一次 `speckit.code-review-security`，同类变更合并为一次增量审计 |
| `code-audit` 技能缺失 | ⚠️ 阻塞 | 安全子代理返回阻塞，主 agent 在报告中明确标注，不得静默跳过 |

**原则：每个提交至少一个子代理分析**

---

## 执行清单

```markdown
前置准备：
- [ ] 确认审查标准文档存在
- [ ] 确认报告模板存在

代码同步：
- [ ] 调用 git-branch-sync（如需要）

收集代码变更（使用 developer-info-collector 技能）：
- [ ] 步骤3.1：收集Git仓库元数据
  - [ ] 调用 collect_info.py 扫描所有仓库
  - [ ] 读取并加载JSON输出到上下文
  - [ ] 获取仓库列表和contributors信息
- [ ] 步骤3.2：收集提交记录
  - [ ] 询问用户：审查的开发者、时间范围
  - [ ] 询问用户：是否需要需求文档
  - [ ] AI根据contributors列表校准开发者名称
  - [ ] 针对每个仓库调用 collect_commits.py
  - [ ] 确保返回的数据包含 full_hash 字段
- [ ] 步骤3.3：验证收集结果
  - [ ] 仓库元数据不为空
  - [ ] 提交记录不为空
  - [ ] 每个提交都有 full_hash（长hash）

需求文档理解（如已获取则跳过）：
- [ ] 识别需求文档来源（飞书/本地/直接输入）
- [ ] 使用对应技能或工具获取需求内容
- [ ] 提取功能需求、业务规则、性能要求等
- [ ] 记录关键检查点

逐个提交分析：
- [ ] 遍历每个提交
- [ ] 调用 speckit.code-review-analyze 子代理（只给commit信息和变更文件）
- [ ] 让子agent自主搜索代码、追踪调用链
- [ ] 接收子agent的路径分析报告（客观事实，无质量评价）
- [ ] 基于路径报告，必要时补充阅读代码
- [ ] 【如有需求】主agent进行需求符合性检查
- [ ] 应用审查标准发现问题
- [ ] 生成修复方案

安全审计：
- [ ] 调用 speckit.code-review-security 子代理（一次增量审计）
- [ ] 传入仓库根目录、project_name、commit（含 full_hash）、变更文件、需求背景
- [ ] 要求子代理调用 code-audit 技能，不生成 HTML、不写文件、不上传
- [ ] 接收结构化安全发现，校验每个发现都有文件:行号与关联 commit
- [ ] 按 6.3 等级映射归一到总报告问题分级
- [ ] 在报告中新增「🛡️ 安全审计」章节（无发现也要保留）
- [ ] 🟣严重/🔴高危发现写入报告摘要并单列提示

前后端接口对接审查（全栈场景）：
- [ ] 检查变更记录是否同时包含前后端代码
- [ ] 如是，识别前后端接口调用关系
- [ ] 检查接口路径、HTTP方法、请求参数、响应结构一致性
- [ ] 检查字段名、数据类型、枚举值对齐情况
- [ ] 发现接口对接问题并生成修复方案
- [ ] 在报告中添加接口对接审查章节
- [ ] 提供联调测试建议

生成报告：
- [ ] 汇总所有提交的分析结果
- [ ] 按模板生成报告
- [ ] 保存到 docs/review-results/

报告复核与修订：
- [ ] 调用 speckit.code-review-report-verifier，传入报告、准确提交范围、模板规范及完整上游结果
- [ ] 独立检查每条问题的证据、可达性、风险等级、需求依据与修复方案
- [ ] 检查范围覆盖、安全结果、问题详情、统计与摘要一致性
- [ ] 主 Agent 按通过 / 需修订 / 不成立 / 待验证逐项处理，保留反证和修订记录
- [ ] 最多两轮修订复查，重新读取最新报告并检查整体一致性
- [ ] 确认无未解决修订、待验证或阻塞，最新复核允许上传
- [ ] 无问题报告也完成复核；门控后实质修改必须重新复核

同步问题清单：
- [ ] 步骤 8.3 上传门控通过后才调用上传工具
- [ ] 步骤9.1：调用 mcp_upload-doc_create_code_review_document 创建审查文档
  - [ ] 必须传递 project_name 参数（从步骤3.1元数据获取）
- [ ] 获取返回的 documentId
- [ ] 步骤9.2：逐个调用 mcp_upload-doc_create_code_review_issue 创建问题清单
  - [ ] 每个问题必须传递 project_name 参数（从步骤3.1元数据获取）
  - [ ] 每个问题必须传递 commitId 参数（长hash，从步骤3.2的 full_hash 获取）
  - [ ] 确保问题内容与报告一致
- [ ] 确认所有问题都已同步
- [ ] 输出同步完成确认信息
```

---

## 关键原则

1. **职责分工明确**
   - code-review（主agent）：
     - 数据收集（使用 developer-info-collector 技能）
     - 需求理解（如有）
     - 质量评估（应用审查规范）
     - 调度安全审计子代理并合并安全发现
     - 前后端对接审查（全栈场景）
     - 上传问题时传递 project_name 和 commitId（长hash）
   - speckit.code-review-analyze（子agent）：
     - 路径追踪（自主调查）
     - 客观事实分析（不做质量评价）
   - speckit.code-review-security（子agent）：
     - 调用 code-audit 技能做增量安全审计（OWASP Top 10 + CWE Top 25）
     - 输出结构化安全发现，不落盘、不上传

2. **技能调用规范**
   - ✅ 主agent使用 developer-info-collector 技能收集数据（两步式工作流）
   - ✅ 步骤1：扫描仓库元数据（collect_info.py）
   - ✅ 步骤2：收集提交记录（collect_commits.py），必须获取 full_hash
   - ✅ 安全审计统一由 `speckit.code-review-security` 子代理调用 `code-audit` 技能完成
   - ❌ 主agent不得绕过安全子代理自行下安全结论

3. **主agent不要微观管理子agent**
   - 不要预先搜索所有代码
   - 不要梳理好调用关系
   - 不要预先判定安全漏洞
   - 只给起点信息（commit、文件、变更描述、仓库路径），信任子agent

4. **安全审计纪律**
   - 只审本次变更及直接调用链，不做存量全量扫描
   - 每个安全发现必须具备文件:行号与关联 commit 的 full_hash
   - 严格遵守 `code-audit` 的排除项（硬编码凭据、高权限DB账户、配置明文、认证开关关闭）
  - 安全发现必须全部纳入复核处理；确认成立的问题并入总报告并逐个上传，不得只上传高危；撤回问题保留反证，待验证问题未解决前禁止上传

5. **前后端对接审查重要性**
   - 全栈开发必检项，防止接口对接问题
   - 重点检查字段匹配、数据类型、枚举值对齐
   - 提供明确的修复方案和联调测试建议

---

## 技能依赖

### 主agent直接使用的技能
1. **developer-info-collector** - 收集仓库元数据和提交记录（两步式）
   - 步骤1：collect_info.py - 扫描所有Git仓库
   - 步骤2：collect_commits.py - 收集提交记录（包含 full_hash）
   
2. **feishu-doc-reader** - 读取飞书需求文档（可选）
   - 当用户提供飞书文档链接时使用
   
3. **git-branch-sync** - 同步代码（可选）
   - 在获取提交记录前执行

### 子代理调用
4. **runSubagent** - 调用子代理
   - speckit.code-review-analyze（路径追踪）
   - speckit.code-review-security（安全审计，定义见 `code-review-security-agent.md`）
  - speckit.code-review-report-verifier（独立报告复核，定义见 `code-review-report-verifier-agent.md`；只读核实，主 Agent 修订，上传前门控）

### 安全子代理使用的技能
5. **code-audit** - OWASP Top 10 + CWE Top 25 白盒安全审计（必选）
   - 由 `speckit.code-review-security` 子代理主动加载并调用
   - 采用增量模式，只审计本次变更及直接调用链
   - 路径优先级：`.agents/skills/code-audit/` → `.claude/skills/code-audit/` → `.specify/templates/skills/code-audit/` → `templates/skills/code-audit/`
   - 仅使用其检查、污点追踪、定级与误报过滤能力；不生成 HTML、不执行修复

### 远程同步工具
6. **mcp_upload-doc_create_code_review_document** - 创建代码审查文档
7. **mcp_upload-doc_create_code_review_issue** - 创建代码审查问题清单


工具名称：create_code_review_document     
docName          完整的代码评审结果的文档标题
docContent       完整的代码评审结果的文档内容
project_name     评审代码所属的项目名称: 取Git仓库的project_name（从步骤3.1元数据获取）
createUser       当前文档数据的创建人，通常是用户邮箱
commitUser       编写代码的提交人提交用户名称

工具名称：create_code_review_issue
documentId       代码评审文档ID,需要先创建导入代码评审文档ID
issueTitle       完整的每一个代码评审结果文档中的问题标题名称
issueContent     完整的每一个代码评审结果文档中的问题详细说明内容，需要和代码评审结果文档中的问题描述区域的内容一致
project_name     评审代码所属的项目名称: 取Git仓库的project_name（从步骤3.1元数据获取）
commitId         提交的完整hash（长hash，从步骤3.2的full_hash字段获取）
issueCategory    评审代码问题的问题分类，通常是4-8个字说明

---

## 审查边界

✅ **允许**：
- 审查本次修改的代码及其调用链
- 审查与修改点直接交互的方法

❌ **禁止**：
- 对整个项目全面审查
- 审查无关的历史遗留问题

---

## 问题分类

### 代码质量问题

- 🔴 **严重**（必修）：影响稳定性、性能、安全
  - 循环中的数据库查询/外部调用
  - SQL注入风险
  - 大事务导致性能问题
  - 未处理异常可能崩溃

- 🟡 **一般**（建议修）：影响代码质量但不致命
  - 事务传播行为不当
  - 异常处理不完善
  - 日志记录不规范
  - 命名不清晰

- 🔵 **优化**（可选）：改进可维护性
  - 代码结构优化
  - 设计模式应用
  - 性能微调

### 安全问题（步骤 6 安全审计产出）

安全发现沿用 `code-audit` 的原始分级，在主报告中按 6.3 的映射归一：

- 🔴 **严重**：安全等级为 🟣严重 / 🔴高危
  - 未授权访问、越权（IDOR）、SQL注入、命令执行、反序列化、SSRF
- 🟡 **一般**：安全等级为 🟠中危
  - 需特定条件才能利用的数据泄露、CSRF、敏感信息泄露
- 🔵 **优化**：安全等级为 🔵低危 / ⚪信息
  - 安全头缺失、错误信息过详、依赖升级建议

每条安全问题的 `issueCategory` 建议填：`安全漏洞` / `安全风险` / `安全加固`。

### 需求符合性问题（当提供需求文档时）

- 🔴 **需求偏离 - 严重**：功能缺失或错误
  - 必需功能未实现
  - 接口定义不符合规范
  - 业务规则实现错误
  - 安全要求未满足

- 🟡 **需求偏离 - 一般**：实现不完整
  - 非核心功能缺失
  - 性能要求未达标
  - 数据模型部分不符
  - 边界条件处理不当

- 🔵 **需求优化**：可改进项
  - 用户体验优化建议
  - 扩展性改进
  - 错误提示优化

---

**版本**：1.5  
**更新日期**：2026-11-02  
**维护者**：皮皮芳  
**变更说明**：
- v1.5:
  - ✨ 新增：步骤6 安全审计，调用 `speckit.code-review-security` 子代理
  - ✨ 新增：安全子代理通过 `code-audit` 技能执行 OWASP Top 10 + CWE Top 25 增量审计
  - 🔧 调整：安全发现由子代理返回，主 agent 统一写入总报告并上传
  - 🔄 重编：原步骤6/7/8/9 顺延为步骤7/8/9/10
- v1.4:
  - 🔧 优化：简化步骤3，使用 developer-info-collector 技能的两步式工作流
  - 🗑️ 移除：步骤3.1（确定审查场景）和3.2（识别Git仓库）的复杂逻辑
  - ✅ 确保：提交记录包含 full_hash 字段（长hash）
  - 🔧 修复：步骤8上传问题时必须传递 project_name 和 commitId 参数
  - 📝 文档：更新执行清单，明确技能调用规范
- v1.3: 
  - 🔧 修复：主agent直接使用技能收集代码变更（移除collect子agent调用）
  - ✨ 新增：前后端接口对接审查（全栈开发场景）
  - 🚀 增强：自动识别多仓库结构
- v1.2: 新增需求文档理解和需求符合性审查功能
- v1.1: 引入 Logic Analysis 子代理，职责分离
