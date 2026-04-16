# issue-fetch

> 一个用于查询 Gerrit 代码检查结果的 VS Code Copilot 技能

## 版本信息

| 字段 | 内容 |
|------|------|
| 版本 | 0.0.1 |
| 发布日期 | 2026-03-18 |
| 许可证 | MIT |


## 👥 作者
| Name           | Domain               | Responsibilities                                                  |
|----------------|----------------------|-------------------------------------------------------------------|
| lijianhua   |   System Engineer      | Requirement Analysis,System Design,Risk Assessment              |
| wangbin6    | Technical Consultant | Technical Solution Review, technical Guidance                     |
| huangfang     | AI Enhancement       | model selection, prompt optimization     |
| pancr | Engineering          | CI pipeline, automated testing, deployment scripts             |


## 技能概述

在 VS Code 中通过 Gerrit 的 `changeNumber` 查询gerrit代码检查检出的问题项，以便在 Copilot 中自动化分析和修复代码质量问题。

支持自动从本地 Gerrit 仓库最后一次提交中提取 `Change-Id` 并解析 `changeNumber`，无需手动输入。

## 功能特性

| 功能 | 说明 |
|------|------|
| 自动解析 changeNumber | 从本地 Git 仓库最后一次提交自动提取，无需手动填写 |
| 查询 Coverity 问题 | 通过 changeNumber 获取完整的静态分析检出报告 |
| 问题定位 | 提供文件路径、行号、函数名等精确定位信息 |
| 推理步骤展示 | 展示 detailIssue 完整推理链，辅助理解问题根因 |
| 错误处理 | 网络失败、参数错误均有统一提示，不重试 |
| 开箱即用 | 提供 Windows 可执行文件，无需额外安装依赖 |

## 依赖说明

| 项目 | 说明 |
|------|------|
| 运行依赖 | 无（Windows exe 已静态链接） |
| 编译依赖 | libcurl（仅需重新编译时安装） |
| 网络要求 | 需可访问内网 `rgci.ruijie.com.cn` |

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.0.1 | 2026-03-18 | 初始版本 |

## 许可证

MIT License — 详见 [LICENSE.txt](LICENSE.txt)

