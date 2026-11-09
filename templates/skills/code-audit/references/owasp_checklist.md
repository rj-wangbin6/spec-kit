# OWASP Top 10 详细审计检查清单

## A01: 访问控制失效（Broken Access Control）

### 1.0 四层访问控制验证方法论（v4 新增）

对每个 API 接口/路由，必须按四层顺序逐层验证，任何一层缺失即为漏洞：

```
第 1 层：认证层（Authentication）
  → 接口是否要求登录？未登录状态能否直接访问？
  → 对应漏洞：未授权访问（CWE-862）

第 2 层：角色层（Role-based Authorization）
  → 已登录用户是否具有该接口的角色权限？
  → 普通用户能否调用管理员/审批人/配置管理接口？
  → 对应漏洞：垂直越权（CWE-863）

第 3 层：数据层（Data-level Authorization / Parameter Authorization）
  → 接口参数（ID、编号、用户名等）是否做了归属校验？
  → 能否通过修改/枚举参数值访问他人数据？
  → 资源标识符是否可预测（顺序数字、日期+序号）？
  → 对应漏洞：水平越权/IDOR（CWE-639）

第 4 层：响应层（Response Minimization）
  → 接口返回的数据是否遵循最小化原则？
  → 是否返回了业务不需要的敏感字段（手机号、身份证、密码哈希、内部ID）？
  → 搜索/查询接口是否可获取全量用户信息？
  → 对应漏洞：过度数据暴露（CWE-200）
```

**审计执行**：对每个被审计接口，填写如下检查表：

| 接口路径 | 第1层-认证 | 第2层-角色 | 第3层-数据归属 | 第4层-响应最小化 | 结论 |
|----------|:----------:|:----------:|:--------------:|:----------------:|------|
| `/api/xxx` | ✅/❌ | ✅/❌/N/A | ✅/❌ | ✅/❌ | 安全/漏洞 |

### 1.1 路由认证检查

| 语言/框架 | 认证装饰器/方法 | 检查要点 |
|-----------|----------------|----------|
| Python/Flask | `@login_required`、`@jwt_required()` | 公开接口是否有意省略认证？ |
| Python/Django | `@login_required`、`LoginRequiredMixin` | Class-based view 是否混入了权限类？ |
| Go/Gin | 中间件链 `authMiddleware`、`JWTMiddleware` | 路由组是否应用了认证中间件？ |
| Java/Spring | `@PreAuthorize`、`@Secured`、`SecurityConfig` | 每个 endpoint 是否有 `hasRole`/`hasAuthority`？ |
| Node/Express | `passport.authenticate()`、JWT 中间件 | 路由是否挂载了 auth 中间件？ |

**检查步骤**：
1. 收集所有路由注册代码（Flask: `@app.route`、Gin: `r.GET/POST`、Spring: `@GetMapping`）
2. 逐条确认是否有认证保护
3. 特别关注：文件下载、报告查看、数据导出等接口

### 1.2 水平越权（IDOR）检查

**漏洞特征**：接口接收资源 ID（`/api/order/123`、`/user/profile/456`），但查询时未过滤当前用户。

```python
# ❌ 漏洞示例
@app.route('/api/order/<int:order_id>')
@login_required
def get_order(order_id):
    order = Order.query.get(order_id)  # 未过滤 user_id
    return jsonify(order.to_dict())

# ✅ 修复示例
@app.route('/api/order/<int:order_id>')
@login_required
def get_order(order_id):
    order = Order.query.filter_by(id=order_id, user_id=current_user.id).first_or_404()
    return jsonify(order.to_dict())
```

**检查点**：
- URL 路径参数：`<int:id>`、`<record_id>`、`<token>`
- Body/Query 参数：`?user_id=`、`{"id": 123}`
- 文件访问：`/download/<filename>`、`/export/<record_id>`
- 任务状态查询：`/task/status/<task_id>`（任务创建时是否绑定 owner？）

### 1.3 垂直越权检查

**漏洞特征**：管理员接口缺少角色检查，普通用户可访问。

```python
# ❌ 漏洞示例
@app.route('/admin/users')
@login_required
def admin_users():  # 只验证了登录，未验证是否管理员
    return User.query.all()

# ✅ 修复示例
@app.route('/admin/users')
@login_required
def admin_users():
    if not current_user.is_admin:
        abort(403)
    return User.query.all()
```

**检查点**：
- 路径以 `/admin/`、`/manage/`、`/system/` 开头的接口
- DELETE、PATCH、批量操作等高风险方法
- 用户管理、权限变更、系统配置接口

### 1.4 可预测资源标识符检测（v4 新增）

**漏洞特征**：资源标识符使用可预测/可枚举的模式，攻击者可通过遍历获取大量数据。

**常见可预测模式**：

| 模式类型 | 示例 | 遍历方式 |
|----------|------|---------|
| 纯顺序数字 | `/api/order/1`, `/api/order/2` | 从 1 递增遍历 |
| 日期+序号 | `RJLL20250219037` | 固定日期前缀，遍历序号 000-999 |
| 可枚举参数 | `?wf_num=MS0002022` | 递增数字部分 |
| 用户名参数 | `?userId=zhangsan` | 遍历已知用户名列表 |

```python
# ❌ 危险：使用顺序数字 ID 且无归属校验
@app.route('/api/record/<int:record_id>')
@login_required
def get_record(record_id):
    return Record.query.get(record_id).to_dict()  # 可遍历所有记录

# ❌ 危险：日期+序号组合的可预测编号
def generate_order_number():
    today = datetime.now().strftime('%Y%m%d')
    seq = get_next_sequence()  # 001, 002, 003...
    return f"ORD{today}{seq:03d}"  # ORD20250219001 — 可枚举

# ✅ 修复：使用不可预测的 UUID 或加密 ID
import uuid
def generate_order_number():
    return str(uuid.uuid4())  # 不可枚举

# ✅ 修复：即使用顺序 ID，也必须做归属校验
@app.route('/api/record/<int:record_id>')
@login_required
def get_record(record_id):
    record = Record.query.filter_by(id=record_id, user_id=current_user.id).first_or_404()
    return record.to_dict()
```

