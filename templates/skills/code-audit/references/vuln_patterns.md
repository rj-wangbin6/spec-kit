# 各语言常见漏洞模式速查

## Python / Flask / Django

### 越权漏洞模式

```python
# 模式1: 无认证路由
@app.route('/api/data')        # ← 无 @login_required
def get_data():
    return Data.query.all()    # 任何人可访问

# 模式2: IDOR（仅凭 ID 查询）
record = Model.query.get(id)                          # ← 无 user_id 过滤
record = Model.query.filter_by(id=id).first()         # ← 同上

# 模式3: 管理员接口无角色检查
@app.route('/admin/delete/<int:id>')
@login_required                # ← 只验证登录，无角色检查
def admin_delete(id):
    ...
```

### 注入漏洞模式

```python
# SQL 注入
db.execute("SELECT * FROM t WHERE name='" + name + "'")
db.execute(f"DELETE FROM t WHERE id={user_id}")

# 命令注入  
os.system("ffmpeg -i " + filename)
subprocess.call("ls " + path, shell=True)   # shell=True 且拼接字符串

# 路径遍历
open(base_dir + '/' + user_filename)        # 缺少 os.path.realpath 校验
```

### 敏感信息模式

```python
# 硬编码密钥
SECRET_KEY = "mysecret123"
DATABASE_URL = "postgresql://user:password123@localhost/db"
API_KEY = "sk-abc123def456"

# 弱密码存储
hashlib.md5(password.encode()).hexdigest()
hashlib.sha256(password).hexdigest()        # 未加盐

# 日志泄露
logger.info(f"Login attempt: {username}/{password}")
print(f"Request body: {request.json}")
```

### 配置错误模式

```python
app.run(debug=True)             # 生产环境 DEBUG
app.config['TESTING'] = True    # 测试模式开
CORS(app)                       # 无参数 = 允许所有来源
```

---

## Go / Gin / net/http

### 越权漏洞模式

```go
// 模式1: 路由组未挂载认证中间件
r.GET("/api/admin/users", adminHandler)  // ← 无中间件

// 模式2: IDOR
var record Record
db.First(&record, id)                   // ← 无用户 ID 过滤
db.Where("id = ?", id).First(&record)   // ← 同上

// 模式3: 任务/资源无归属校验
task := tasks[taskID]                   // ← 全局 map，无 owner 校验
```

### 注入模式

```go
// SQL 注入
db.Exec("SELECT * FROM users WHERE name = '" + name + "'")
db.Raw(fmt.Sprintf("DELETE FROM records WHERE id=%d", id))  // fmt.Sprintf 拼接

// 命令注入
exec.Command("sh", "-c", "convert " + filename)  // 拼接字符串
```

### 敏感信息模式

```go
// 硬编码密钥
const jwtSecret = "hardcoded_secret_key"
db, _ := sql.Open("sqlite3", "user:password@tcp(host)/db")

// 弱随机
token := fmt.Sprintf("%d", rand.Int())  // math/rand 非密码学安全
```

---

## JavaScript / TypeScript / Node.js / Express

### 越权漏洞模式

```javascript
// 模式1: 路由无认证
app.get('/api/admin/stats', (req, res) => { ... })  // 无 authMiddleware

// 模式2: IDOR
const record = await Model.findById(req.params.id)  // 无 userId 过滤

// 模式3: JWT 不验证
jwt.verify(token, null)                              // 跳过签名验证
jwt.decode(token)                                    // 只解码，不验证
```

### 注入模式

```javascript
// SQL 注入（手写 SQL）
db.query(`SELECT * FROM users WHERE name='${name}'`)

// NoSQL 注入（MongoDB）
User.findOne({ username: req.body.username })       // 若 username 是 {$gt: ''} 可绕过密码

// XSS
res.send(`<div>${userInput}</div>`)                 // 直接拼接 HTML
element.innerHTML = data                            // 客户端 DOM 操作
```

### Prototype Pollution

```javascript
// 危险：合并用户输入到对象
Object.assign(target, JSON.parse(userInput))        // 若含 __proto__ 可污染
_.merge(obj, userInput)                             // lodash < 4.17.21
```

---

## Java / Spring Boot

### 越权漏洞模式

```java
// 模式1: 无权限注解
@GetMapping("/admin/users")
public List<User> getUsers() { ... }  // 缺 @PreAuthorize

// 模式2: IDOR
Optional<Order> order = orderRepo.findById(id);  // 无 userId 过滤

// Spring Security 配置漏洞
http.authorizeRequests()
    .antMatchers("/admin/**").permitAll()  // ← 管理接口全开放
```

### 注入模式

```java
// SQL 注入（JDBC 字符串拼接）
String sql = "SELECT * FROM users WHERE name='" + name + "'";
stmt.executeQuery(sql);

// JPQL 注入
entityManager.createQuery("FROM User WHERE name='" + name + "'");

// SpEL 注入
@PreAuthorize("hasRole('" + roleName + "')")  // roleName 来自用户输入
```

