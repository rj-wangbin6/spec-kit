#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const contractPath = path.resolve(scriptDirectory, '..', 'report-contract.json');

function printUsage() {
  console.log(`Code review report structure checker

Usage:
  node validate-report.mjs --report <path> --requirements <present|absent> --fullstack <present|absent>

This checks report structure only. It does not determine whether review findings are correct or complete.`);
}

function parseArguments(args) {
  const options = {};
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === '--help' || argument === '-h') {
      options.help = true;
      continue;
    }
    if (!['--report', '--requirements', '--fullstack'].includes(argument)) {
      throw new Error(`不认识参数“${argument}”。请运行 --help 查看支持的用法。`);
    }
    if (options[argument]) {
      throw new Error(`参数“${argument}”重复提供，请保留一个值。`);
    }
    options[argument] = args[index + 1];
    index += 1;
  }

  if (options.help) return options;
  for (const name of ['--report', '--requirements', '--fullstack']) {
    if (!options[name]) throw new Error(`缺少必需参数“${name}”。请运行 --help 查看用法。`);
  }
  for (const name of ['--requirements', '--fullstack']) {
    if (!['present', 'absent'].includes(options[name])) {
      throw new Error(`参数“${name}”只接受 present 或 absent，当前值为“${options[name]}”。`);
    }
  }
  return options;
}

function parseHeadings(markdown) {
  const headings = [];
  const lines = markdown.split(/\r?\n/);
  let fence = null;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const fenceMatch = line.match(/^\s{0,3}(`{3,}|~{3,})/);
    if (fenceMatch) {
      const marker = fenceMatch[1][0];
      if (fence === null) {
        fence = { marker, length: fenceMatch[1].length };
      } else if (fence.marker === marker && fenceMatch[1].length >= fence.length) {
        fence = null;
      }
      continue;
    }
    if (fence !== null) continue;

    const headingMatch = line.match(/^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$/);
    if (headingMatch) {
      headings.push({ level: headingMatch[1].length, title: headingMatch[2].trim(), line: index });
    }
  }

  return { headings, lines };
}

function normalizeTitle(title) {
  return title
    .replace(/[✅📋📄🛡️⚠️📊]/gu, '')
    .replace(/（如提供需求文档时填写）/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function sectionForHeading(headings, lines, heading) {
  let end = lines.length;
  for (const candidate of headings) {
    if (candidate.line > heading.line && candidate.level <= heading.level) {
      end = candidate.line;
      break;
    }
  }
  return lines.slice(heading.line + 1, end).join('\n').trim();
}

function isPlaceholder(content) {
  if (!content.trim()) return true;
  // 只匹配明确的未填充模板痕迹，正常表格与正文内容不会被误判
  const withoutFences = content.replace(/^\s*(`{3,}|~{3,})[^\n]*\n[\s\S]*?^\s*\1\s*$/gm, ' ');
  const templateSignatures = [
    /xxxxxxxx/i,
    /\bYYYY-MM-DD\b/,
    /\bTODO\b/i,
    /\{[^\n{}]*(?:填写|记录|说明|示例|问题标题|版本号)[^\n{}]*\}/,
    /\{(?:author_name|start_date|end_date|requirement_summary|version)\}/,
    /待填写|待补充|这里记录|列出核心|填写本次|描述问题的具体描述|当前问题的问题分类描述|如提供需求文档时填写/,
    /^\s*示例[:：]\s*$/m,
    /^\s*\|[^\n|]*(?:xxx|XXX|\{[^}]+\})[^\n|]*\|/m
  ];
  return templateSignatures.some((pattern) => pattern.test(withoutFences));
}