**检查步骤**：
1. 找出所有接受资源标识符的接口参数
2. 分析标识符是否使用了顺序数字、日期+序号、可枚举字符串等模式
3. 检查接口是否对标识符做了归属校验（`WHERE user_id = current_user.id`）
4. 若标识符可预测且无归属校验 → 高危 IDOR

### 1.5 参数遍历攻击面分析（v4 新增）

**漏洞特征**：URL 或查询参数使用顺序/可枚举值，修改参数值即可越权访问其他页面或数据。

```python
# ❌ 危险：功能页面通过顺序参数标识，无权限检查
@app.route('/admin/config')
@login_required
def admin_config():
    page_id = request.args.get('page_id')  # page_id=1, 2, 3...
    config = SystemConfig.query.get(page_id)  # 任何登录用户可遍历所有配置页
    return render_template('config.html', config=config)

# ✅ 修复：对每个参数值做权限校验
@app.route('/admin/config')
@login_required
@admin_required  # 角色检查
def admin_config():
    page_id = request.args.get('page_id')
    config = SystemConfig.query.filter_by(
        id=page_id,
        allowed_roles__contains=current_user.role  # 权限过滤
    ).first_or_404()
    return render_template('config.html', config=config)
```

**检查点**：
- URL 中包含顺序编号的参数（如 `wf_num=S005`、`page=1`、`step=2`）
- 修改参数值是否能访问不属于当前用户/角色的页面或数据
- 工作流、审批流、流程配置等参数是否可遍历

### 1.6 响应字段最小化审计（v4 新增）

**漏洞特征**：API 接口返回了远超业务需要的字段，导致敏感信息泄露。

**高风险场景**：
- 搜索/查询人员接口返回了手机号、身份证号、工号、邮箱等
- 列表接口返回了完整的记录详情（包含地址、项目详情等）
- 用户信息接口返回了 `password_hash`、内部 `user_id`、`role` 等内部字段

```python
# ❌ 危险：搜索接口返回全量用户信息
@app.route('/api/search/users')
@login_required
def search_users():
    name = request.args.get('name')
    users = User.query.filter(User.name.contains(name)).all()
    return jsonify([u.to_dict() for u in users])
    # to_dict() 可能包含: phone, id_card, address, password_hash...

# ✅ 修复：使用序列化白名单，仅返回业务所需字段
@app.route('/api/search/users')
@login_required
def search_users():
    name = request.args.get('name')
    users = User.query.filter(User.name.contains(name)).all()
    return jsonify([{
        'id': u.public_id,  # 使用非连续的公开 ID
        'name': u.name,
        # 仅返回业务需要的字段，不含手机号/身份证/地址等
    } for u in users])
```

**检查步骤**：
1. 对每个 API 接口，分析响应 JSON 的字段列表
2. 对照业务需求，标记不必要的敏感字段
3. 特别关注：搜索接口、列表接口、用户信息接口、下拉选项接口
4. 检查 ORM 模型的 `to_dict()`/`serialize()` 方法是否有字段白名单

### 1.7 关联对象越权检测（v5 新增）

**漏洞特征**：修改资源时，关联引用的外键对象（收货地址、支付账户、优惠券等）未做归属校验，攻击者可将他人的关联对象绑定到自己的资源上。

```python
# ❌ 危险：修改订单时直接信任前端传的 address_id
@app.route('/api/order/<int:order_id>', methods=['PUT'])
@login_required
def update_order(order_id):
    order = Order.query.filter_by(id=order_id, user_id=current_user.id).first_or_404()
    order.address_id = request.json['address_id']  # 未校验 address 是否属于当前用户
    order.coupon_id = request.json.get('coupon_id')  # 未校验 coupon 归属
    db.session.commit()
    return jsonify(order.to_dict())

# ✅ 修复：对每个关联外键都做归属校验
@app.route('/api/order/<int:order_id>', methods=['PUT'])
@login_required
def update_order(order_id):
    order = Order.query.filter_by(id=order_id, user_id=current_user.id).first_or_404()
    # 校验地址归属
    address = Address.query.filter_by(
        id=request.json['address_id'], user_id=current_user.id
    ).first_or_404()
    order.address_id = address.id
    # 校验优惠券归属
    if coupon_id := request.json.get('coupon_id'):
        coupon = Coupon.query.filter_by(
            id=coupon_id, user_id=current_user.id, used=False
        ).first_or_404()
        order.coupon_id = coupon.id
    db.session.commit()
    return jsonify(order.to_dict())
```

**检查步骤**：
1. 找出所有接受外键 ID 的更新/创建接口（`address_id`、`account_id`、`coupon_id` 等）
2. 检查这些外键引用的对象是否做了归属校验
3. 特别关注：订单-地址、用户-支付方式、申请-审批人 等关联关系

### 1.8 批量操作越权检测（v5 新增）

**漏洞特征**：批量删除/修改/导出接口接受 ID 数组，但未对每个 ID 逐一校验归属。

```python
# ❌ 危险：批量删除只校验了 ID 存在，未校验归属
@app.route('/api/records/batch-delete', methods=['POST'])
@login_required
def batch_delete():
    ids = request.json['ids']  # [1, 2, 3, 999]  999 可能是他人的
    Record.query.filter(Record.id.in_(ids)).delete()
    db.session.commit()
    return jsonify({"deleted": len(ids)})

# ✅ 修复：逐一校验归属，只删除属于当前用户的记录
@app.route('/api/records/batch-delete', methods=['POST'])
@login_required
def batch_delete():
    ids = request.json['ids']
    deleted = Record.query.filter(
        Record.id.in_(ids),
        Record.user_id == current_user.id  # 归属过滤
    ).delete(synchronize_session=False)
    db.session.commit()
    return jsonify({"deleted": deleted})  # 返回实际删除数，非请求数
```

**检查步骤**：
1. 找出所有接受 ID 数组/列表的接口（`ids[]`、`batch_ids`、`selected`）
2. 检查是否对数组中每个 ID 都做了归属校验
3. 检查批量导出接口是否有数量限制和权限范围校验

