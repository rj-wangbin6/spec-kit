# 前端开发规范

**Author:** 皮皮芳

---

## 1. 项目强制规范 (⚠️ 必须遵守)

### 1.1 性能优化 🔴

**规则**: 避免不必要的重渲染和性能问题。

**错误示例:**
```javascript
// ❌ 严重问题: 循环中调用API
async function loadUserDetails(userIds) {
    for (const userId of userIds) {
        // 每次循环都发起一次HTTP请求!
        const user = await api.getUserById(userId);
        // 处理逻辑...
    }
}

// ❌ 严重问题: 未使用useMemo导致重复计算
function ExpensiveComponent({ data }) {
    // 每次渲染都会重新计算!
    const processedData = data.map(item => complexCalculation(item));
    return <div>{processedData}</div>;
}
```

**正确示例:**
```javascript
// ✅ 正确: 批量请求
async function loadUserDetails(userIds) {
    const users = await api.batchGetUsers(userIds);
    return users;
}

// ✅ 正确: 使用useMemo缓存计算结果
function ExpensiveComponent({ data }) {
    const processedData = useMemo(
        () => data.map(item => complexCalculation(item)),
        [data]
    );
    return <div>{processedData}</div>;
}
```

**影响**: 
- 循环API调用会导致网络阻塞和响应时间增加
- 未优化的重渲染会导致页面卡顿

---

### 1.2 状态管理 🔴

**规则**: 避免直接修改状态，使用不可变数据更新。

**错误示例:**
```javascript
// ❌ 严重问题: 直接修改状态
function updateUser(userId, newData) {
    const user = users.find(u => u.id === userId);
    user.name = newData.name; // 直接修改!
    setUsers(users); // React可能不会重新渲染
}

// ❌ 严重问题: 未考虑异步状态更新
function incrementCounter() {
    setCount(count + 1);
    setCount(count + 1); // 第二次更新会覆盖第一次!
}
```

**正确示例:**
```javascript
// ✅ 正确: 不可变更新
function updateUser(userId, newData) {
    setUsers(users.map(user =>
        user.id === userId ? { ...user, ...newData } : user
    ));
}

// ✅ 正确: 使用函数式更新
function incrementCounter() {
    setCount(prev => prev + 1);
    setCount(prev => prev + 1);
}
```

---

### 1.3 安全性 🔴

**规则**: 防止XSS攻击和敏感信息泄露。

**错误示例:**
```javascript
// ❌ 严重问题: 直接渲染用户输入 (XSS风险)
function UserComment({ comment }) {
    return <div dangerouslySetInnerHTML={{ __html: comment }} />;
}

// ❌ 严重问题: 敏感信息暴露在前端
const config = {
    apiKey: 'sk-1234567890abcdef', // API密钥不应在前端!
    secretToken: 'secret123'
};
```

**正确示例:**
```javascript
// ✅ 正确: 使用文本渲染或DOMPurify清理
import DOMPurify from 'dompurify';

function UserComment({ comment }) {
    // 方案1: 直接渲染文本
    return <div>{comment}</div>;
    
    // 方案2: 使用DOMPurify清理HTML
    const cleanHTML = DOMPurify.sanitize(comment);
    return <div dangerouslySetInnerHTML={{ __html: cleanHTML }} />;
}

// ✅ 正确: 敏感配置放在后端环境变量
const config = {
    apiUrl: process.env.REACT_APP_API_URL, // 只暴露必要的公开信息
};
```

---

## 2. 建议规范 (🟡 强烈建议)

### 2.1 组件设计

**规则**: 组件应该职责单一，可复用。

```javascript
// ✅ 好的组件设计
function UserCard({ user, onEdit }) {
    return (
        <div className="user-card">
            <Avatar src={user.avatar} />
            <UserInfo user={user} />
            <Button onClick={() => onEdit(user)}>编辑</Button>
        </div>
    );
}

// ❌ 组件职责过多
function UserManagement() {
    // 同时处理: 数据获取、状态管理、UI渲染、业务逻辑
    // 应该拆分成多个组件
}
```