function checkReport(markdown, contract, applicability) {
  const errors = [];
  const warnings = [];
  const { headings, lines } = parseHeadings(markdown);
  const recognized = [];

  for (const section of contract.requiredSections) {
    const accepted = [section.title, ...(section.aliases ?? [])].map(normalizeTitle);
    const matches = headings.filter((heading) => accepted.includes(normalizeTitle(heading.title)));
    if (matches.length === 0) {
      errors.push(`缺少必需章节“${section.title}”。请添加该二级标题，并补充内容：${section.suggestion}`);
      continue;
    }
    if (matches.length > 1) {
      errors.push(`章节“${section.title}”出现了 ${matches.length} 次（第 ${matches.map((item) => item.line + 1).join('、')} 行）。请保留一份正式章节，删除重复标题或将示例内容移出正式报告。`);
      continue;
    }
    const content = sectionForHeading(headings, lines, matches[0]);
    recognized.push(matches[0]);
    if (isPlaceholder(content)) {
      errors.push(`章节“${section.title}”（第 ${matches[0].line + 1} 行）目前为空或仍是模板占位内容。${section.suggestion}`);
    }
  }

  for (const section of contract.conditionalSections) {
    const accepted = normalizeTitle(section.title);
    const matches = headings.filter((heading) => normalizeTitle(heading.title).startsWith(accepted));
    const applicable = section.condition === 'requirements=present'
      ? applicability.requirements === 'present'
      : applicability.fullstack === 'present';

    if (applicable && matches.length === 0) {
      errors.push(`当前评审条件要求章节“${section.title}”，但报告中没有找到。${section.suggestion}`);
      continue;
    }
    if (!applicable && matches.length === 0) {
      errors.push(`请保留章节“${section.title}”并明确说明“${section.notApplicableText}”，避免无法区分不适用与遗漏。`);
      continue;
    }
    if (matches.length > 1) {
      errors.push(`条件章节“${section.title}”出现了 ${matches.length} 次。请合并为一个正式章节。`);
      continue;
    }

    const content = sectionForHeading(headings, lines, matches[0]);
    recognized.push(matches[0]);
    if (applicable && isPlaceholder(content)) {
      errors.push(`章节“${section.title}”（第 ${matches[0].line + 1} 行）为空或仍含模板占位内容。${section.suggestion}`);
    }
    if (!applicable && !content.includes(section.notApplicableText)) {
      errors.push(`章节“${section.title}”当前不适用，但没有明确写出“${section.notApplicableText}”。请在章节正文中补充该说明。`);
    }
  }

  const issuesHeading = headings.find((heading) => normalizeTitle(heading.title) === normalizeTitle('⚠️ 问题清单'));
  if (issuesHeading) {
    const issueContent = sectionForHeading(headings, lines, issuesHeading);
    const headingsAfterIssues = headings.filter((heading) => heading.line > issuesHeading.line);
    const issueHeadingEnd = headingsAfterIssues.length ? headingsAfterIssues[0].line : lines.length;
    const issueBody = lines.slice(issuesHeading.line + 1, issueHeadingEnd).join('\n');
    if (isPlaceholder(issueContent) && !issueBody.includes(contract.noFindingsText)) {
      errors.push(`“⚠️ 问题清单”没有可识别的问题内容，也未明确声明“${contract.noFindingsText}”。请列出确认的问题，或明确声明本轮未发现已确认问题。`);
    }
  }

  const missingSeverity = contract.severityContract.filter((severity) => {
    const occurrences = markdown.match(new RegExp(`\\b${severity}\\b`, 'g'));
    return occurrences && occurrences.length > 0 && !new RegExp(`\\b${severity}\\b`).test(markdown);
  });
  if (missingSeverity.length) {
    warnings.push(`严重度编号需要人工核对：${missingSeverity.join(', ')}。标准口径为 P0、P1、P2、P3；该脚本不判定单个问题的风险评级是否正确。`);
  }

  return { errors, warnings, sectionsFound: recognized.length };
}

async function main() {
  let options;
  try {
    options = parseArguments(process.argv.slice(2));
  } catch (error) {
    console.error(`参数错误：${error.message}`);
    process.exitCode = 2;
    return;
  }
  if (options.help) {
    printUsage();
    return;
  }

  const reportPath = path.resolve(options['--report']);
  let markdown;
  let contract;
  try {
    [markdown, contract] = await Promise.all([
      readFile(reportPath, 'utf8'),
      readFile(contractPath, 'utf8').then(JSON.parse)
    ]);
  } catch (error) {
    console.error(`无法读取评审报告或校验规则：${error.message}`);
    console.error('请确认报告路径正确，并确认仓库中存在 templates/code-review/report-contract.json。');
    process.exitCode = 2;
    return;
  }

  const result = checkReport(markdown, contract, {
    requirements: options['--requirements'],
    fullstack: options['--fullstack']
  });

  console.log(`报告结构检查：${result.errors.length === 0 ? '未发现结构问题' : `发现 ${result.errors.length} 项需要处理`}`);
  console.log(`检查章节：${result.sectionsFound} 项；需求来源：${options['--requirements']}；前后端联调：${options['--fullstack']}`);
  for (const error of result.errors) console.error(`\n- ${error}`);
  for (const warning of result.warnings) console.warn(`\n提示：${warning}`);

  if (result.errors.length > 0) {
    console.error('\n请根据以上提示补齐或修正报告后，重新运行本脚本。检查通过只表示报告结构完整，不代表评审发现已经验证或没有遗漏。');
    process.exitCode = 1;
    return;
  }
  console.log('\n结构检查通过。仍须完成独立报告复核；本脚本不判断问题真实性、风险评级或漏报。');
}

export { checkReport, parseHeadings };

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
