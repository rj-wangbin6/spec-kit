---
name: code-audit
version: 1.6
description: "OWASP Top 10 + CWE Top 25 白盒代码安全审计。触发词：代码审计、安全扫描、漏洞检查、安全审查、越权检查、OWASP检查、SQL注入、XSS、敏感信息检查、威胁建模、合规检查、逻辑漏洞、中间件安全、组件漏洞、文件泄露。覆盖注入/越权/信息泄露/CSRF/SSRF/反序列化/业务逻辑/API安全/供应链等。v1.6 基于 SOC 507 条真实漏洞工单新增：中间件默认配置检查、高频组件 CVE 识别、部署产物泄露检查、文件操作安全审计。提供 STRIDE 建模、污点追踪、CWE/CVSS 映射、合规对照、HTML 报告输出。"
---

# OWASP 全面代码安全审计（v1.6 — SOC 实战增强版）

面向项目代码执行完整的 OWASP Top 10 + CWE Top 25 安全审计，集成 STRIDE 威胁建模、数据流污点追踪、业务逻辑深度检查、自我验证、正面发现记录，生成专业 HTML 漏洞报告，提供一键修复和合规性对照。

**v1.6 核心增强**：基于 SOC 安全管理平台 507 条真实漏洞工单数据验证，新增四大高频漏洞检查类别（中间件默认配置、高频组件 CVE、部署产物泄露、文件操作安全），覆盖实际环境中 70% 以上的安全事件类型。

---

## 适用场景

| 场景 | 触发方式 | 审计范围 |
|------|----------|----------|
| **全量审计** | "代码审计"、"安全扫描"、"OWASP 检查" | 扫描全部源代码 |
| **增量审计** | "审计这次改动"、"Review PR 安全" | 仅扫描 `git diff` 变更文件 |
| **定向审计** | "检查 SQL 注入"、"检查越权" | 仅执行指定类别的检查 |
| **合规审计** | "PCI-DSS 合规检查"、"SOC2 审计" | 按合规框架裁剪检查项 |

---

## 审计前初始化

### Step 0: 环境准备与配置

1. **确定 Skill 目录路径**：Skill 文件位于 `.agents/skills/code-audit/`。

2. **读取参考文件**（审计前必须全部加载）：
   - `references/owasp_checklist.md` — OWASP Top 10 详细检查清单（含代码示例）
   - `references/vuln_patterns.md` — 各语言漏洞模式速查
   - `references/cwe_mapping.md` — CWE Top 25 映射表 + CVSS 速查 + 合规映射
   - `references/report_template.md` — HTML 报告模板

3. **确定审计模式**：
   - 若用户提到"这次改动"、"PR"、"diff" → 增量模式：`git diff --name-only HEAD~1` 获取变更文件列表
   - 若用户指定某个漏洞类别 → 定向模式：仅执行对应检查
   - 否则 → 全量模式

---

## 审计执行流程

### Phase 1: 情报收集（Reconnaissance）

#### Step 1: 项目结构扫描与攻击面识别

1. **确定项目根目录**（通常为工作区根目录）。
2. **技术栈识别** — 遍历所有源代码文件，识别：
   - 编程语言：Python、Go、Java、JS/TS、PHP、Rust、C#、Ruby 等
   - Web 框架：Flask/Django/FastAPI、Gin/Echo/Fiber、Spring Boot/Quarkus、Express/Nest/Koa、Laravel/Symfony 等
   - 数据库：PostgreSQL/MySQL/SQLite/MongoDB/Redis/ElasticSearch
   - 前端框架：React/Vue/Angular/Svelte/Next.js/Nuxt
   - 容器化：Dockerfile、docker-compose.yml、K8s manifests
   - CI/CD：.github/workflows、Jenkinsfile、.gitlab-ci.yml
3. **攻击面枚举** — 列举所有入口点：
   - HTTP 路由端点 / REST API
   - WebSocket 端点
   - GraphQL schema（queries/mutations/subscriptions）
   - gRPC 服务定义
   - 消息队列消费者（Kafka/RabbitMQ/Redis Pub-Sub）
   - 定时任务 / Cron Jobs
   - CLI 命令入口
   - 文件上传端点
   - Webhook 接收端点
4. **关键代码区域定位**：
   - 认证与授权（中间件、装饰器、过滤器）
   - 数据库操作（ORM + raw SQL）
   - 文件 I/O（上传/下载/读取/写入）
   - 外部 HTTP/TCP 请求
   - 反序列化 / 序列化
   - 加密 / 哈希 / 签名
   - 日志记录
   - 配置管理（环境变量、配置文件）
   - 错误处理（异常捕获、错误响应）

### Phase 2: 威胁分析（Threat Analysis）

#### Step 2: STRIDE 威胁建模

在深入代码审查前，先进行系统级威胁分析，产出信任边界描述：

| 威胁维度 | 分析内容 | 对应 OWASP |
|----------|----------|-----------|
| **S — 欺骗（Spoofing）** | 认证是否可绕过？Token/Session 可伪造？Cookie 是否防篡改？ | A07 |
| **T — 篡改（Tampering）** | 请求参数可篡改？数据完整性有校验？CSRF 保护是否到位？ | A08 |
| **R — 否认（Repudiation）** | 关键操作有审计日志？能追溯到操作者？日志防篡改？ | A09 |
| **I — 信息泄露（Info Disclosure）** | 错误信息/API 响应/日志泄露敏感数据？前端暴露密钥？ | A02 |
| **D — 拒绝服务（DoS）** | 有速率限制？存在资源耗尽风险？大文件上传无限制？ | A04 |
| **E — 权限提升（EoP）** | 普通用户可执行管理操作？有角色边界？批量赋值风险？ | A01 |