### 1.9 隐藏接口暴露检测（v5 新增）

**漏洞特征**：前端通过隐藏菜单/按钮实现权限控制，但后端接口本身未做鉴权，直接请求即可访问。

**检查步骤**：
1. 收集路由注册文件中的所有接口列表
2. 对比前端代码中实际展示/调用的接口，找出"隐藏"接口
3. 检查这些接口是否有独立的后端认证/授权保护
4. 检查 Swagger/OpenAPI 文档是否在生产环境可访问（`/swagger-ui/`、`/api-docs/`、`/docs`）
5. 检查前端 JS Bundle 中是否包含未在页面使用的 API 路径常量

```python
# ❌ 危险：调试/管理接口无认证保护
@app.route('/api/internal/clear-cache', methods=['POST'])
def clear_cache():  # 无 @login_required，无角色检查
    cache.clear()
    return jsonify({"status": "ok"})

# ❌ 危险：Swagger 文档在生产环境暴露
# Flask-RESTX 默认在 /swagger-ui/ 暴露文档
# Spring Boot 默认在 /swagger-ui/index.html 暴露文档

# ✅ 修复：所有接口必须有后端鉴权，生产环境关闭文档
@app.route('/api/internal/clear-cache', methods=['POST'])
@login_required
@admin_required
def clear_cache():
    cache.clear()
    return jsonify({"status": "ok"})
```

---

## A02: 加密机制失效（Cryptographic Failures）

### 2.1 密码存储

```python
# ❌ 危险
import hashlib
hashed = hashlib.md5(password.encode()).hexdigest()  # MD5 不安全
hashed = hashlib.sha1(password).hexdigest()  # SHA1 不安全
password_db = password  # 明文

# ✅ 正确
from werkzeug.security import generate_password_hash, check_password_hash
hashed = generate_password_hash(password, method='pbkdf2:sha256:600000')
```

**检查关键词**：`md5(`、`sha1(`、`hashlib.`、`password =`（赋值给字段）

### 2.2 硬编码敏感信息

**检查正则模式**：
```
(SECRET_KEY|password|api_key|apikey|access_token|private_key)\s*=\s*["'][^"']{6,}["']
```

**常见位置**：`config.py`、`.env`（未被 .gitignore 忽略）、硬编码数据库 DSN

### 2.3 弱随机数

```python
# ❌ 危险（可预测）
import random
token = str(random.randint(100000, 999999))

# ✅ 正确
import secrets
token = secrets.token_urlsafe(32)
```

---

## A03: 注入（Injection）

### 3.1 SQL 注入

```python
# ❌ 漏洞
name = request.args.get('name')
users = db.execute(f"SELECT * FROM users WHERE name = '{name}'")  # 字符串拼接

# ✅ 修复 - 参数化查询
users = db.execute("SELECT * FROM users WHERE name = ?", (name,))
# 或使用 ORM
users = User.query.filter_by(name=name).all()
```

**检查关键词**: `execute(f"`, `execute("...%s`, `.format(`, `+ request.`, `+ str(`（拼接 SQL）

### 3.2 XSS

```python
# ❌ Flask 模板关闭了自动转义
from flask import Markup
# 不安全：直接渲染用户输入
return render_template_string('<div>' + user_input + '</div>')

# ✅ 使用 Jinja2 自动转义（默认开启）
return render_template('page.html', content=user_input)
```

**JavaScript 检查**：
```javascript
// ❌ 危险
element.innerHTML = userInput;
document.write(userInput);

// ✅ 安全
element.textContent = userInput;
```

### 3.3 命令注入

```python
# ❌ 漏洞
filename = request.form['filename']
os.system(f"convert {filename} output.png")

# ✅ 修复 - 使用列表参数
subprocess.run(['convert', filename, 'output.png'], check=True)
```

**检查关键词**：`os.system(`、`subprocess.call(`（字符串参数）、`eval(`、`exec(`

---

## A04: 不安全设计（Insecure Design）

### 4.1 速率限制

- 登录接口是否有失败次数限制？
- 短信/邮件验证码接口是否有频率限制？
- 批量查询 API 是否有 page_size 上限？

### 4.2 业务逻辑基础检查

- 负数金额是否被允许？
- 状态机转换是否有合法性校验（如：不能从"已完成"跳回"待支付"）？
- 优惠码是否可以重复使用？

### 4.3 支付/订单逻辑篡改（v5 新增）

**漏洞特征**：支付链路中前端传递的金额/数量等参数被后端直接信任，攻击者可篡改实现低价购买或免费获取。

```python
# ❌ 危险：直接使用前端传来的价格创建订单
@app.route('/api/order/create', methods=['POST'])
@login_required
def create_order():
    data = request.json
    order = Order(
        product_id=data['product_id'],
        quantity=data['quantity'],
        price=data['price'],  # 信任前端传的价格！
        total=data['quantity'] * data['price']
    )
    db.session.add(order)
    db.session.commit()
    return jsonify(order.to_dict())

# ✅ 修复：价格从数据库读取，数量做合法性校验
@app.route('/api/order/create', methods=['POST'])
@login_required
def create_order():
    data = request.json
    product = Product.query.get_or_404(data['product_id'])
    quantity = int(data['quantity'])
    if quantity <= 0:
        abort(400, "数量必须大于 0")
    order = Order(
        product_id=product.id,
        quantity=quantity,
        price=product.price,  # 从数据库读取价格
        total=quantity * product.price
    )
    db.session.add(order)
    db.session.commit()
    return jsonify(order.to_dict())
```

**检查点**：
- 前端传递的价格/金额参数是否被后端信任？还是从数据库重新读取？
- 数量参数是否校验 > 0？是否有最大值限制？
- 优惠券/折扣是否在后端重新计算？是否校验适用条件？
- 积分抵扣是否校验用户实际积分余额？

### 4.4 支付回调校验（v5 新增）

