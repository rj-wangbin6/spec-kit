# HTML 报告模板（v1.6）

生成报告时使用以下完整 HTML 模板。将模板中的 `{{变量}}` 替换为实际值。

## 完整模板

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OWASP 安全审计报告 — {{项目名称}}</title>
  <style>
    :root {
      --bg: #f7f8fa;
      --card: #ffffff;
      --text: #1f2a37;
      --muted: #667085;
      --critical: #7a271a;
      --high: #d92d20;
      --medium: #dc6803;
      --low: #175cd3;
      --info: #667085;
      --positive: #027a48;
      --border: #e4e7ec;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Microsoft YaHei", "Segoe UI", -apple-system, sans-serif;
      background: radial-gradient(1200px 600px at 10% 0%, #fff1f1 0%, var(--bg) 55%), var(--bg);
      color: var(--text);
      line-height: 1.6;
    }
    .wrap { max-width: 1120px; margin: 32px auto; padding: 0 20px 60px; }
    h1 { margin: 0 0 6px; color: #7a271a; font-size: 28px; font-weight: 700; }
    h2 { font-size: 20px; margin: 32px 0 12px; color: var(--text); border-bottom: 2px solid var(--border); padding-bottom: 6px; }
    h3 { margin: 0 0 10px; font-size: 17px; }
    .meta { color: var(--muted); margin-bottom: 24px; font-size: 14px; }
    .meta strong { color: var(--text); }

    /* 统计面板 */
    .badge-row { display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 24px; }
    .badge {
      display: flex; flex-direction: column; align-items: center;
      background: var(--card); border: 1px solid var(--border);
      border-radius: 10px; padding: 14px 24px; min-width: 100px;
      box-shadow: 0 2px 8px rgba(16,24,40,.06);
    }
    .badge .num { font-size: 32px; font-weight: 700; }
    .badge .label { font-size: 12px; color: var(--muted); margin-top: 2px; }
    .badge.critical .num { color: var(--critical); }
    .badge.high .num  { color: var(--high); }
    .badge.medium .num{ color: var(--medium); }
    .badge.low .num   { color: var(--low); }
    .badge.total .num { color: var(--text); }
    .badge.positive .num { color: var(--positive); }

    /* 概要 */
    .summary {
      background: #fff6f6; border: 1px solid #ffd3d3;
      border-left: 5px solid var(--high); border-radius: 10px;
      padding: 14px 18px; margin-bottom: 26px; font-size: 14px;
    }
    .summary.ok {
      background: #f0fdf4; border-color: #a7f3d0;
      border-left-color: var(--positive);
    }

    /* STRIDE 折叠 */
    details { margin: 16px 0; }
    details summary {
      cursor: pointer; font-weight: 600; font-size: 15px;
      padding: 10px 14px; background: var(--card); border: 1px solid var(--border);
      border-radius: 8px; user-select: none;
    }
    details[open] summary { border-radius: 8px 8px 0 0; }
    details .detail-content {
      background: var(--card); border: 1px solid var(--border); border-top: 0;
      border-radius: 0 0 8px 8px; padding: 14px 18px; font-size: 14px;
    }

    /* 漏洞卡片 */
    .finding {
      background: var(--card); border: 1px solid var(--border);
      border-left-width: 6px; border-radius: 10px;
      padding: 18px 20px; margin: 16px 0;
      box-shadow: 0 4px 16px rgba(16,24,40,.05);
    }
    .finding.critical { border-left-color: var(--critical); }
    .finding.high   { border-left-color: var(--high); }
    .finding.medium { border-left-color: var(--medium); }
    .finding.low    { border-left-color: var(--low); }
    .finding.info   { border-left-color: var(--info); }

    .sev {
      display: inline-block; color: #fff; border-radius: 6px;
      padding: 2px 10px; font-size: 12px; margin-right: 8px;
      vertical-align: middle; font-weight: 600;
    }
    .sev.critical { background: var(--critical); }
    .sev.high   { background: var(--high); }
    .sev.medium { background: var(--medium); }
    .sev.low    { background: var(--low); }
    .sev.info   { background: var(--info); }

    .cvss {
      display: inline-block; background: #f3f4f6; color: #374151;
      border-radius: 4px; padding: 1px 8px; font-size: 12px;
      margin-left: 4px; font-family: monospace;
    }

    /* 数据流路径 */
    .dataflow {
      background: #f0f4ff; border: 1px solid #c7d2fe;
      border-radius: 6px; padding: 8px 12px; margin: 8px 0;
      font-size: 13px; font-family: monospace; color: #3730a3;
    }

    table { width: 100%; border-collapse: collapse; margin: 10px 0 16px; font-size: 14px; }
    th, td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; vertical-align: top; }
    th { background: #f9fafb; width: 110px; font-weight: 600; white-space: nowrap; }

    pre {
      background: #111827; color: #f9fafb; border-radius: 8px;
      padding: 14px 16px; overflow-x: auto; font-size: 13px;
      line-height: 1.55; margin: 10px 0;
    }
    code { font-family: "Cascadia Code", Consolas, monospace; }

    .tag {
      display: inline-block; background: #f3f4f6; color: #374151;
      border-radius: 4px; padding: 1px 7px; font-size: 12px;
      margin: 2px; border: 1px solid #e5e7eb;
    }
    .cwe-tag {
      display: inline-block; background: #fef3c7; color: #92400e;
      border-radius: 4px; padding: 1px 7px; font-size: 12px;
      margin: 2px; border: 1px solid #fcd34d;
    }

    /* 正面发现 */
    .positive-finding {
      background: #f0fdf4; border: 1px solid #a7f3d0;
      border-left: 4px solid var(--positive);
      border-radius: 8px; padding: 12px 16px; margin: 8px 0;
      font-size: 14px;
    }

    /* 合规表 */
    .compliance-table th { background: #1e3a5f; color: #fff; }
    .compliance-table td { font-size: 13px; }

    .priority-table th { background: #1f2937; color: #fff; }
    .priority-table tr:nth-child(even) td { background: #f9fafb; }

    .no-finding { color: var(--muted); font-style: italic; padding: 12px 0; }
    footer { color: var(--muted); font-size: 12px; margin-top: 40px; text-align: center; }
  </style>
</head>
<body>
<div class="wrap">

  <h1>🔒 OWASP 安全审计报告</h1>
  <div class="meta">
    项目：<strong>{{项目名称}}</strong> &nbsp;|&nbsp;
    技术栈：<strong>{{技术栈}}</strong> &nbsp;|&nbsp;
    审计模式：<strong>{{审计模式}}</strong><br>
    审计时间：{{审计时间}} &nbsp;|&nbsp;
    Skill 版本：{{skill_version}}
  </div>

  <!-- 统计徽章 -->
  <div class="badge-row">
    <div class="badge total"><span class="num">{{总漏洞数}}</span><span class="label">漏洞总数</span></div>
    <div class="badge critical"><span class="num">{{严重数}}</span><span class="label">🟣 严重</span></div>
    <div class="badge high">  <span class="num">{{高危数}}</span><span class="label">🔴 高危</span></div>
    <div class="badge medium"><span class="num">{{中危数}}</span><span class="label">🟠 中危</span></div>
    <div class="badge low">   <span class="num">{{低危数}}</span><span class="label">🔵 低危</span></div>
    <div class="badge">       <span class="num">{{信息数}}</span><span class="label">⚪ 信息</span></div>
    <div class="badge positive"><span class="num">{{正面发现数}}</span><span class="label">✅ 正面发现</span></div>
    <div class="badge">       <span class="num">{{扫描接口数}}</span><span class="label">扫描接口</span></div>
  </div>

  <!-- 扫描概要 -->
  <div class="summary">
    <strong>扫描概要：</strong>
    共扫描 <strong>{{扫描接口数}}</strong> 个路由/接口，
    覆盖 OWASP Top 10 + CWE Top 25 + API 安全，
    发现 <strong>{{总漏洞数}}</strong> 个安全风险
    （严重 {{严重数}} / 高危 {{高危数}} / 中危 {{中危数}} / 低危 {{低危数}} / 信息 {{信息数}}）。
    <div style="margin-top:8px;color:var(--muted);font-size:13px;">
      涉及漏洞类型：{{漏洞类型标签列表}}
    </div>
  </div>

  <!-- STRIDE 威胁建模 -->
  <h2>威胁建模</h2>
  <details>
    <summary>🎯 STRIDE 威胁分析（点击展开）</summary>
    <div class="detail-content">
      <table>
        <tr><th>S — 欺骗</th><td>{{Spoofing 分析结论}}</td></tr>
        <tr><th>T — 篡改</th><td>{{Tampering 分析结论}}</td></tr>
        <tr><th>R — 否认</th><td>{{Repudiation 分析结论}}</td></tr>
        <tr><th>I — 泄露</th><td>{{InfoDisclosure 分析结论}}</td></tr>
        <tr><th>D — 拒绝服务</th><td>{{DoS 分析结论}}</td></tr>
        <tr><th>E — 提权</th><td>{{EoP 分析结论}}</td></tr>
      </table>
      <p><strong>信任边界：</strong></p>
      <pre><code>{{信任边界描述}}</code></pre>
    </div>
  </details>

  <h2>漏洞发现列表</h2>

  <!-- 对每个漏洞重复以下 .finding 块 -->

  <div class="finding critical">
    <h3>
      <span class="sev critical">严重</span>
      {{漏洞标题}}
      <span class="cvss">CVSS {{评分}}</span>
    </h3>
    <table>
      <tr><th>文件</th><td><code>{{文件路径}}</code></td></tr>
      <tr><th>行号</th><td>{{行号}}</td></tr>
      <tr><th>漏洞类型</th><td>{{漏洞类型}}</td></tr>
      <tr><th>CWE</th><td><span class="cwe-tag">{{CWE-XXX}}</span> {{CWE名称}}</td></tr>
      <tr><th>OWASP</th><td>{{OWASP分类}}</td></tr>
      <tr><th>CVSS 向量</th><td><code>{{CVSS:3.1/AV:N/AC:L/...}}</code></td></tr>
    </table>
    <p><strong>数据流路径：</strong></p>
    <div class="dataflow">{{Source}} → {{中间变量}} → {{Sink}}</div>
    <p><strong>问题说明：</strong>{{详细描述，含危害和攻击场景}}</p>
    <p><strong>漏洞代码：</strong></p>
    <pre><code>{{漏洞代码片段}}</code></pre>
    <p><strong>修复建议：</strong></p>
    <pre><code>{{修复后代码}}</code></pre>
    <p><strong>预防措施：</strong>{{框架特定建议}}</p>
  </div>

  <!-- high/medium/low/info 同样格式，级别不同（低危和信息级可省略 CVSS） -->

  <!-- 正面发现 -->
  <h2>✅ 正面安全发现</h2>
  <div class="positive-finding">
    ✅ {{正面发现描述，如：使用了 bcrypt 存储密码}}
  </div>
  <!-- 重复多个 .positive-finding -->

  <!-- 修复优先级 -->
  <h2>修复优先级建议</h2>
  <table class="priority-table">
    <thead>
      <tr>
        <th>#</th>
        <th>优先级</th>
        <th>CWE</th>
        <th>漏洞</th>
        <th>文件</th>
        <th>建议操作</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>1</td>
        <td><span class="sev critical">严重</span></td>
        <td><span class="cwe-tag">CWE-XXX</span></td>
        <td>{{漏洞标题}}</td>
        <td><code>{{文件路径}}</code></td>
        <td>{{一句话修复建议}}</td>
      </tr>
    </tbody>
  </table>

  <!-- 合规性参考 -->
  <h2>合规性参考</h2>
  <table class="compliance-table">
    <thead>
      <tr>
        <th>漏洞类型</th>
        <th>PCI-DSS 4.0</th>
        <th>SOC 2</th>
        <th>ISO 27001</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>{{漏洞类型}}</td>
        <td>{{PCI-DSS 条款}}</td>
        <td>{{SOC 2 控制项}}</td>
        <td>{{ISO 27001 条款}}</td>
      </tr>
    </tbody>
  </table>

  <footer>
    由 GitHub Copilot code-audit Skill v1.6 自动生成 &nbsp;|&nbsp;
    OWASP Top 10:2021 + CWE Top 25:2024 + OWASP API Top 10 &nbsp;|&nbsp;
    STRIDE 威胁建模
  </footer>
</div>
</body>
</html>
```

## 变量说明

| 变量占位符 | 替换为 |
|-----------|--------|
| `{{项目名称}}` | 工作区目录名或用户指定的项目名 |
| `{{技术栈}}` | 如 "Python/Flask + PostgreSQL + React" |
| `{{审计模式}}` | "全量审计" / "增量审计" / "定向审计" |
| `{{审计时间}}` | `YYYY-MM-DD HH:MM:SS` 格式 |
| `{{skill_version}}` | `config.yaml` 中的 `skill_version` |
| `{{总漏洞数}}` | 所有漏洞发现数量 |
| `{{严重数}}`/`{{高危数}}`/`{{中危数}}`/`{{低危数}}`/`{{信息数}}` | 各级别数量 |
| `{{正面发现数}}` | 正面安全发现数量 |
| `{{扫描接口数}}` | 扫描到的路由/端点总数 |
| `{{漏洞类型标签列表}}` | `<span class="tag">未授权</span><span class="cwe-tag">CWE-862</span>` |
| `{{文件路径}}` | 相对于项目根目录的路径 |
| `{{行号}}` | 如 `第 42–45 行` |
| `{{CWE-XXX}}` | CWE 编号，如 `CWE-89` |
| `{{OWASP分类}}` | 如 `A03: Injection` |
| `{{CVSS 评分/向量}}` | 如 `9.1` / `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N` |
| `{{Source → Sink}}` | 数据流路径 |

## 未发现任何漏洞时

```html
<div class="summary ok">
  ✅ <strong>未发现安全漏洞。</strong>
  共扫描 {{扫描接口数}} 个接口，覆盖 OWASP Top 10 + CWE Top 25，未发现明确的安全风险。
  建议保持依赖更新并定期复查。
</div>
<p class="no-finding">本次审计未发现需要报告的漏洞。</p>
```