**输出格式**：
```
信任边界分析：
├── 外部用户 → [认证层] → 业务逻辑
├── 内部 API → [授权层] → 数据访问
├── 第三方服务 → [验证层] → 回调处理
└── 定时任务 → [无认证] → 数据库操作  ⚠️ 风险点
```

#### Step 3: 数据流污点追踪

对每个用户输入源（Source），追踪传播路径到最终使用点（Sink）。

**Source 全量清单**：

| 类别 | Source 示例 |
|------|------------|
| HTTP 参数 | `request.args`, `request.form`, `request.json`, `req.body`, `req.query`, `req.params` |
| HTTP 头 | `request.headers`, `X-Forwarded-For`, `Referer`, `Host`, `Cookie` |
| URL 路径 | `<int:id>`, `{id}`, `req.params.id` |
| 文件上传 | `request.files`, `req.file`, `MultipartFile` |
| WebSocket | `ws.on('message')`, WebSocket 帧数据 |
| 数据库结果 | 查询返回值（二次注入场景） |
| 环境变量 | 来自不可信配置源时 |
| 外部 API 响应 | 第三方服务返回数据 |

**Sink 全量清单**：

| 危险类型 | Sink 示例 | 对应 CWE |
|----------|----------|---------|
| SQL 执行 | `execute()`, `raw()`, `createQuery()`, `$wpdb->query()` | CWE-89 |
| 命令执行 | `os.system()`, `exec.Command()`, `subprocess()`, `child_process.exec()` | CWE-78 |
| 文件操作 | `open()`, `readFile()`, `writeFile()`, `include()`, `require()` | CWE-22 |
| HTML 渲染 | `render_template_string()`, `innerHTML`, `v-html`, `dangerouslySetInnerHTML` | CWE-79 |
| HTTP 请求 | `requests.get(url)`, `fetch(url)`, `http.Get(url)` | CWE-918 |
| 反序列化 | `pickle.loads()`, `yaml.load()`, `ObjectInputStream`, `unserialize()` | CWE-502 |
| 代码执行 | `eval()`, `exec()`, `Function()`, `new Function()` | CWE-94 |
| 日志输出 | `logger.info()`, `console.log()` 含敏感数据 | CWE-532 |
| 响应输出 | `jsonify()`, `res.json()` 返回过多字段 | CWE-200 |
| 模板渲染 | `render_template_string(user_input)`, `Jinja2 sandbox escape` | CWE-1336 |

**追踪流程**：
1. 标记所有 Source 变量
2. 逐步追踪：变量赋值 → 函数传参 → 返回值 → 属性访问
3. 检查路径中是否经过**净化函数**（sanitizer）：
   - SQL: 参数化查询、ORM filter
   - XSS: HTML 转义、DOMPurify、模板自动转义
   - 命令: shlex.quote、列表参数
   - 路径: os.path.realpath + 前缀校验
   - URL: 白名单校验
4. Source → Sink 无净化 → **标记为漏洞**，记录完整数据流路径

### Phase 3: 系统检查（Systematic Review）

#### Step 4: OWASP Top 10 + CWE 系统检查

按**审计优先级**从高到低逐项检查。每个发现必须标注 CWE 编号。

---

##### 🔴 优先级 1：认证与授权（影响面最广）

**A01: 访问控制失效** — CWE-284 / CWE-639 / CWE-862 / CWE-863

**⚡ 四层访问控制验证方法论**（v4 新增 — 逐层递进检查）：

```
第 1 层：认证层 — 接口是否要求登录？未登录能否直接访问？
    ↓ 通过
第 2 层：角色层 — 已登录用户是否具有该接口的角色权限？普通用户能否调用管理接口？
    ↓ 通过
第 3 层：数据层 — 用户有接口权限后，接口参数是否做了归属校验？能否通过修改 ID/参数访问他人数据？
    ↓ 通过
第 3.5 层：关联对象层 — 修改资源时，关联引用的对象（收货地址ID、支付账户ID等）是否也做了归属校验？
    ↓ 通过
第 4 层：响应层 — 返回的数据是否最小化？是否包含了业务不需要的敏感字段（手机号、身份证、密码哈希等）？
```

**每个接口都必须逐层检查**，任何一层缺失即为漏洞。