---

### 2.2 错误处理

**规则**: 使用ErrorBoundary捕获组件错误。

```javascript
// ✅ 使用ErrorBoundary
class ErrorBoundary extends React.Component {
    state = { hasError: false };

    static getDerivedStateFromError(error) {
        return { hasError: true };
    }

    componentDidCatch(error, errorInfo) {
        console.error('Component error:', error, errorInfo);
        // 发送错误日志到监控系统
    }

    render() {
        if (this.state.hasError) {
            return <ErrorFallback />;
        }
        return this.props.children;
    }
}
```

---

### 2.3 TypeScript类型安全

**规则**: 使用TypeScript提供类型安全。

```typescript
// ✅ 明确的类型定义
interface User {
    id: number;
    name: string;
    email: string;
    role: 'admin' | 'user' | 'guest';
}

function updateUser(user: User): Promise<User> {
    return api.put(`/users/${user.id}`, user);
}

// ❌ 使用any类型
function updateUser(user: any): Promise<any> {
    // 失去类型检查
}
```

---

## 3. 代码风格 (🔵 提升可维护性)

### 3.1 命名规范

- 组件名: PascalCase (`UserCard`, `ProductList`)
- 函数/变量: camelCase (`getUserInfo`, `isLoading`)
- 常量: UPPER_SNAKE_CASE (`MAX_RETRY_COUNT`)
- 私有变量: 下划线前缀 (`_internalState`)

### 3.2 文件组织

```
src/
├── components/        # 通用组件
│   ├── Button/
│   │   ├── Button.tsx
│   │   ├── Button.test.tsx
│   │   └── Button.module.css
├── features/         # 功能模块
│   ├── user/
│   │   ├── UserList.tsx
│   │   ├── UserDetail.tsx
│   │   └── userSlice.ts
├── hooks/           # 自定义Hooks
├── utils/           # 工具函数
└── types/           # TypeScript类型定义
```

---

## 4. 审查重点

### 4.1 必须检查项 (🔴)
- [ ] 循环中是否有API调用
- [ ] 是否存在XSS漏洞
- [ ] 敏感信息是否暴露在前端
- [ ] 状态更新是否正确
- [ ] 是否有内存泄漏风险

### 4.2 建议检查项 (🟡)
- [ ] 组件是否职责单一
- [ ] 是否有ErrorBoundary
- [ ] 是否使用TypeScript类型
- [ ] 性能优化是否到位
- [ ] 代码是否可复用

### 4.3 优化建议项 (🔵)
- [ ] 命名是否规范
- [ ] 文件组织是否合理
- [ ] 注释是否充分
- [ ] 测试覆盖率

前端CR审查检查表
1. 命名语义化，无硬编码、无测试残留代码
   要求：变量/函数/文件语义清晰；禁止硬编码IP、接口、文案；删除console.log、debugger、测试注释、临时代码
   正确示例：
   // 语义化命名
   const tableData = [];
   const getUserInfo = () => {};
   // 常量统一管理
   const IFRAME_BASE_URL = "http://192.168.1.xx";
   错误示例：
   // 无意义命名
   const a = [];
   const fn1 = () => {};
   // 硬编码
   let url = "http://192.168.1.100:8080/home";
   // 测试残留
   debugger
   console.log("测试接口返回");
   // 注释残留测试代码
   // function testDemo(){}
------------------------------------------------------------------------------------------------
2. 组件拆分合理，单文件不臃肿
   要求：单一职责原则；弹窗、表格、表单、独立模块抽子组件；单Vue文件代码建议≤500行
   正确示例：
   components/
   ├─ IframeEmbed/       // iframe内嵌单独组件
   ├─ SearchForm/        // 搜索栏抽离
   └─ TableList/         // 表格模块抽离
   错误示例：
- 一个页面内同时写：搜索+表单+弹窗+iframe+大量业务逻辑
- 复制粘贴重复代码，不抽公共组件/工具方法
------------------------------------------------------------------------------------------------
3. Props / 异步 / 接口 有校验、异常捕获
   要求：Props必做类型、默认值、校验；所有异步、接口请求必须try/catch；禁止裸写Promise无捕获
   正确示例：