```python
# ❌ 危险：支付回调未校验签名和金额
@app.route('/api/payment/callback', methods=['POST'])
def payment_callback():
    order_id = request.form['order_id']
    order = Order.query.get(order_id)
    order.status = 'paid'  # 直接标记支付成功
    db.session.commit()
    return "OK"

# ✅ 修复：校验签名 + 校验金额一致性
@app.route('/api/payment/callback', methods=['POST'])
def payment_callback():
    if not verify_payment_signature(request.form, PAYMENT_SECRET):
        abort(403)
    order_id = request.form['order_id']
    paid_amount = Decimal(request.form['amount'])
    order = Order.query.get_or_404(order_id)
    if order.total != paid_amount:
        logger.warning(f"金额不一致: 订单={order.total}, 回调={paid_amount}")
        abort(400)
    order.status = 'paid'
    db.session.commit()
    return "OK"
```

### 4.5 多步骤流程绕过（v5 新增）

**漏洞特征**：多步骤流程（注册、审批、下单）中，攻击者直接请求后续步骤的接口跳过前置校验。

```python
# ❌ 危险：审批流程可跳步
@app.route('/api/approval/<int:id>/approve', methods=['POST'])
@login_required
def approve(id):
    approval = Approval.query.get_or_404(id)
    approval.status = 'approved'  # 未校验当前状态是否允许审批
    db.session.commit()

# ✅ 修复：严格校验状态转换合法性
VALID_TRANSITIONS = {
    'pending': ['reviewing'],
    'reviewing': ['approved', 'rejected'],
    'approved': ['completed'],
    'rejected': ['pending'],  # 允许重新提交
}

@app.route('/api/approval/<int:id>/approve', methods=['POST'])
@login_required
def approve(id):
    approval = Approval.query.get_or_404(id)
    target_status = 'approved'
    if target_status not in VALID_TRANSITIONS.get(approval.status, []):
        abort(400, f"不允许从 {approval.status} 转换到 {target_status}")
    approval.status = target_status
    db.session.commit()
```

**检查点**：
- 多步骤流程每一步是否有状态前置条件校验？
- step/phase 参数是否可被篡改直接跳到终态？
- 已完成/已拒绝的流程能否被重放中间步骤？

### 4.6 验证码/OTP 逻辑缺陷（v5 新增）

**漏洞特征**：验证码实现存在多种逻辑缺陷，可被绕过或暴力破解。

```python
# ❌ 危险：验证码无过期时间、无错误次数限制、未绑定手机号
@app.route('/api/verify-code', methods=['POST'])
def verify_code():
    code = request.json['code']
    phone = request.json['phone']
    stored_code = redis.get('verify_code')  # 未绑定手机号！
    if code == stored_code:
        return jsonify({"verified": True})

# ✅ 修复：绑定手机号 + TTL + 错误次数限制
@app.route('/api/verify-code', methods=['POST'])
def verify_code():
    phone = request.json['phone']
    code = request.json['code']
    # 检查错误次数
    attempts_key = f'verify_attempts:{phone}'
    attempts = int(redis.get(attempts_key) or 0)
    if attempts >= 5:
        abort(429, "验证码错误次数过多，请重新获取")
    # 校验验证码（绑定手机号）
    stored_code = redis.get(f'verify_code:{phone}')
    if not stored_code or code != stored_code.decode():
        redis.incr(attempts_key)
        redis.expire(attempts_key, 300)
        abort(400, "验证码错误")
    # 验证成功，立即删除（一次性使用）
    redis.delete(f'verify_code:{phone}')
    redis.delete(attempts_key)
    return jsonify({"verified": True})
```

**检查点**：
- 验证码是否有 TTL（建议 5 分钟内过期）？
- 验证码错误次数是否有限制？4-6 位数字码可暴力枚举
- 验证码与手机号/邮箱是否绑定校验？能否先获取验证码再替换接收方？
- 验证码是否出现在 API 响应体中（方便前端调试但泄露）？
- 图形验证码是否可被 OCR 或固定值绕过？

### 4.7 幂等性缺失（v5 新增）

**漏洞特征**：创建类接口缺少幂等保护，重复提交可产生重复记录或重复扣款。

```python
# ❌ 危险：无幂等保护，重复提交产生多个订单
@app.route('/api/order/create', methods=['POST'])
@login_required
def create_order():
    order = Order(**request.json, user_id=current_user.id)
    db.session.add(order)
    db.session.commit()
    return jsonify(order.to_dict())

# ✅ 修复：使用幂等键防止重复提交
@app.route('/api/order/create', methods=['POST'])
@login_required
def create_order():
    idempotency_key = request.headers.get('Idempotency-Key')
    if idempotency_key:
        existing = Order.query.filter_by(
            idempotency_key=idempotency_key, user_id=current_user.id
        ).first()
        if existing:
            return jsonify(existing.to_dict())  # 返回已有记录
    order = Order(**request.json, user_id=current_user.id, idempotency_key=idempotency_key)
    db.session.add(order)
    db.session.commit()
    return jsonify(order.to_dict()), 201
```

**检查点**：
- 创建类接口（订单/申请/注册）是否支持 Idempotency-Key？
- 表单提交是否有前端防重（disable button）+ 后端去重（唯一约束）？
- 奖励/优惠券领取接口是否有唯一约束防止重复领取？
- 通知发送接口是否有去重逻辑？

### 4.8 时间维度遍历（v5 新增）

**漏洞特征**：通过修改时间范围或部门参数，导出超出权限范围的数据。

```python
# ❌ 危险：导出接口未限制时间范围和部门
@app.route('/api/export/records')
@login_required
def export_records():
    start = request.args.get('start')  # 2020-01-01
    end = request.args.get('end')      # 2099-12-31
    dept = request.args.get('dept')    # all
    records = Record.query.filter(
        Record.created_at.between(start, end),
        Record.department == dept if dept != 'all' else True
    ).all()
    return generate_csv(records)  # 可能导出全库数据

# ✅ 修复：限制时间跨度 + 限制部门权限
@app.route('/api/export/records')
@login_required
def export_records():
    start = parse_date(request.args.get('start'))
    end = parse_date(request.args.get('end'))
    if (end - start).days > 90:
        abort(400, "导出时间跨度不能超过 90 天")
    records = Record.query.filter(
        Record.created_at.between(start, end),
        Record.department == current_user.department  # 限制本部门
    ).limit(10000).all()  # 数量上限
    return generate_csv(records)
```