| 检查项 | CWE | 关键问题 |
|--------|-----|--------|
| 未授权访问 | CWE-862 | 路由/视图是否有认证保护？（第 1 层） |
| 垂直越权 | CWE-863 | 管理接口是否有角色检查？（第 2 层） |
| 水平越权（IDOR） | CWE-639 | 资源查询是否过滤当前用户？（第 3 层） |
| 可预测资源标识符 | CWE-330/CWE-639 | 资源 ID 是否使用顺序数字/日期+序号等可遍历模式？（第 3 层）|
| 参数遍历攻击面 | CWE-639 | URL/Query 参数值是否可被枚举递增？（第 3 层） |
| 关联对象越权 | CWE-639 | 修改资源时关联的地址ID/账户ID等是否校验归属？（第 3.5 层）|
| 响应字段最小化 | CWE-200 | API 响应是否返回了不必要的敏感字段？（第 4 层） |
| 批量操作越权 | CWE-639/CWE-862 | 批量删除/修改/导出传入 ID 数组是否逐一校验归属？ |
| 隐藏接口暴露 | CWE-862 | 前端隐藏但后端未鉴权的接口？Swagger/JS 中泄露的 API？ |
| CORS 配置 | CWE-942 | 是否使用 `*` 允许所有来源？ |
| HTTP Method | — | 是否限制了允许的方法？ |
| 批量赋值 | CWE-915 | 是否限制了可更新字段？ |
| CSRF | CWE-352 | 状态变更操作是否有 CSRF 保护？ |

**A07: 认证失败** — CWE-287 / CWE-798 / CWE-306

| 检查项 | CWE | 关键问题 |
|--------|-----|---------|
| 弱密码策略 | CWE-521 | 密码长度 ≥ 12？复杂度要求？ |
| 会话管理 | CWE-613 | 登出时 Session 是否失效？ |
| JWT 安全 | CWE-347 | 是否验证签名？是否指定算法？是否检查过期？ |
| 暴力破解 | CWE-307 | 登录失败是否有次数限制？ |
| 凭据泄露 | CWE-532 | 密码/Token 是否出现在日志中？ |
| MFA | — | 关键操作是否支持双因素？ |
| OAuth | CWE-346 | PKCE？state 参数？redirect_uri 白名单？ |
| 账户枚举 | CWE-204 | 登录/注册/忘记密码是否返回不同响应？ |

**🆕 中间件/基础服务默认配置未授权检查**（v1.6 新增 — SOC 213 条工单验证）：

扫描 `docker-compose.yml`、`Dockerfile`、`k8s/*.yaml`、`application.yml`、`application.properties`、`nginx.conf`、`.env` 等基础设施配置文件，检查以下高频未授权风险：

| 检查项 | CWE | 配置文件/关键词 | 风险 |
|--------|-----|---------------|------|
| Docker API 未授权 | CWE-306 | `2375:2375`/`2376:2376` 端口暴露，无 TLS | 远程命令执行 |
| Elasticsearch 无认证 | CWE-306 | `9200:9200` 暴露，未配置 `xpack.security.enabled: true` | 数据泄露/删除 |
| Kibana 未授权 | CWE-306 | `5601:5601` 暴露，无 `xpack.security` | 日志数据暴露 |
| Redis 无密码 | CWE-306 | `6379:6379` 暴露，无 `requirepass` | 数据泄露/RCE |
| Spring Actuator 暴露 | CWE-215 | `management.endpoints.web.exposure.include=*` | 敏感信息/远程操作 |
| Nacos 默认 Token | CWE-798 | 默认 `nacos.core.auth.server.identity` 未修改 | 认证绕过 |
| rsync 无认证 | CWE-306 | `873:873` 暴露，`/etc/rsyncd.conf` 无 `auth users` | 文件窃取 |
| MongoDB 无认证 | CWE-306 | `27017:27017` 暴露，未启用 `--auth` | 数据库接管 |
| Swagger/API 文档暴露 | CWE-200 | 生产环境 `springdoc.swagger-ui.enabled=true` / Flask `/docs` | 接口信息泄露 |
| MinIO 默认凭据 | CWE-798 | `MINIO_ROOT_USER=minioadmin`/`MINIO_ROOT_PASSWORD=minioadmin` | 存储桶接管 |
| RabbitMQ 默认凭据 | CWE-798 | `RABBITMQ_DEFAULT_USER=guest`/`RABBITMQ_DEFAULT_PASS=guest` + `15672` 暴露 | 消息队列接管 |
| MySQL/PostgreSQL 弱密码 | CWE-521 | `MYSQL_ROOT_PASSWORD=123456`/`root`/`password` 等弱口令 | 数据库接管 |

**检查步骤**：
1. 搜索 `docker-compose.yml`、`Dockerfile`、`k8s/` 目录中的端口映射（`ports:` 配置）
2. 对每个暴露端口，检查对应服务是否有认证配置
3. 检查 `application.yml`/`.properties` 中 Actuator、Swagger、Nacos 等配置
4. 检查 `.env`/`docker-compose.yml` 中硬编码的默认密码

---

##### 🔴 优先级 2：注入攻击（直接利用）

**A03: 注入** — CWE-79 / CWE-89 / CWE-78 / CWE-94

