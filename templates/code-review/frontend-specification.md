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

---

**版本**: 1.0  
**更新日期**: 2026-01-08  
**维护者**: 皮皮芳