### 反序列化

```java
// 危险: 反序列化不可信数据
ObjectInputStream ois = new ObjectInputStream(userInputStream);
Object obj = ois.readObject();
```

---

## PHP

### 文件包含/路径遍历

```php
// ❌ 危险
include($_GET['page'] . '.php');           // 文件包含
readfile('/uploads/' . $_GET['file']);     // 路径遍历

// ❌ SQL 注入
$sql = "SELECT * FROM users WHERE id=" . $_GET['id'];
```

---

## Rust

### 不安全代码模式

```rust
// 模式1: 不安全内存操作
unsafe { *ptr = value; }                              // ← 不安全指针写入
unsafe { std::slice::from_raw_parts(ptr, len) }       // ← 不受限的原始指针切片

// 模式2: SQL 注入（raw SQL）
sqlx::query(&format!("SELECT * FROM users WHERE name='{}'", name))  // ← 拼接
diesel::sql_query(format!("DELETE FROM t WHERE id={}", id))          // ← 拼接

// 模式3: 命令注入
std::process::Command::new("sh").arg("-c").arg(format!("ls {}", user_input))  // ← 拼接

// 模式4: 路径遍历
let path = PathBuf::from(base).join(user_input);     // ← 未 canonicalize 校验
std::fs::read_to_string(path)?;
```

### 反序列化 / 依赖风险

```rust
// 模式1: 不安全反序列化
serde_json::from_str::<Value>(&untrusted_input)?;     // ← 无大小/深度限制
bincode::deserialize(&untrusted_bytes)?;               // ← 不可信来源

// 模式2: unwrap 导致 DoS
let val = some_option.unwrap();                        // ← 可触发 panic
let val = result.unwrap();                             // ← 生产代码应用 ? 或 match
```

---

## C# / ASP.NET

### 注入漏洞模式

```csharp
// SQL 注入
var sql = "SELECT * FROM Users WHERE Name='" + name + "'";
cmd.CommandText = $"DELETE FROM Records WHERE Id={id}";  // ← 字符串内插拼接

// 命令注入
Process.Start("cmd.exe", "/c " + userInput);

// 路径遍历
var path = Path.Combine(basePath, userInput);            // ← 未 GetFullPath 校验
System.IO.File.ReadAllText(path);

// LDAP 注入
var filter = $"(uid={userInput})";                       // ← 未转义特殊字符
```

### 越权与配置模式

```csharp
// 模式1: 缺少授权属性
[HttpGet("/admin/users")]
public IActionResult GetUsers() { ... }                  // ← 缺 [Authorize(Roles="Admin")]

// 模式2: IDOR
var order = _db.Orders.Find(id);                         // ← 无 UserId 过滤

// 模式3: 不安全反序列化
BinaryFormatter bf = new BinaryFormatter();
var obj = bf.Deserialize(stream);                        // ← 已知 RCE 风险

// 模式4: DEBUG 信息泄露
app.UseDeveloperExceptionPage();                         // ← 生产环境泄露堆栈
```

---

## Ruby / Rails

### 注入漏洞模式

```ruby
# SQL 注入
User.where("name = '#{params[:name]}'")                  # ← 字符串插值
User.find_by_sql("SELECT * FROM users WHERE id=#{id}")   # ← 拼接

# 命令注入
system("ls " + params[:dir])                             # ← 拼接系统命令
`convert #{filename}`                                    # ← 反引号命令执行

# 路径遍历
send_file(Rails.root.join('uploads', params[:file]))     # ← 未校验路径
File.read(params[:path])                                 # ← 直接读任意文件
```

### 越权与配置模式

```ruby
# 模式1: 缺少认证
class AdminController < ApplicationController
  # ← 缺少 before_action :authenticate_admin!
  def index; end
end

# 模式2: IDOR（仅凭 ID 查询）
@order = Order.find(params[:id])                         # ← 无 current_user 过滤

# 模式3: 批量赋值
User.new(params[:user].permit!)                          # ← permit! 允许所有字段
User.update(params.require(:user).permit(:role))         # ← role 不应可修改

# 模式4: 不安全反序列化
Marshal.load(cookie_data)                                # ← 不可信数据反序列化
YAML.load(user_input)                                    # ← 应使用 YAML.safe_load
```

---

## 通用硬编码密钥正则（用于所有语言）

```regex
# 常见密钥模式
(password|passwd|secret|api_key|apikey|token|access_key|private_key|auth_key)\s*[=:]\s*["'][^"']{8,}["']

# AWS / 云凭据
AKIA[0-9A-Z]{16}
sk-[a-zA-Z0-9]{32,}