| 注入类型 | CWE | 检测关键词/模式 |
|----------|-----|----------------|
| SQL 注入 | CWE-89 | `execute(f"`, `.format(`, `+ request.` 拼接 SQL |
| NoSQL 注入 | CWE-943 | MongoDB `$gt`/`$ne` 操作符注入 |
| ORM 注入 | CWE-89 | ORM raw/extra 方法中拼接字符串 |
| XSS（反射型） | CWE-79 | 用户输入直接拼接到 HTML 响应 |
| XSS（存储型） | CWE-79 | 用户输入存入数据库后未转义输出 |
| XSS（DOM 型） | CWE-79 | `innerHTML`、`document.write`、`v-html` |
| 命令注入 | CWE-78 | `os.system`、`subprocess(shell=True)` |
| 代码注入 | CWE-94 | `eval()`、`exec()`、`Function()` |
| 路径遍历 | CWE-22 | `../` 路径、未校验 `realpath` |
| LDAP 注入 | CWE-90 | LDAP 查询拼接用户输入 |
| XPath 注入 | CWE-643 | XPath 查询拼接用户输入 |
| SSTI 模板注入 | CWE-1336 | 模板字符串嵌入用户输入 |
| CSV 注入 | CWE-1236 | CSV 导出未过滤 `=+\-@` |
| Header 注入 | CWE-113 | 响应头含未过滤用户输入 |
| Host Header | CWE-644 | 信任 Host 头生成链接 |
| HTTP Request Smuggling | CWE-444 | Content-Length/Transfer-Encoding 不一致 |

**A10: SSRF** — CWE-918

- 用户可控 URL 发起请求？
- 白名单校验 scheme + domain？
- 阻止内网 IP（127.x、10.x、172.16-31.x、192.168.x、169.254.169.254）？
- 检查 DNS rebinding 和重定向链？

---

##### 🟠 优先级 3：数据安全

**A02: 加密机制失效** — CWE-327 / CWE-328 / CWE-259 / CWE-798

| 检查项 | CWE | 关键问题 |
|--------|-----|---------|
| 弱密码哈希 | CWE-328 | MD5/SHA1/SHA256 无盐存密码？ |
| ~~硬编码凭据~~ | ~~CWE-798~~ | ~~源代码中明文密钥/密码？~~ **【已排除】** |
| 弱传输 | CWE-319 | 未强制 HTTPS？HSTS 未启用？ |
| 弱随机数 | CWE-330 | `math/rand`、`random.randint` 用于安全场景？ |
| 弱加密算法 | CWE-327 | DES/RC4/ECB 模式？ |
| 证书验证禁用 | CWE-295 | `verify=False`？ |

**敏感信息泄露** — CWE-200 / CWE-209 / CWE-532

| 检查项 | CWE | 位置 |
|--------|-----|------|
| 错误信息暴露 | CWE-209 | 异常堆栈返回到客户端 |
| 日志记录敏感数据 | CWE-532 | 密码/Token 写入日志 |
| API 返回过多数据 | CWE-200 | 内部 ID/哈希/配置 |
| URL 中含敏感参数 | CWE-598 | API Key 在 query string |
| 前端暴露密钥 | CWE-200 | JS 代码含 API Key |
| 版本信息泄露 | CWE-200 | Server 头暴露版本 |
| 配置文件未忽略 | CWE-200 | .env 不在 .gitignore |

**🆕 部署产物与敏感文件泄露检查**（v1.6 新增 — SOC 34 条工单验证）：

扫描代码仓库和项目配置，检查以下可能在部署后暴露敏感文件的场景：

| 检查项 | CWE | 关键文件/路径 | 风险 |
|--------|-----|-------------|------|
| VCS 元数据泄露 | CWE-538 | `.svn/entries`、`.git/config`、`.hg/` 目录 | 源代码/历史泄露 |
| macOS 临时文件 | CWE-538 | `.DS_Store`（含目录结构信息） | 目录结构暴露 |
| 备份压缩包泄露 | CWE-538 | `*.tar.gz`、`*.bak`、`*.sql`、`*.dump`、`*~` 在 Web 可访问目录 | 源代码/数据泄露 |
| 前端 AK/SK 泄露 | CWE-200 | JS/HTML 中硬编码 `AccessKeyId`/`AccessKeySecret`/`AKID` | 云资源接管 |
| 目录列表启用 | CWE-548 | Nginx `autoindex on;` / Apache `Options +Indexes` | 文件遍历 |
| 编辑器临时文件 | CWE-538 | `.swp`、`.swo`、`~` 后缀文件 | 源代码泄露 |
| 配置文件暴露 | CWE-200 | `web.config`、`wp-config.php.bak`、`.env.production` | 凭据泄露 |
| CI/CD 配置泄露 | CWE-200 | `.github/workflows/` 中硬编码凭据或 secrets 未使用变量 | 凭据泄露 |
| GitLab/GitHub Token | CWE-200 | GraphQL info leak（`/api/graphql` introspection 暴露用户信息） | 信息泄露 |
| 上传目录可列表 | CWE-548 | `/uploads/`、`/static/uploads/` 无 index 且开启列表 | 文件遍历 |

**检查步骤**：
1. 检查 `.gitignore` 是否包含 `.env`、`*.pem`、`*.key`、`*.bak`、`.DS_Store`、`*.sql`
2. 搜索 Nginx/Apache 配置中的 `autoindex`、`Options +Indexes`
3. 搜索前端代码（`*.js`、`*.html`、`*.vue`、`*.tsx`）中的 AK/SK 模式：
   - 正则：`(AKID|AccessKey|aws_access_key|AKIA)[a-zA-Z0-9]{10,}`
4. 检查 CI/CD 配置文件中是否硬编码了密码/Token（而非使用 `${{ secrets.XXX }}`）
5. 检查 Web 服务器配置是否为静态资源目录关闭了目录列表

---

##### 🟡 优先级 4：设计与配置

**A04: 不安全设计** — CWE-840

