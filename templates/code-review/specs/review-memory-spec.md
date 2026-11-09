# 跨会话记忆机制 — 完整规格

本文档定义代码评审编排器跨会话记忆的数据模型、读写逻辑和淘汰策略。编排器按需引用本文件，子代理在需要历史记忆辅助判断时也应读取本文件。

---

## 记忆存储位置

```
<project_root>/docs/review-results/.review-memory/
  ├── module-patterns.json       # 模块级问题模式：哪些模块反复出同类问题
  ├── rule-effectiveness.json    # 规则有效性统计：命中率、误报率、开发者认可度
  ├── developer-profiles.json    # 开发者问题倾向：哪些开发者在哪些规则上容易出问题
  └── false-positive-log.json   # 历史误报记录：哪些场景容易被误判
```

---

## 数据模型

### module-patterns.json

记录模块级别的问题模式和热点区域：

```json
{
  "src/order/service/": {
    "hot_issues": ["空指针", "事务范围不当"],
    "issue_count": 7,
    "last_5_sessions": ["001-20260409", "002-20260415", "003-20260501", "004-20260520", "005-20260601"],
    "recurring_count": 3,
    "last_seen": "2026-06-01",
    "note": "订单服务是高频问题区，重点关注 null 校验和事务边界"
  }
}
```

**字段说明**：
- `hot_issues`：该模块高频出现的问题类型（保留前 5 个）
- `issue_count`：累计问题数
- `last_5_sessions`：最近 5 次涉及该模块的评审会话 ID
- `recurring_count`：连续出现同类问题的次数
- `last_seen`：最近一次出现问题的日期
- `note`：人工可读的备注

### rule-effectiveness.json

记录每条规则的历史表现，辅助判断规则可信度：

```json
{
  "R03-空指针检查": {
    "total_triggers": 45,
    "confirmed": 38,
    "false_positive": 5,
    "severity_disputed": 2,
    "precision": 0.844,
    "common_fp_scenarios": ["DTO 转换层", "Builder 模式链式调用"],
    "last_updated": "2026-06-01"
  }
}
```

**字段说明**：
- `total_triggers`：规则历史总触发次数
- `confirmed`：被确认为有效问题的次数
- `false_positive`：被确认为误报的次数
- `severity_disputed`：严重度被调整的次数
- `precision`：精确度 = confirmed / total_triggers
- `common_fp_scenarios`：常见误报场景描述列表
- `last_updated`：最近更新日期

### developer-profiles.json

记录开发者的问题倾向，辅助评审重点关注：

```json
{
  "zhangsan@example.com": {
    "review_count": 8,
    "top_issues": ["并发安全", "异常处理遗漏"],
    "improvement_trend": "improving",
    "last_reviewed": "2026-06-01"
  }
}
```

**字段说明**：
- `review_count`：该开发者被评审的总次数
- `top_issues`：出现频率最高的问题类型（保留前 5 个）
- `improvement_trend`：趋势判断（`improving` / `stable` / `declining`），基于近 5 次评审的问题数变化
- `last_reviewed`：最近一次被评审的日期

### false-positive-log.json

记录被确认为误报的案例，辅助 validator 和 rule-checker 避免重蹈覆辙：

```json
{
  "entries": [
    {
      "session_id": "003-20260501-reports",
      "rule_id": "R03",
      "code_pattern": "Optional.orElse() 返回值直接调用方法",
      "reason": "Optional 已确保非空，rule-checker 未识别 Optional 语义",
      "added_at": "2026-05-01"
    }
  ]
}
```

**字段说明**：
- `session_id`：发现误报的评审会话 ID
- `rule_id`：触发误报的规则编号
- `code_pattern`：导致误报的代码模式简述
- `reason`：误报原因分析
- `added_at`：记录添加日期

---

## 记忆读取详细逻辑

### 读取时机

阶段 0 步骤 4，编排器检查 `.review-memory/` 目录是否存在。

### 读取后写入 `00-session-state.json` 的 `memory_context` 字段