---

## A05: 安全配置错误（Security Misconfiguration）

### 5.1 调试模式

```python
# ❌ 生产环境不应开启 DEBUG
app.run(debug=True)
app.config['DEBUG'] = True
```

### 5.2 CORS 配置

```python
# ❌ 过于宽松
CORS(app, origins="*")

# ✅ 限定来源
CORS(app, origins=["https://yourdomain.com"])
```

### 5.3 错误响应

```python
# ❌ 暴露内部信息
@app.errorhandler(500)
def error(e):
    return str(e), 500  # 返回完整异常

# ✅ 返回通用错误
@app.errorhandler(500)
def error(e):
    return jsonify({"error": "Internal Server Error"}), 500
```

---

## A06: 脆弱和过时的组件（Vulnerable and Outdated Components）

### 6.1 已知漏洞检查

对以下文件中的依赖，检查是否有 CVSS ≥ 7.0 的已知 CVE：
- Python: `requirements.txt`
- Node: `package.json`
- Go: `go.mod`
- Java: `pom.xml`、`build.gradle`

**常见高危组件**（截至 2025 年）：
- `log4j` < 2.17.1 (Log4Shell CVE-2021-44228)
- `django` < 4.2.x (多个 SQL 注入/XSS)
- `flask` < 3.x (建议升级)
- `lodash` < 4.17.21 (Prototype Pollution)
- `pillow` < 10.x (多个图像处理 CVE)

---

## A07: 认证失败（Identification and Authentication Failures）

### 7.1 会话管理

```python
# 检查：登出时是否清除会话
@app.route('/logout')
def logout():
    session.clear()  # 必须有
    logout_user()
    return redirect('/')
```

### 7.2 JWT 安全

```python
# ❌ 危险：不验证签名
jwt.decode(token, options={"verify_signature": False})

# ❌ 危险：接受 alg: none
# ✅ 正确：明确指定算法
jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
```

### 7.3 凭据出现在日志

```python
# ❌ 危险
logger.info(f"User login: {username} with password {password}")
logger.debug(f"Request: {request.json}")  # JSON 中可能含密码
```

---

## A08: 数据完整性失败（Software and Data Integrity Failures）

### 8.1 不安全反序列化

```python
# ❌ 危险
import pickle
data = pickle.loads(user_provided_data)  # 任意代码执行风险

import yaml
data = yaml.load(user_input)  # 应使用 yaml.safe_load

# ❌ 危险
eval(user_input)
```

---

## A09: 日志和监控不足（Security Logging and Monitoring Failures）

**应记录日志的操作**：
- 所有登录（成功/失败）
- 密码修改、权限变更
- 敏感数据访问（导出、批量查询）
- 管理员操作

**不应记录到日志**：
- 密码明文
- 完整的 Authorization Token
- 信用卡号、身份证号等 PII

---

## A10: SSRF（Server-Side Request Forgery）

```python
# ❌ 危险：无限制请求用户指定 URL
@app.route('/fetch')
def fetch():
    url = request.args.get('url')
    resp = requests.get(url)  # 可访问内网资源

# ✅ 修复：URL 白名单校验
ALLOWED_DOMAINS = {'api.example.com', 'cdn.example.com'}
def is_safe_url(url):
    from urllib.parse import urlparse
    parsed = urlparse(url)
    return parsed.scheme in ('http', 'https') and parsed.hostname in ALLOWED_DOMAINS
```

---

## 扩展: 敏感信息泄露

### E1: API Key URL 参数传递

```python
# ❌ 危险：API Key 出现在 URL 中（会被日志、代理记录）
provided = request.args.get('api_key') or request.headers.get('X-API-Key')

# ✅ 修复：仅允许 Header 传递
provided = request.headers.get('X-API-Key')
```

### E2: 过度信息返回

- API 响应是否返回了 `password_hash`、内部 `id` 序列、系统路径？
- 分页接口是否允许 `page_size=9999` 批量导出？

### E3: 配置文件泄露

- `.env`、`config.py`、`*.pem` 是否在 `.gitignore` 中？
- 是否有备份文件（`config.py.bak`、`*.sql`）意外提交？

---

## 扩展: CSRF 检查（CWE-352）

### CSRF 保护

```python
# Flask — 需要 flask-wtf 或手动实现
from flask_wtf.csrf import CSRFProtect
csrf = CSRFProtect(app)

# Django — 默认启用 CsrfViewMiddleware
# 检查是否有 @csrf_exempt 装饰器
```

**检查点**：
- 所有状态变更操作（POST/PUT/DELETE）是否有 CSRF token？
- 是否有 `@csrf_exempt` 或 `csrf_protect = False` 的豁免？
- SameSite Cookie 属性是否设置为 `Lax` 或 `Strict`？

---

## 扩展: API 安全（OWASP API Top 10）

### Mass Assignment（批量赋值）— CWE-915

```python
# ❌ 危险：接受所有字段更新
user.update(**request.json)  # 用户可能传入 {"is_admin": true}

# ✅ 修复：白名单字段
allowed = {'name', 'email', 'avatar'}
data = {k: v for k, v in request.json.items() if k in allowed}
user.update(**data)
```

### 过度数据暴露

```python
# ❌ 危险：返回完整模型
return jsonify(user.to_dict())  # 包含 password_hash、internal_id 等

# ✅ 修复：序列化白名单
return jsonify({
    'id': user.public_id,
    'name': user.name,
    'email': user.email
})
```

### 资源限制

```python
# ❌ 危险：无分页限制
page_size = request.args.get('page_size', type=int)  # 可传入 999999

# ✅ 修复：强制上限
page_size = min(request.args.get('page_size', 20, type=int), 100)
```

---

## 扩展: GraphQL 安全

### 查询深度限制