| 检查项 | CWE | 关键问题 |
|--------|-----|---------|
| 速率限制缺失 | CWE-770 | 登录/API 无限流？ |
| 竞态条件 | CWE-362 | 余额双花？优惠券重复领取？重复提交订单？ |
| TOCTOU | CWE-367 | 检查与使用之间的时间窗口？ |
| 幂等性缺失 | CWE-362 | 写入接口是否有幂等键？重复提交能否产生重复记录？ |
| 文件上传 | CWE-434 | 类型/大小/内容校验？ |

**业务逻辑漏洞检查清单**（v5 新增 — 独立检查项）：

| 检查项 | CWE | 关键问题 |
|--------|-----|----------|
| 支付金额篡改 | CWE-20 | 前端传递的价格/金额参数是否被后端信任？是否从数据库重新读取？ |
| 负数/零值绕过 | CWE-20 | 数量、金额、积分等参数是否允许负数或零值？ |
| 优惠券/折扣滥用 | CWE-840 | 优惠码是否可重复使用？是否可叠加？是否校验适用条件？ |
| 支付回调伪造 | CWE-345 | 支付成功回调是否校验签名？是否校验金额一致性？ |
| 订单状态篡改 | CWE-840 | 能否跳过支付直接修改订单为已支付？是否有合法状态转换校验？ |
| 多步骤流程绕过 | CWE-840 | 审批/下单/注册等多步骤流程能否跳步？step 参数可否篡改？ |
| 流程重放攻击 | CWE-294 | 已完成流程的中间步骤请求能否被重放？ |
| 验证码不过期 | CWE-613 | 短信/邮件验证码是否有 TTL？超时是否失效？ |
| 验证码爆破 | CWE-307 | 验证码错误次数是否有限制？4-6 位纯数字可否暴力枚举？ |
| 验证码未绑定 | CWE-345 | 验证码与手机号/邮箱是否绑定校验？能否先获取验证码再替换接收方？ |
| 验证码泄露 | CWE-200 | 验证码是否出现在 API 响应体/日志中？ |
| 时间维度遍历 | CWE-639 | 修改时间范围参数能否导出他人/全量数据？ |

**A05: 安全配置错误** — CWE-16

| 检查项 | 风险 |
|--------|------|
| DEBUG 模式 | 生产环境暴露内部信息 |
| 默认凭据 | admin/admin123 等 |
| 安全头缺失 | CSP、X-Frame-Options、HSTS、X-Content-Type-Options |
| Cookie 属性 | HttpOnly / Secure / SameSite 未设置 |
| CORS 过宽 | `Access-Control-Allow-Origin: *` |

**A08: 数据完整性失败** — CWE-502

- 不安全反序列化（pickle/yaml.load/ObjectInputStream）
- 文件上传 MIME 校验（不仅仅扩展名，需检查 magic bytes）
- SRI（Subresource Integrity）外部脚本校验
- CI/CD 流程完整性

---

##### 🔵 优先级 5：组件与监控

**A06: 脆弱组件** — CWE-1395

- CVSS ≥ 7.0 的已知 CVE（检查 requirements.txt/go.mod/package.json/pom.xml）
- lock 文件是否存在（版本确定性）
- 已弃用/不维护的库
- Typosquatting 风险（包名相似的恶意包）

**🆕 高频组件 CVE 模式库**（v1.6 新增 — SOC 79 条工单验证）：

除了通用依赖版本检查外，重点识别以下在 SOC 实战中高频出现的组件漏洞特征。审计时主动搜索项目中是否使用了这些组件并检查版本：

| 组件 | 高危版本/特征 | CVE | 风险 | 检查位置 |
|------|-------------|-----|------|---------|
| **Apache ActiveMQ** | < 5.15.16 / < 5.16.7 / < 5.17.6 | CVE-2023-46604 | OpenWire 反序列化 RCE | `pom.xml`/`docker-compose.yml` 中 `activemq` |
| **Harbor** | < 2.7.3 / < 2.8.3 | CVE-2022-46463 | 未授权访问镜像仓库 | `docker-compose.yml` 中 `harbor`，检查版本 |
| **Apache Flink** | < 1.11.3 | CVE-2020-17518/17519 | 文件上传 RCE / 文件读取 | `pom.xml`/`flink-conf.yaml` |
| **Nacos** | < 2.2.1 | CVE-2021-29441 等 | 默认 Token 认证绕过 | `application.yml` 中 `nacos` 配置 |
| **Log4j** | < 2.17.1 | CVE-2021-44228 (Log4Shell) | JNDI 注入 RCE | `pom.xml`/`log4j2.xml`/`gradle` 中 `log4j-core` |
| **Apache Struts 2** | OGNL 表达式漏洞 | CVE-2017-5638 等 | 远程代码执行 | `pom.xml` 中 `struts2-core` |
| **Spring Framework** | < 5.3.18 / < 5.2.20 | CVE-2022-22965 (Spring4Shell) | RCE | `pom.xml`/`gradle` 中 `spring-webmvc` |
| **Spring Cloud Gateway** | < 3.1.1 | CVE-2022-22947 | SpEL 注入 RCE | `pom.xml` 中 `spring-cloud-gateway` |
| **Fastjson** | < 1.2.83 | 多个反序列化 CVE | 任意代码执行 | `pom.xml`/`gradle` 中 `fastjson` |
| **Jackson** | 未开启 `DefaultTyping` 限制 | CVE-2019-14379 等 | 反序列化 RCE | `ObjectMapper` 配置 |
| **OpenSSL** | < 3.0.7 | CVE-2022-3602/3786 | 缓冲区溢出 | `Dockerfile` 中基础镜像版本 |
| **SaltStack** | < 3003.4 | CVE-2021-25282 | 任意文件写入 | `docker-compose.yml` 中 `salt` |
| **Nancy 框架** | 未维护 (.NET) | — | 已知多个漏洞 | `.csproj` 中 `Nancy` |
| **lodash** | < 4.17.21 | CVE-2021-23337 | Prototype Pollution → RCE | `package.json` 中 `lodash` |
| **Pillow** | < 10.0.1 | CVE-2023-44271 等 | 图像处理 DoS/RCE | `requirements.txt` 中 `Pillow` |
| **n8n** | Webhook 端点 | CVE-2026-21858 | 远程代码执行 | `docker-compose.yml` 中 `n8nio/n8n` |

