# CWE Top 25 映射表（2024）

本文件将 CWE Top 25 最危险软件缺陷映射到 OWASP Top 10 分类和代码审计检查点。

## 映射总表

| 排名 | CWE ID | 名称 | OWASP 映射 | 代码审计关注点 |
|------|--------|------|-----------|---------------|
| 1 | CWE-79 | 跨站脚本（XSS） | A03 注入 | innerHTML、v-html、render_template_string、未转义输出 |
| 2 | CWE-787 | 越界写入 | A03 注入 | C/C++ 缓冲区操作、不安全内存操作 |
| 3 | CWE-89 | SQL 注入 | A03 注入 | 字符串拼接SQL、未参数化查询 |
| 4 | CWE-352 | 跨站请求伪造（CSRF） | A01 访问控制 | 缺少 CSRF token、SameSite 未设置 |
| 5 | CWE-22 | 路径遍历 | A03 注入 | `../` 路径、未校验 realpath |
| 6 | CWE-125 | 越界读取 | A03 注入 | C/C++ 数组越界 |
| 7 | CWE-78 | OS 命令注入 | A03 注入 | os.system、subprocess(shell=True)、exec.Command 拼接 |
| 8 | CWE-416 | Use After Free | — | C/C++ 内存管理 |
| 9 | CWE-862 | 缺失授权 | A01 访问控制 | 路由无认证装饰器、无中间件保护 |
| 10 | CWE-434 | 无限制文件上传 | A04 不安全设计 | 未校验文件类型/大小/内容 |
| 11 | CWE-94 | 代码注入 | A03 注入 | eval()、exec()、Function()、new Function() |
| 12 | CWE-20 | 输入验证不当 | A03 注入 | 缺少类型检查、范围验证、格式校验 |
| 13 | CWE-77 | 命令注入 | A03 注入 | 通过特殊元素注入命令 |
| 14 | CWE-287 | 认证不当 | A07 认证失败 | 弱认证逻辑、可绕过的认证 |
| 15 | CWE-269 | 权限管理不当 | A01 访问控制 | 过高权限、权限未撤销 |
| 16 | CWE-502 | 不安全反序列化 | A08 数据完整性 | pickle.loads、yaml.load、ObjectInputStream |
| 17 | CWE-200 | 信息泄露 | A02 加密失效 | 错误信息暴露、API 返回过多数据 |
| 18 | CWE-863 | 授权不正确 | A01 访问控制 | 有授权但逻辑错误、可绕过 |
| 19 | CWE-918 | 服务端请求伪造(SSRF) | A10 SSRF | 用户可控 URL 发起请求 |
| 20 | CWE-119 | 内存缓冲区限制不当 | — | C/C++ 缓冲区溢出 |
| 21 | CWE-476 | NULL 指针解引用 | — | 未检查返回值 |
| 22 | CWE-798 | 硬编码凭据 | A02 加密失效 | SECRET_KEY = "..."、password = "..." |
| 23 | CWE-190 | 整数溢出 | — | 数值计算未检查边界 |
| 24 | CWE-400 | 资源消耗不受控 | A04 不安全设计 | 无速率限制、无分页上限 |
| 25 | CWE-306 | 关键功能缺失认证 | A07 认证失败 | 管理接口、密码重置无认证 |

## v1.6 新增 CWE 条目

| CWE ID | 名称 | OWASP 映射 | 代码审计关注点 |
|--------|------|-----------|---------------|
| CWE-538 | 文件/目录信息暴露 | A05 配置错误 | `.svn`/`.git`/`.DS_Store` 等版本控制目录对外可访问 |
| CWE-548 | 目录列表暴露 | A05 配置错误 | Nginx `autoindex on`、Apache `Options +Indexes` |
| CWE-459 | 不完整清理 | A04 不安全设计 | 临时文件/导出文件未定时清理，可被他人访问 |
| CWE-1395 | 依赖项漏洞 | A06 组件漏洞 | ActiveMQ/Harbor/Flink/Nacos/Log4j/Fastjson 等已知 CVE 组件 |
| CWE-215 | 通过调试信息暴露 | A05 配置错误 | DEBUG 模式开启、Spring Actuator /env /heapdump 暴露、Swagger 生产环境未关闭 |

## 高频 CWE 与代码模式

### CWE-79: XSS

**Python/Flask**:
```python
# 危险
return render_template_string('<div>' + user_input + '</div>')
Markup(user_input)
```

**JavaScript**:
```javascript
element.innerHTML = userInput;
document.write(userInput);
$(selector).html(userInput);
```

**React**:
```jsx
<div dangerouslySetInnerHTML={{__html: userInput}} />
```

**Vue**:
```vue
<div v-html="userInput"></div>
```

### CWE-89: SQL 注入

**通用检测模式**（正则）:
```
execute\(f["']|execute\(["'].*%s|execute\(["'].*\.format\(|\.query\(.*\+|\.raw\(.*\+|createQuery\(.*\+
```

### CWE-78: 命令注入

**检测关键词**:
```
os.system(|os.popen(|subprocess.call(.*shell=True|subprocess.Popen(.*shell=True|exec.Command("sh".*-c
```

### CWE-862/CWE-863: 访问控制

**检查方法**:
1. 列出所有路由定义
2. 检查每条路由是否有认证中间件/装饰器
3. 对需要资源级权限的接口，检查查询条件是否包含 user_id 过滤

### CWE-798: 硬编码凭据

**检测正则**:
```
(password|passwd|secret|api_key|apikey|access_token|private_key|SECRET_KEY)\s*[=:]\s*["'][^"']{8,}["']
```

### CWE-502: 不安全反序列化

**危险函数**:
- Python: `pickle.loads()`, `yaml.load()`, `marshal.loads()`
- Java: `ObjectInputStream.readObject()`, `XMLDecoder`
- PHP: `unserialize()`
- Node: `node-serialize`

### CWE-918: SSRF

**检查要点**:
- 接受 URL 参数的接口
- 是否校验 URL scheme（仅允许 http/https）
- 是否阻止内网 IP 段：`127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- 是否阻止云元数据端点：`169.254.169.254`

## CVSS 3.1 评分速查

| 场景 | 典型 CVSS | 向量示例 |
|------|----------|---------|
| 未认证 RCE | 9.8 | AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H |
| 未认证 SQL 注入 | 9.1 | AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N |
| 存储型 XSS | 8.1 | AV:N/AC:L/PR:L/UI:R/S:C/C:H/I:L/A:N |
| IDOR 数据泄露 | 6.5 | AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N |
| CSRF | 6.1 | AV:N/AC:L/PR:N/UI:R/S:C/C:N/I:L/A:N |
| 信息泄露 | 5.3 | AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N |
| 缺少安全头 | 3.7 | AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:N/A:N |
| DEBUG 模式开启 | 7.5 | AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N |
| 硬编码密钥 | 7.5 | AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N |

## 合规性映射

| 安全问题 | PCI-DSS | SOC 2 | ISO 27001 |
|----------|---------|-------|-----------|
| SQL 注入 | Req 6.5.1 | CC6.1 | A.14.2.5 |
| XSS | Req 6.5.7 | CC6.1 | A.14.2.5 |
| 弱加密 | Req 4.1 | CC6.1 | A.10.1.1 |
| 访问控制 | Req 7.1 | CC6.3 | A.9.4.1 |
| 审计日志 | Req 10 | CC7.2 | A.12.4.1 |
| 硬编码凭据 | Req 2.1 | CC6.1 | A.9.4.3 |
| 组件漏洞 | Req 6.2 | CC7.1 | A.12.6.1 |