```python
# ❌ 危险：无深度限制
# 攻击者可构造嵌套查询消耗服务器资源
# { user { friends { friends { friends { ... } } } } }

# ✅ 修复：设置最大查询深度
from graphql import GraphQLError
MAX_DEPTH = 5
```

### Introspection 禁用

```python
# 生产环境应禁用 Introspection
# ✅ 修复
schema = graphene.Schema(query=Query, auto_camelcase=False)
# 在中间件中拦截 __schema 和 __type 查询
```

---

## 扩展: WebSocket 安全

### Origin 验证

```javascript
// ❌ 危险：不验证来源
wss.on('connection', (ws) => { ... })

// ✅ 修复：验证 Origin
wss.on('connection', (ws, req) => {
  const origin = req.headers.origin;
  if (!ALLOWED_ORIGINS.includes(origin)) {
    ws.close(1008, 'Origin not allowed');
    return;
  }
})
```

---

## 扩展: 客户端安全

### localStorage 敏感数据

```javascript
// ❌ 危险：Token 存储在 localStorage（XSS 可窃取）
localStorage.setItem('auth_token', token);

// ✅ 修复：使用 httpOnly Cookie
// 由服务端设置 Set-Cookie: token=xxx; HttpOnly; Secure; SameSite=Lax
```

### Clickjacking

```python
# ✅ 服务端设置
response.headers['X-Frame-Options'] = 'DENY'
response.headers['Content-Security-Policy'] = "frame-ancestors 'none'"
```

### postMessage

```javascript
// ❌ 危险：不验证来源
window.addEventListener('message', (event) => {
  processData(event.data);  // 任何来源的消息都处理
});

// ✅ 修复：验证 origin
window.addEventListener('message', (event) => {
  if (event.origin !== 'https://trusted-domain.com') return;
  processData(event.data);
});
```

---

## 扩展: 竞态条件（CWE-362）

### 余额双花

```python
# ❌ 危险：无原子性保证
balance = get_balance(user_id)  # 查询余额
if balance >= amount:
    deduct_balance(user_id, amount)  # 扣款
    # 并发请求可能导致余额被扣成负数

# ✅ 修复：数据库事务 + 行级锁
with db.session.begin():
    user = User.query.filter_by(id=user_id).with_for_update().one()
    if user.balance >= amount:
        user.balance -= amount
```

### 文件竞争

```python
# ❌ 危险：TOCTOU
if os.path.exists(filepath):  # 检查
    os.remove(filepath)       # 使用（两步之间文件可能已变化）

# ✅ 修复：直接操作，捕获异常
try:
    os.remove(filepath)
except FileNotFoundError:
    pass
```

---

## 扩展: 供应链安全

### 检查要点

1. **依赖锁定**：是否有 `package-lock.json`/`poetry.lock`/`go.sum`？
2. **版本固定**：是否使用精确版本而非范围（`^`/`~`）？
3. **Typosquatting**：新引入的包名是否可疑（如 `requests` vs `reqeusts`）？
4. **维护状态**：依赖是否超过 2 年未更新？
5. **已知漏洞**：`npm audit`/`pip-audit`/`govulncheck` 结果如何？

---

## 🆕 v1.6 新增：中间件/基础服务默认配置未授权检查

> 来源：SOC 安全管理平台 213 条「未授权弱口令」类工单分析（2024-2025 年真实事件）

### M1: Docker API 未授权暴露

```yaml
# ❌ 危险：docker-compose.yml 中暴露 Docker Remote API 无 TLS
services:
  docker-api:
    image: docker:dind
    ports:
      - "2375:2375"  # 未加密暴露 Docker API，任何人可远程执行容器命令
    # 缺少 DOCKER_TLS_CERTDIR 配置

# ✅ 修复：不暴露 2375，使用 TLS 加密的 2376
services:
  docker-api:
    image: docker:dind
    ports:
      - "2376:2376"
    environment:
      - DOCKER_TLS_CERTDIR=/certs
    volumes:
      - docker-certs:/certs
```

**检查正则**：`2375:2375|2375/tcp|DOCKER_HOST.*2375`

### M2: Elasticsearch 无认证

```yaml
# ❌ 危险：ES 暴露 9200 无认证
services:
  elasticsearch:
    image: elasticsearch:7.17.0
    ports:
      - "9200:9200"
    # 缺少 xpack.security.enabled

# ✅ 修复：启用 xpack 安全认证
services:
  elasticsearch:
    image: elasticsearch:7.17.0
    environment:
      - xpack.security.enabled=true
      - xpack.security.transport.ssl.enabled=true
      - ELASTIC_PASSWORD=${ES_PASSWORD}
    ports:
      - "127.0.0.1:9200:9200"  # 仅本地绑定
```

**检查关键词**：`9200:9200` + 缺少 `xpack.security.enabled: true`

### M3: Redis 无密码

```yaml
# ❌ 危险
services:
  redis:
    image: redis:7
    ports:
      - "6379:6379"  # 暴露到外部，无密码

# ✅ 修复
services:
  redis:
    image: redis:7
    command: redis-server --requirepass ${REDIS_PASSWORD}
    ports:
      - "127.0.0.1:6379:6379"  # 仅本地
```

### M4: Spring Boot Actuator 暴露

```yaml
# ❌ 危险：application.yml
management:
  endpoints:
    web:
      exposure:
        include: "*"  # 暴露所有端点，含 /env、/heapdump、/shutdown

# ✅ 修复：仅暴露健康检查
management:
  endpoints:
    web:
      exposure:
        include: health,info
  endpoint:
    health:
      show-details: when-authorized
```

**检查关键词**：`management.endpoints.web.exposure.include` = `*` 或含 `env`/`heapdump`/`shutdown`

### M5: Nacos 默认 Token / 认证绕过