**检查步骤**：
1. 扫描所有依赖声明文件（`pom.xml`/`build.gradle`/`requirements.txt`/`package.json`/`go.mod`/`Gemfile`/`*.csproj`）
2. 对照上表高频组件列表，检查是否存在且版本是否在受影响范围内
3. 扫描 `docker-compose.yml` / `Dockerfile` 中的镜像名和版本标签
4. 对命中项标记 CWE-1395，引用对应 CVE 编号

**A09: 日志与监控不足** — CWE-778

- 敏感操作有审计日志？
- 日志中无敏感数据？
- 结构化日志格式（便于 SIEM）？
- 安全事件告警机制？

---

##### 🔵 扩展检查项

**API 安全（OWASP API Top 10）**：
- BOLA / BFLA / Mass Assignment / 过度数据暴露 / 资源限制

**GraphQL 安全**：
- 查询深度限制 / Introspection 禁用 / 字段级权限 / 批量查询限制

**WebSocket 安全**：
- Origin 验证 / 认证 Token 校验 / 消息输入验证

**客户端安全**：
- dangerouslySetInnerHTML / v-html 滥用
- localStorage 存储敏感数据
- iframe sandbox / postMessage origin 验证 / Clickjacking

**竞态条件（CWE-362）**：
- 数据库事务 + 行级锁 / 原子操作 / 乐观锁

**批量操作越权**（v5 新增）：
- 批量删除/修改/导出接口传入 ID 数组时，是否逐一校验每个 ID 的归属？
- 是否只校验第一个 ID 而信任其余？攻击者在合法 ID 中混入他人 ID
- 批量导出是否有数量限制和权限范围校验？

**隐藏接口暴露**（v5 新增）：
- 前端菜单/按钮隐藏 ≠ 后端接口不可访问，需确认后端独立鉴权
- Swagger/OpenAPI 文档是否在生产环境暴露了未授权接口？
- 前端 JS Bundle 中是否包含未在页面展示的 API 路径？
- 检查路由注册文件，找出无认证中间件保护的非公开接口

**幂等性与重复提交**（v5 新增）：
- 创建类接口（订单/申请/领取）是否支持 Idempotency-Key？
- 表单提交是否有前端防重和后端去重双重保护？
- 奖励/优惠券领取接口是否有唯一约束防止重复领取？

**🆕 文件操作安全深度审计**（v1.6 新增 — SOC 33 条工单验证）：

在已有路径遍历（CWE-22）和文件上传（CWE-434）检查基础上，增加以下高频实战场景：

| 检查项 | CWE | 关键问题 |
|--------|-----|---------|
| 导出/模板文件路径注入 | CWE-22 | 文件导出/模板下载接口的 `filename`/`path`/`template` 参数是否可被路径遍历？是否做了 `realpath` + 前缀校验？ |
| OSS 对象存储配置不当 | CWE-284 | OSS/S3 Bucket 是否配置了公开读写？上传接口是否校验文件类型和存储路径？`presigned URL` 是否限制了过期时间？ |
| 文件下载越权 | CWE-639 | 文件下载接口（`/download/<file_id>`）是否校验文件归属？是否可通过遍历 ID 下载他人文件？ |
| 上传文件名注入 | CWE-22 | 上传时是否信任原始文件名？是否可通过 `../../etc/crontab` 等文件名写入任意路径？ |
| 临时文件清理缺失 | CWE-459 | 生成的临时文件/导出文件是否有定期清理？是否可被其他用户访问？ |
| 文件内容校验不足 | CWE-434 | 是否只校验扩展名而不检查 magic bytes？`.jpg` 后缀的 PHP/JSP webshell？ |
| SaltStack/Ansible 文件写入 | CWE-22 | 配置管理工具的文件操作模块参数是否来自不可信输入？ |
| 企业应用文件读取接口 | CWE-22 | 业务系统文件读取/导出接口的路径参数是否可遍历？（SOC 高频漏洞） |

**检查步骤**：
1. 搜索所有文件读写操作（`open()`/`readFile()`/`writeFile()`/`send_file()`/`FileResponse()`）
2. 检查文件路径参数是否来自用户输入，是否经过了 `os.path.realpath()` + 前缀白名单校验
3. 检查 OSS/S3 SDK 调用中的 Bucket ACL 配置和 presigned URL 设置
4. 检查文件下载接口是否有归属校验（`WHERE user_id = current_user.id`）
5. 检查上传功能是否对文件名做了清洗（移除路径分隔符，使用 UUID 重命名）