<script setup>
const props = defineProps({
  iframeUrl: {
    type: String,
    required: true,
    default: ""
  }
})

// 接口统一捕获异常
const loadData = async () => {
  try {
    loading.value = true;
    const res = await api.getDetail();
  } catch (error) {
    ElMessage.error("数据加载失败");
  } finally {
    loading.value = false;
  }
};
</script>
错误示例：
// props无校验、无默认值
const props = defineProps(["iframeUrl"])

// 接口无异常捕获
const loadData = async () => {
const res = await api.getDetail()
}
------------------------------------------------------------------------------------------------
4. 样式 scoped，无全局污染
   要求：业务页面/组件样式必须加 scoped；禁止滥用!important、全局通配符、穿透污染全局
   正确示例：
<style scoped>
.iframe-wrap {
  width: 100%;
  height: 600px;
}
/* 深度修改第三方组件使用:deep() */
:deep(.el-card) {
  border-radius: 4px;
}
</style>
错误示例：
<style>
/* 无scoped，全局污染 */
.iframe-wrap{ }
* { margin:0; }
.el-input { width:100% !important; }
<style>
------------------------------------------------------------------------------------------------
5. 列表 key、渲染规则合规
要求：v-for 绑定唯一key；禁止用index作为高频更新列表key；合理区分v-if/v-show
正确示例：
<div v-for="item in tableList" :key="item.id">
  {{ item.name }}
</div>

<!-- 少量渲染用v-if，频繁切换用v-show -->
<iframe v-show="showIframe" :src="iframeUrl"></iframe>
错误示例：
<!-- 无key / 滥用index key -->
<div v-for="item in list">{{ item.title }}</div>
<div v-for="(item,index) in list" :key="index"></div>

<!-- v-if 和 v-for 混用且v-if在前 -->
<div v-if="show" v-for="item in list"></div>
------------------------------------------------------------------------------------------------
6. 定时器 / 事件 / iframe 监听 销毁处理
要求：组件卸载时，清除定时器、监听事件、iframe消息监听，杜绝内存泄漏
正确示例：
let timer = null;
const messageFn = (e) => {}

onMounted(() => {
  timer = setInterval(() => {}, 3000);
  window.addEventListener("message", messageFn);
})

// 强制销毁
onUnmounted(() => {
  clearInterval(timer);
  window.removeEventListener("message", messageFn);
})
错误示例：
- 开启定时器、addEventListener、iframe监听，页面销毁不清除
- 多页面复用同一全局定时器，造成重复执行
------------------------------------------------------------------------------------------------
7. 跨域、iframe、第三方嵌入 做安全限制
要求：iframe跨域通信必须校验origin白名单；禁止无限制内嵌陌生内网/外网IP；限制嵌入权限
正确示例：
// 跨域message严格白名单校验
const safeOriginList = ["http://192.168.1.100:8080"]
window.addEventListener("message", (e) => {
  if (!safeOriginList.includes(e.origin)) return;
  // 业务逻辑
})
错误示例：
// 不做源校验，全量接收所有跨域消息，存在安全风险
window.addEventListener("message", (e) => {
  handleData(e.data)
})

<!-- 直接裸嵌未知IP，无任何安全限制 -->
<iframe src="http://陌生IP/xxx"></iframe>
------------------------------------------------------------------------------------------------
8. 空数据、报错、加载状态 完整兜底
要求：接口加载中loading、无数据空状态、接口异常错误提示、白屏兜底全覆盖
正确示例：
<el-loading v-loading="loading">
  <div v-if="tableList.length === 0" class="empty-box">
    暂无数据
  </div>
  <div v-else>
<!-- 列表渲染 -->
  </div>
</el-loading>
错误示例：
- 接口请求无loading，用户无感知
- 直接渲染list[0].name，不做空判断，报错白屏
- 接口报错无提示，页面空白无反馈
------------------------------------------------------------------------------------------------