# 私钥文件内容
-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----
```

---

## 漏洞严重性速查

| 漏洞类型 | 典型严重级别 | 关键判断因素 |
|----------|-------------|-------------|
| 垂直越权（管理后台无认证） | 高危 | 是否直接可利用 |
| SQL 注入（带回显） | 高危 | 数据是否可直接读取 |
| 命令注入 | 高危 | 系统命令执行 |
| 反序列化任意代码执行 | 高危 | 远程代码执行 |
| 水平越权（IDOR） | 中危 → 高危 | 数据敏感性和影响范围 |
| 存储型 XSS | 中危 | 影响其他用户 |
| 硬编码密钥 | 中危 | 密钥是否在用 |
| 反射型 XSS | 中危 | 需社工利用 |
| API Key URL 传递 | 低危 | 需日志访问权限 |
| DEBUG 模式 | 低危 | 信息泄露 |
| 弱密码存储（MD5） | 中危 | 需获取数据库 |
| 缺少速率限制 | 低危 | 需结合具体场景 |
| Docker API 未授权 | 严重 | 远程命令执行（v1.6 新增） |
| ES/Redis/MongoDB 无认证 | 高危 | 数据泄露/RCE（v1.6 新增） |
| Spring Actuator 暴露 | 中危 → 高危 | 可获取 heapdump/env（v1.6 新增） |
| Nacos 默认 Token | 高危 | 认证绕过（v1.6 新增） |
| 前端 AK/SK 泄露 | 严重 | 云资源接管（v1.6 新增） |
| .svn/.git 暴露 | 中危 | 源码泄露（v1.6 新增） |
| 备份文件暴露 | 中危 | 源码/数据泄露（v1.6 新增） |
| OSS Bucket 公开读写 | 高危 | 存储桶接管（v1.6 新增） |
| 文件下载越权 | 中危 → 高危 | 数据敏感性（v1.6 新增） |
| 高危组件 CVE | 高危 → 严重 | ActiveMQ/Log4j/Fastjson 等（v1.6 新增） |

---

## 🆕 基础设施配置漏洞模式（v1.6 新增）

### Docker / K8s / docker-compose.yml

```yaml
# 模式1: 敏感端口直接暴露
ports:
  - "2375:2375"   # ← Docker API 未授权
  - "9200:9200"   # ← ES 无认证
  - "6379:6379"   # ← Redis 无密码
  - "27017:27017" # ← MongoDB 无认证
  - "15672:15672" # ← RabbitMQ 管理界面默认凭据

# 模式2: 默认/弱凭据
environment:
  - MYSQL_ROOT_PASSWORD=123456       # ← 弱密码
  - MINIO_ROOT_PASSWORD=minioadmin   # ← 默认凭据
  - RABBITMQ_DEFAULT_PASS=guest      # ← 默认凭据
  - POSTGRES_PASSWORD=postgres       # ← 弱密码
```

### Spring Boot / Java 配置

```yaml
# 模式1: Actuator 全暴露
management.endpoints.web.exposure.include: "*"     # ← 暴露 /env /heapdump /shutdown

# 模式2: Swagger 生产环境未关闭
springdoc.swagger-ui.enabled: true                 # ← API 文档暴露
springdoc.api-docs.enabled: true

# 模式3: Nacos 默认配置
nacos.core.auth.enabled: false                     # ← 认证未启用
nacos.core.auth.server.identity.value: security    # ← 默认 identity
```

### Nginx / Apache 配置

```nginx
# 模式1: 目录列表
location /uploads/ { autoindex on; }               # ← 文件遍历

# 模式2: 版本信息暴露
server_tokens on;                                  # ← 暴露 Nginx 版本
```

### 文件操作漏洞模式

```python
# 模式1: 导出/下载路径未校验
filepath = os.path.join(base_dir, request.args.get('file'))  # ← 路径遍历
send_file(filepath)                                            # 无 realpath 校验

# 模式2: OSS 公开配置
s3.put_bucket_acl(Bucket=bucket, ACL='public-read-write')    # ← 公开读写
presigned_url(ExpiresIn=86400*365)                            # ← 过期时间过长

# 模式3: 文件名未清洗
f.save(os.path.join('/uploads', f.filename))                  # ← 原始文件名含路径

# 模式4: 仅扩展名校验
if filename.endswith('.jpg'):                                  # ← 未检查 magic bytes
    save(file)
```

### 前端凭据泄露模式

```javascript
// 模式1: 硬编码云凭据
const accessKeyId = 'LTAI5txxxxxxxxxx'          // ← AK 硬编码
const accessKeySecret = 'xxxxxxxxxxxxxx'        // ← SK 硬编码
const AWS_ACCESS_KEY = 'AKIAIOSFODNN7EXAMPLE'   // ← AWS AK

// 模式2: API Key 硬编码
const API_KEY = 'sk-proj-xxxxxxxxxxxx'          // ← OpenAI Key
const STRIPE_KEY = 'sk_live_xxxxxxxxx'          // ← 支付密钥
```