### Phase 4: 验证与报告（Verification & Reporting）

#### Step 5: 漏洞分级与 CVSS 评估

| 级别 | 标准 | CVSS 范围 | 徽章 |
|------|------|-----------|------|
| 严重 | 远程未认证直接利用，系统完全控制 | 9.0-10.0 | 🟣 |
| 高危 | 直接利用导致数据泄露、大规模越权 | 7.0-8.9 | 🔴 |
| 中危 | 需一定条件利用，影响有限 | 4.0-6.9 | 🟠 |
| 低危 | 配置不当、信息泄露，单独难直接利用 | 0.1-3.9 | 🔵 |
| 信息 | 最佳实践建议 | 0.0 | ⚪ |

**高危及以上必须提供 CVSS 3.1 向量**（参考 `references/cwe_mapping.md` 速查表）。

#### Step 6: 自我验证与误报过滤（关键步骤）

在输出报告前，对每个发现执行五步验证：

1. **证据核实**：是否有确切文件路径 + 行号 + 代码片段？
2. **可达性分析**：该代码路径是否真的可从外部触达？是否有前置中间件/过滤器？
3. **上下文排除**：
   - 是否在测试代码/示例代码中？（`test_*.py`、`*_test.go`、`*.spec.ts`）
   - 是否被注释掉？
   - 是否有条件编译/环境判断保护？
4. **反思挑战**："这个发现为什么可能是误报？"
   - 找到合理理由 → 降级或移除
   - 无法反驳 → 确认为真阳性
5. **去重合并**：同一根因的多个表象 → 合并为一个发现

#### Step 7: 正面安全发现记录

审计不只是找问题。记录项目已实施的安全最佳实践：

- ✅ 使用了 bcrypt/argon2 存储密码
- ✅ 配置了 CSP、HSTS 等安全头
- ✅ 实施了速率限制
- ✅ 使用了参数化查询/ORM
- ✅ 敏感配置通过环境变量管理
- ✅ 有审计日志记录
- ✅ 依赖有 lock 文件且定期更新

**作用**：帮助团队了解哪些实践应继续保持，避免修复时破坏已有安全机制。

#### Step 8: 生成 HTML 报告

**文件名**：`log/security_audit_OWASP_<YYYYMMDDHHMMSS>.html`

使用 `references/report_template.md` 模板，报告**必须包含**以下章节：

1. **报告头** — 项目名、审计时间、Skill 版本、技术栈、审计模式
2. **统计面板** — 严重/高/中/低/信息 数量徽章
3. **威胁建模摘要** — STRIDE 分析结论（折叠面板）
4. **漏洞发现列表** — 每个发现包含：
   - 严重级别 + 标题
   - CWE 编号 + OWASP 分类
   - CVSS 3.1 评分和向量（高危以上）
   - 文件路径 + 行号
   - 数据流路径（Source → ... → Sink）
   - 问题说明（中文，清晰描述危害和攻击场景）
   - 漏洞代码片段（高亮关键行）
   - 修复建议代码
   - 预防措施（框架特定推荐）
5. **正面发现列表** — 已实施的安全实践
6. **修复优先级表** — 按严重性排序的行动清单
7. **合规性参考** — 对应的 PCI-DSS / SOC2 / ISO27001 控制项
8. **报告页脚** — 生成工具、OWASP 版本

#### Step 9: 安全门控检查清单（新增）

报告生成后，对照安全门控清单做最终确认：

```
安全门控检查（审计质量保证）：
□ 所有路由/端点已被扫描覆盖
□ OWASP Top 10 每个分类都已检查（无遗漏）
□ 每个发现都有确切文件路径和行号
□ 高危以上发现都有 CVSS 评分
□ 每个发现都有可执行的修复建议
□ 已执行自我验证（无明显误报）
□ 正面发现已记录
□ 报告 HTML 已验证可正常打开
```

若有未通过项，补充完善后再输出。

#### Step 10: 展示报告

在浏览器中打开 `log/security_audit_OWASP_<datetime>.html`。

#### Step 11: 修复引导提示

```
✅ 审计完成！

📊 扫描摘要：
  - 技术栈：{{语言}} / {{框架}} / {{数据库}}
  - 扫描路由/接口：X 个
  - 发现安全问题：N 个
  - 🟣 严重：S 个  🔴 高危：A 个  🟠 中危：B 个  🔵 低危：C 个  ⚪ 信息：D 个
  
🛡️ 正面发现：P 个安全最佳实践已实施
🔍 威胁建模：已完成 STRIDE 六维度分析

📄 完整报告：log/security_audit_OWASP_<datetime>.html

如需自动修复，请回复 **修复** 开始修复流程。
如需针对特定漏洞类型深入分析，请回复 **深入 <类型>**。
```

---

## 修复流程

当用户回复"修复"时执行。

### 修复排序

严重 → 高危 → 中危 → 低危，同级按出现顺序。

### 修复策略