```properties
# ❌ 危险：使用默认 identity
nacos.core.auth.server.identity.key=serverIdentity
nacos.core.auth.server.identity.value=security
nacos.core.auth.plugin.nacos.token.secret.key=SecretKey012345678901234567890123456789012345678901234567890123456789

# ✅ 修复：自定义强随机值
nacos.core.auth.enabled=true
nacos.core.auth.server.identity.key=myCustomKey
nacos.core.auth.server.identity.value=${NACOS_IDENTITY_VALUE}  # 从环境变量读取
nacos.core.auth.plugin.nacos.token.secret.key=${NACOS_TOKEN_SECRET}  # ≥ 32 字节
```

### M6: 其他常见中间件默认凭据

```yaml
# ❌ MinIO 默认凭据
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin

# ❌ RabbitMQ 默认凭据 + 管理端口暴露
RABBITMQ_DEFAULT_USER=guest
RABBITMQ_DEFAULT_PASS=guest
ports:
  - "15672:15672"  # 管理界面暴露

# ❌ MySQL/PostgreSQL 弱密码
MYSQL_ROOT_PASSWORD=123456
POSTGRES_PASSWORD=postgres
```

**检查正则**：
```
(MINIO_ROOT_PASSWORD|RABBITMQ_DEFAULT_PASS|MYSQL_ROOT_PASSWORD|POSTGRES_PASSWORD)\s*[=:]\s*["']?(minioadmin|guest|123456|password|root|admin)["']?
```

---

## 🆕 v1.6 新增：高频组件 CVE 模式库

> 来源：SOC 安全管理平台 79 条「框架组件漏洞」类工单分析

### C1: ActiveMQ OpenWire 反序列化 (CVE-2023-46604)

```xml
<!-- pom.xml 中检查 -->
<dependency>
    <groupId>org.apache.activemq</groupId>
    <artifactId>activemq-client</artifactId>
    <version>5.15.0</version>  <!-- ❌ 受影响: < 5.15.16, < 5.16.7, < 5.17.6 -->
</dependency>
```
**修复**：升级至 5.15.16+/5.16.7+/5.17.6+ 或 5.18.0+

### C2: Harbor 未授权访问 (CVE-2022-46463)

```yaml
# docker-compose.yml 中检查 Harbor 版本
services:
  harbor:
    image: goharbor/harbor-core:v2.5.0  # ❌ 受影响: < 2.7.3
```
**修复**：升级至 2.7.3+ 或 2.8.3+

### C3: Nacos 认证绕过

```yaml
# application.yml / application.properties
nacos:
  core:
    auth:
      enabled: false  # ❌ 未启用认证
```
**检查**：`nacos.core.auth.enabled` 是否为 `true`，identity key/value 是否为默认值

### C4: Fastjson 反序列化

```xml
<!-- ❌ 高危版本 -->
<dependency>
    <groupId>com.alibaba</groupId>
    <artifactId>fastjson</artifactId>
    <version>1.2.68</version>  <!-- < 1.2.83 均存在反序列化风险 -->
</dependency>
```
**修复**：迁移至 `fastjson2`（2.x）或升级至 1.2.83+，并启用 safeMode

### C5: Spring Boot Actuator 信息泄露 + Spring4Shell (CVE-2022-22965)

```xml
<!-- 检查 Spring 版本 -->
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>2.6.3</version>  <!-- ❌ 受 Spring4Shell 影响 -->
</parent>
```
**修复**：升级至 Spring Boot 2.6.6+/2.5.12+ 或 Spring Framework 5.3.18+

### C6: Log4j2 JNDI 注入 (Log4Shell CVE-2021-44228)

```xml
<!-- ❌ 高危 -->
<dependency>
    <groupId>org.apache.logging.log4j</groupId>
    <artifactId>log4j-core</artifactId>
    <version>2.14.1</version>  <!-- < 2.17.1 受影响 -->
</dependency>
```
**修复**：升级至 2.17.1+

### C7: n8n Webhook RCE (CVE-2026-21858)

```yaml
# docker-compose.yml
services:
  n8n:
    image: n8nio/n8n:0.x  # 检查版本是否受影响
    ports:
      - "5678:5678"  # Webhook 端口暴露
```
**修复**：升级至修复版本，限制 Webhook 访问来源

---

## 🆕 v1.6 新增：部署产物与敏感文件泄露检查

> 来源：SOC 安全管理平台 34 条「敏感文件泄露」类工单分析

### D1: .gitignore 完整性检查

```gitignore
# ✅ 必须包含以下条目
.env
.env.*
*.pem
*.key
*.p12
*.jks
*.bak
*.sql
*.dump
*.tar.gz
*.zip
.DS_Store
.svn/
*.swp
*.swo
*~
__pycache__/
node_modules/
.idea/
.vscode/
```

**检查步骤**：读取 `.gitignore`，确认以上关键条目存在

### D2: 前端 AK/SK 泄露检查

```javascript
// ❌ 危险：前端代码中硬编码云凭据
const ossConfig = {
  accessKeyId: 'LTAI5txxxxxxxxxxxxxxxx',      // ❌ AK 硬编码
  accessKeySecret: 'xxxxxxxxxxxxxxxxxxxxxxxx',  // ❌ SK 硬编码
  bucket: 'my-bucket',
  region: 'oss-cn-hangzhou'
};

// ❌ 危险：AWS 凭据
const AWS_ACCESS_KEY = 'AKIAIOSFODNN7EXAMPLE';
const AWS_SECRET_KEY = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
```

**检查正则**（扫描 `*.js`/`*.ts`/`*.vue`/`*.jsx`/`*.tsx`/`*.html`）：
```regex
(LTAI[a-zA-Z0-9]{12,}|AKIA[A-Z0-9]{16}|AccessKeyId|accessKeySecret|aws_secret_access_key)\s*[=:'"]\s*['"]?[A-Za-z0-9/+=]{16,}
```

### D3: Web 服务器目录列表检查

```nginx
# ❌ 危险：Nginx 开启目录列表
server {
    location /uploads/ {
        autoindex on;  # 允许列出所有上传文件
    }
}

# ✅ 修复
server {
    location /uploads/ {
        autoindex off;
    }
}
```

```apache
# ❌ Apache 开启目录列表
<Directory /var/www/html/uploads>
    Options +Indexes  # 允许目录浏览
</Directory>

# ✅ 修复
<Directory /var/www/html/uploads>
    Options -Indexes
</Directory>
```