```json
{
  "memory_context": {
    "has_memory": true,
    "hot_modules": ["src/order/service/", "src/payment/"],
    "low_precision_rules": ["R12-日志规范"],
    "recent_fp_patterns": [
      {"rule_id": "R03", "code_pattern": "Optional.orElse() 返回值直接调用方法"}
    ],
    "developer_hot_issues": {"zhangsan@example.com": ["并发安全", "异常处理遗漏"]}
  }
}
```

### 传递给子代理的方式

| 消费阶段 | 传入内容 | 来源字段 |
|---------|---------|---------|
| 阶段 1 precheck | 高频问题模块列表 | `memory_context.hot_modules` |
| 阶段 5 rule-checker | 该规则的历史误报场景 | `memory_context.recent_fp_patterns` 中匹配当前 rule_id 的条目 |
| 阶段 5 rule-checker | 被审查开发者的高频问题类型 | `memory_context.developer_hot_issues` |
| 阶段 5.5 validator | 低精确度规则列表 + 历史误报模式 | `memory_context.low_precision_rules` + `memory_context.recent_fp_patterns` |

---

## 记忆回写详细逻辑

### 回写时机

阶段 6.5，报告收口完成后、远程同步前。

### 增量更新规则

#### module-patterns.json 更新

1. 从 `08-final-review-report.md` 提取所有问题涉及的模块路径
2. 对每个模块：
   - 若已存在：`issue_count += 本次该模块问题数`，更新 `hot_issues`（合并后取频率前 5），追加 `last_5_sessions`（保留最近 5 个），更新 `last_seen`
   - 若不存在：创建新条目
3. 若某模块连续 3 次（`last_5_sessions` 中最近 3 个）出现同类问题，更新 `recurring_count`

#### rule-effectiveness.json 更新

1. 从 `rule/06-rule-index.md` 提取本次触发的所有规则编号
2. 对每条触发的规则：`total_triggers += 1`
3. 若 `09-validation-result.md` 标记某规则结论为"高嫌疑"或"建议移除"：`false_positive += 1`
4. 其余情况：`confirmed += 1`
5. 重新计算 `precision`
6. 若本次有新的误报场景，追加到 `common_fp_scenarios`（去重，最多保留 5 条）
7. 更新 `last_updated`

#### developer-profiles.json 更新

1. 从 `02-change-collection.md` 提取被审查开发者邮箱/用户名
2. `review_count += 1`
3. 从 `08-final-review-report.md` 提取本次问题类型分布，合并到 `top_issues`（取频率前 5）
4. 比较近 5 次评审的问题数趋势，更新 `improvement_trend`
5. 更新 `last_reviewed`

#### false-positive-log.json 更新

1. 从 `09-validation-result.md` 的"高嫌疑/建议移除"条目中提取
2. 对每个条目，创建新 entry：
   - `session_id`：当前会话 ID
   - `rule_id`：对应规则编号
   - `code_pattern`：从 validator 的判定依据中提取代码模式描述
   - `reason`：从 validator 的判定依据中提取误报原因
   - `added_at`：当前日期

### 淘汰策略

- 单个 JSON 文件超过 500 条记录时，按 `last_seen`（module-patterns）或 `last_updated`（rule-effectiveness）或 `last_reviewed`（developer-profiles）或 `added_at`（false-positive-log）排序
- 保留最近 200 条，淘汰其余
- 淘汰在回写完成后执行，不影响本次写入

---

## 使用约束

- 记忆只作为辅助参考，不能替代实际代码阅读和规则判定
- 记忆中记录的"高频问题"不意味着本次一定存在同类问题，不能据此凭空制造问题
- 记忆中的"历史误报"不意味着本次同类结论一定是误报，需结合当前代码上下文判断
- 记忆中的开发者画像不能作为歧视性依据，只用于聚焦审查注意力
- 记忆读取失败不阻塞任何阶段
- 记忆回写失败不阻塞阶段 7 远程同步