| 情形 | 处理方式 |
|------|----------|
| 低危 / 信息 | 直接修复，展示 diff |
| 中危 | 直接修复，展示 diff，说明影响范围 |
| 高危 / 严重 | 先展示修复方案，等用户 **确认** |
| 涉及架构变更 | 说明受影响文件、迁移需求，用户二次确认 |
| 涉及密钥/密码 | 生成强随机值（secrets.token_urlsafe(32)），提醒替换 |
| 涉及数据库变更 | 提供迁移脚本建议，提醒备份 |

### 高危确认提示

```
⚠️ 高危修复确认 [N/总数]

漏洞：<标题>
CWE：<CWE-XXX: 名称>
CVSS：<评分> (<向量>)
文件：<路径>  行号：<行号>
修改内容：<说明>
影响范围：<功能/接口>
测试建议：<修复后需验证的用例>

回复 **确认** / **跳过** / **全部确认**
```

### 修复完成后

```
✅ 修复完成！

📊 修复摘要：
  已修复：X 个 | 已跳过：Y 个

📋 后续建议：
1. 运行测试套件确认功能正常
2. 对跳过项进行人工审查
3. 部署前再次执行审计验证修复效果
4. 考虑集成 CI/CD 安全扫描：
   - Python: bandit, safety
   - JavaScript: npm audit, eslint-plugin-security
   - Go: gosec, govulncheck
   - Java: SpotBugs + FindSecBugs, OWASP Dependency-Check
   - 通用: Semgrep, CodeQL, Snyk
5. 设置 pre-commit hook 进行增量安全检查
```

---

## 框架特定安全建议速查

修复建议中根据检测到的框架给出特定推荐：

| 框架 | 推荐安全库/配置 |
|------|----------------|
| **Python/Flask** | `flask-login`, `flask-limiter`, `flask-talisman`(CSP/HSTS), `flask-wtf`(CSRF), `bleach`(XSS), `flask-seasurf` |
| **Python/Django** | Django ORM, `CsrfViewMiddleware`, `ALLOWED_HOSTS`, `django-axes`(暴力破解), `django-csp`, `SECRET_KEY` 从环境变量读取 |
| **Python/FastAPI** | Pydantic 验证, `slowapi`(限流), OAuth2+PKCE, `CORSMiddleware` 配白名单, `python-jose`(JWT) |
| **Go/Gin** | `gin-contrib/cors`(白名单), JWT middleware, `database/sql` prepared statements, `crypto/rand`, `gorilla/csrf` |
| **Go/Echo** | `echo.middleware.CORS`, `echo.middleware.CSRF`, `echo.middleware.RateLimiter` |
| **Java/Spring** | Spring Security, `@PreAuthorize`, CSRF protection, `BCryptPasswordEncoder`, `@Valid`, Security Headers |
| **Node/Express** | `helmet`(安全头), `express-rate-limit`, `express-validator`, `bcrypt`, `csurf`, `cors`(白名单) |
| **Node/Nest** | `@nestjs/throttler`, `class-validator`, `@nestjs/passport`, Helmet integration |
| **React** | 避免 `dangerouslySetInnerHTML`, `DOMPurify`, SRI for CDN, `httpOnly` cookies |
| **Vue** | 避免 `v-html`, `vue-sanitize`, `Content-Security-Policy` |
| **PHP/Laravel** | Eloquent ORM, CSRF middleware, `bcrypt`/`argon2`, Rate Limiting, `htmlspecialchars` |

---

## 排除项（不纳入审计报告的问题类别）

以下类别的问题**不作为漏洞报告**，审计时直接跳过：

| 排除类别 | 说明 | 理由 |
|----------|------|------|
| **硬编码凭据/密码** | 配置文件中的数据库密码、Redis 密码、API Key、SecretKey 等硬编码明文凭据 | 属于配置管理范畴，由运维/DevOps 统一治理，不在代码审计漏洞报告中重复体现 |
| **高权限数据库账户** | 使用 root、system、admin、sa 等高权限账户连接数据库 | 属于数据库权限管理范畴，由 DBA 统一管控 |
| **配置文件未加密** | .properties/.yml/.env 中密码明文存储 | 同硬编码凭据，运维治理 |
| **SSO/认证开关关闭** | apiCheck=false、clientSignCheck=false 等认证开关配置 | 属于部署配置范畴，非代码逻辑漏洞 |

> **注意**：上述排除项仅限于「凭据/账户/配置类」问题。如果代码逻辑中存在凭据通过 API 响应泄露给前端用户、日志中打印密码等**动态泄露**问题，仍然需要报告。

---

## 注意事项（审计纪律）

1. **有据可查**：每个发现必须有具体文件路径和行号，绝不猜测。
2. **不造假**：未发现的漏洞类别明确标注"未发现"，不虚报。
3. **不破坏**：修复前确认不会破坏现有业务逻辑，必要时先运行测试。
4. **不过度**：只修复报告中列出的漏洞，不顺手重构不相关代码。
5. **上下文优先**：先理解威胁模型和业务场景，再判断风险等级。
6. **误报控制**：宁可漏报一个低危，不可虚报一个高危。
7. **组件漏洞**：仅报告 CVSS ≥ 7.0 的已知 CVE，提供升级建议。
8. **增量感知**：增量模式下仅审查变更代码，但需考虑变更对已有安全机制的影响。
9. **排除项遵守**：严格遵守上述「排除项」列表，不将排除类别的问题纳入漏洞报告。