### D4: VCS 元数据和备份文件检查

**检查项**：在 Web 可访问的静态资源目录中搜索以下文件/目录：

| 文件/目录 | 风险 | 检查方式 |
|----------|------|---------|
| `.svn/entries` | SVN 源码和历史暴露 | 检查 Web root 下是否存在 |
| `.git/config` | Git 配置和可能的远程仓库 URL | 检查 Web root 下是否存在 |
| `.DS_Store` | macOS 目录结构信息 | `find . -name .DS_Store` |
| `*.tar.gz`/`*.zip`/`*.bak` | 源代码/数据备份 | 检查 Web root 下是否有压缩包 |
| `*.sql`/`*.dump` | 数据库备份 | 不应出现在 Web 可访问路径 |
| `upload.sh`/`deploy.sh` | 部署脚本可能含凭据 | 不应出现在 Web 可访问路径 |

### D5: Swagger/API 文档生产环境暴露

```python
# Flask-RESTX / FastAPI
# ❌ 生产环境默认暴露 /docs 和 /redoc
app = FastAPI()  # 未设置 docs_url=None

# ✅ 修复：生产环境关闭文档
import os
app = FastAPI(
    docs_url="/docs" if os.getenv("ENV") != "production" else None,
    redoc_url="/redoc" if os.getenv("ENV") != "production" else None,
)
```

```yaml
# Spring Boot — application-prod.yml
# ✅ 生产环境关闭 Swagger
springdoc:
  swagger-ui:
    enabled: false
  api-docs:
    enabled: false
```

### D6: CI/CD 配置中的硬编码凭据

```yaml
# ❌ 危险：GitHub Actions 中硬编码密码
- name: Deploy
  env:
    DB_PASSWORD: "my_secret_password"  # ❌ 硬编码
    API_KEY: "sk-abc123..."            # ❌ 硬编码

# ✅ 修复：使用 secrets
- name: Deploy
  env:
    DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
    API_KEY: ${{ secrets.API_KEY }}
```

**检查正则**（扫描 `.github/workflows/*.yml`、`.gitlab-ci.yml`、`Jenkinsfile`）：
```regex
(password|secret|token|api_key|apikey)\s*[:=]\s*["'][^$\{][^"']{6,}["']
```

---

## 🆕 v1.6 新增：文件操作安全深度审计

> 来源：SOC 安全管理平台 33 条「任意文件读写」类工单分析

### F1: 导出/模板文件路径注入

```python
# ❌ 危险：导出模板下载接口直接拼接用户输入
@app.route('/api/export/template')
@login_required
def get_template():
    template_name = request.args.get('name')  # 用户可传 ../../etc/passwd
    filepath = os.path.join('/app/templates/', template_name)
    return send_file(filepath)

# ✅ 修复：realpath + 前缀校验
@app.route('/api/export/template')
@login_required
def get_template():
    template_name = request.args.get('name')
    base_dir = os.path.realpath('/app/templates/')
    filepath = os.path.realpath(os.path.join(base_dir, template_name))
    if not filepath.startswith(base_dir):
        abort(403, "非法路径")
    if not os.path.isfile(filepath):
        abort(404)
    return send_file(filepath)
```

### F2: OSS 对象存储配置不当

```python
# ❌ 危险：Bucket 公开读写
import boto3
s3 = boto3.client('s3')
s3.put_bucket_acl(Bucket='my-bucket', ACL='public-read-write')  # 任何人可读写

# ❌ 危险：presigned URL 过期时间过长
url = s3.generate_presigned_url('get_object',
    Params={'Bucket': 'my-bucket', 'Key': key},
    ExpiresIn=86400 * 365  # 1 年！
)

# ✅ 修复
s3.put_bucket_acl(Bucket='my-bucket', ACL='private')
url = s3.generate_presigned_url('get_object',
    Params={'Bucket': 'my-bucket', 'Key': key},
    ExpiresIn=3600  # 1 小时
)
```

### F3: 文件下载越权

```python
# ❌ 危险：文件下载无归属校验
@app.route('/api/download/<int:file_id>')
@login_required
def download(file_id):
    file_record = FileUpload.query.get_or_404(file_id)  # 可遍历所有文件
    return send_file(file_record.path)

# ✅ 修复：校验文件归属
@app.route('/api/download/<int:file_id>')
@login_required
def download(file_id):
    file_record = FileUpload.query.filter_by(
        id=file_id, uploader_id=current_user.id
    ).first_or_404()
    return send_file(file_record.path)
```

### F4: 上传文件名清洗

```python
# ❌ 危险：使用原始文件名存储
@app.route('/upload', methods=['POST'])
def upload():
    f = request.files['file']
    f.save(os.path.join('/uploads', f.filename))  # filename 可含 ../../

# ✅ 修复：清洗文件名，使用 UUID 重命名
import uuid
from werkzeug.utils import secure_filename

@app.route('/upload', methods=['POST'])
def upload():
    f = request.files['file']
    ext = os.path.splitext(secure_filename(f.filename))[1]
    safe_name = f"{uuid.uuid4().hex}{ext}"
    f.save(os.path.join('/uploads', safe_name))
```

### F5: 文件类型校验（Magic Bytes）

```python
# ❌ 危险：仅检查扩展名
ALLOWED_EXTENSIONS = {'.jpg', '.png', '.gif'}
ext = os.path.splitext(filename)[1].lower()
if ext not in ALLOWED_EXTENSIONS:
    abort(400)
# 攻击者可将 webshell 命名为 shell.jpg

# ✅ 修复：同时检查 magic bytes
import magic

def validate_file(file_storage):
    ext = os.path.splitext(secure_filename(file_storage.filename))[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        return False
    # 检查文件实际类型
    mime = magic.from_buffer(file_storage.read(2048), mime=True)
    file_storage.seek(0)
    ALLOWED_MIMES = {'image/jpeg', 'image/png', 'image/gif'}
    return mime in ALLOWED_MIMES
```
