#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Git分支切换与代码同步工具

功能：
1. 自动查找Git仓库
2. 切换到指定分支
3. 更新代码到最新状态
4. 强制模式：丢弃本地修改
5. 多仓库批量操作
"""

import os
import sys
import subprocess
import argparse
import json
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import time


class GitBranchSync:
    """Git分支同步工具类"""
    
    def __init__(self, verbose: bool = False, dry_run: bool = False):
        self.verbose = verbose
        self.dry_run = dry_run
        self.results = []
        
    def log(self, message: str, level: str = "INFO"):
        """输出日志"""
        if level == "DEBUG" and not self.verbose:
            return
        
        icons = {
            "INFO": "ℹ️ ",
            "SUCCESS": "✅",
            "ERROR": "❌",
            "WARNING": "⚠️ ",
            "DEBUG": "🔍"
        }
        
        icon = icons.get(level, "")
        print(f"{icon} {message}")
    
    def run_command(self, cmd: List[str], cwd: str = None, check: bool = True) -> Tuple[bool, str, str]:
        """
        运行命令
        返回: (成功标志, stdout, stderr)
        """
        if self.dry_run:
            self.log(f"[DRY RUN] 命令: {' '.join(cmd)}", "DEBUG")
            return True, "", ""
        
        try:
            self.log(f"执行: {' '.join(cmd)}", "DEBUG")
            result = subprocess.run(
                cmd,
                cwd=cwd,
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='ignore',
                check=check
            )
            return True, result.stdout, result.stderr
        except subprocess.CalledProcessError as e:
            return False, e.stdout, e.stderr
        except Exception as e:
            return False, "", str(e)
    
    def find_git_repos(self, base_dir: str, depth: int = 0) -> List[str]:
        """
        智能递归查找Git仓库
        策略：
        1. 从当前目录开始检查是否为Git仓库
        2. 如果不是，则递归进入所有子目录搜索
        3. 找到Git仓库后不再深入其子目录
        4. 支持深度限制（depth=0表示无限深度）
        
        Args:
            base_dir: 扫描的基础目录
            depth: 扫描深度（0=无限深度，1=只扫描当前目录，2=扫描到二级子目录...）
        
        Returns:
            Git仓库路径列表
        """
        repos = []
        base_path = Path(base_dir).resolve()
        
        depth_msg = "无限深度" if depth == 0 else f"深度: {depth}"
        self.log(f"🔍 扫描目录: {base_path} ({depth_msg})")
        
        def scan_dir(path: Path, current_depth: int):
            # 检查当前目录是否为Git仓库
            if (path / '.git').exists():
                repos.append(str(path))
                self.log(f"  ✓ 找到仓库: {path.name}", "DEBUG")
                return  # 找到Git仓库后不再深入其子目录
            
            # 检查深度限制（depth=0表示无限深度）
            if depth > 0 and current_depth >= depth:
                return
            
            try:
                # 扫描子目录
                for item in path.iterdir():
                    # 跳过非目录和隐藏目录
                    if not item.is_dir() or item.name.startswith('.'):
                        continue
                    # 跳过常见的非代码目录
                    if item.name in ['node_modules', 'venv', '__pycache__', 'dist', 'build', '.idea', '.vscode']:
                        continue
                    
                    # 递归扫描
                    scan_dir(item, current_depth + 1)
            except PermissionError:
                self.log(f"  ⚠️  权限不足: {path}", "WARNING")
            except Exception as e:
                self.log(f"  ⚠️  扫描错误 {path}: {e}", "DEBUG")
        
        scan_dir(base_path, 0)
        
        if repos:
            self.log(f"✅ 找到 {len(repos)} 个Git仓库")
        else:
            self.log(f"⚠️  未找到Git仓库", "WARNING")
        return repos
    
    def find_current_repo(self) -> Optional[str]:
        """
        查找当前目录或父目录中的Git仓库
        """
        current = Path.cwd()
        
        # 向上查找，最多10层
        for _ in range(10):
            if (current / '.git').exists():
                return str(current)
            
            parent = current.parent
            if parent == current:  # 已到根目录
                break
            current = parent
        
        return None
    
    def get_repo_status(self, repo_path: str) -> Dict:
        """
        获取仓库状态
        """
        status = {
            "is_valid": False,
            "current_branch": None,
            "has_changes": False,
            "untracked_files": [],
            "modified_files": [],
            "is_detached": False
        }
        
        # 检查是否为有效仓库
        success, stdout, _ = self.run_command(
            ["git", "rev-parse", "--git-dir"],
            cwd=repo_path,
            check=False
        )
        
        if not success:
            return status
        
        status["is_valid"] = True
        
        # 获取当前分支
        success, stdout, _ = self.run_command(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=repo_path,
            check=False
        )
        
        if success:
            branch = stdout.strip()
            if branch == "HEAD":
                status["is_detached"] = True
                status["current_branch"] = "(detached HEAD)"
            else:
                status["current_branch"] = branch
        
        # 检查工作区状态
        success, stdout, _ = self.run_command(
            ["git", "status", "--porcelain"],
            cwd=repo_path,
            check=False
        )
        
        if success and stdout.strip():
            status["has_changes"] = True
            for line in stdout.strip().split('\n'):
                if line.startswith('??'):
                    status["untracked_files"].append(line[3:])
                elif line.startswith(' M') or line.startswith('M'):
                    status["modified_files"].append(line[3:])
        
        return status
    
    def branch_exists(self, repo_path: str, branch: str) -> Tuple[bool, bool]:
        """
        检查分支是否存在
        返回: (本地存在, 远程存在)
        """
        # 检查本地分支
        success, stdout, _ = self.run_command(
            ["git", "rev-parse", "--verify", branch],
            cwd=repo_path,
            check=False
        )
        local_exists = success
        
        # 检查远程分支
        success, stdout, _ = self.run_command(
            ["git", "rev-parse", "--verify", f"origin/{branch}"],
            cwd=repo_path,
            check=False
        )
        remote_exists = success
        
        return local_exists, remote_exists
    
    def sync_branch(self, repo_path: str, branch: str, force: bool = False, 
                   prune: bool = True, no_fetch: bool = False) -> Dict:
        """
        同步分支到最新状态
        
        Args:
            repo_path: 仓库路径
            branch: 目标分支
            force: 是否强制模式（丢弃本地修改）
            prune: 是否清理远程已删除的分支
            no_fetch: 是否跳过fetch操作
        
        Returns:
            操作结果字典
        """
        repo_name = Path(repo_path).name
        result = {
            "repo": repo_path,
            "repo_name": repo_name,
            "success": False,
            "from_branch": None,
            "to_branch": branch,
            "forced": force,
            "message": "",
            "error": None,
            "suggestion": None
        }
        
        # 获取仓库状态
        status = self.get_repo_status(repo_path)
        
        if not status["is_valid"]:
            result["error"] = "不是有效的Git仓库"
            return result
        
        result["from_branch"] = status["current_branch"]
        
        # 检查是否有未提交的修改
        if status["has_changes"] and not force:
            files_info = []
            if status["modified_files"]:
                files_info.extend([f"  M {f}" for f in status["modified_files"][:5]])
            if status["untracked_files"]:
                files_info.extend([f"  ?? {f}" for f in status["untracked_files"][:5]])
            
            result["error"] = "本地有未提交的修改"
            result["suggestion"] = "使用 --force 参数丢弃修改，或手动提交/储藏修改"
            result["message"] = "\n未提交的文件:\n" + "\n".join(files_info[:10])
            
            if len(status["modified_files"]) + len(status["untracked_files"]) > 10:
                result["message"] += f"\n  ... 还有 {len(status['modified_files']) + len(status['untracked_files']) - 10} 个文件"
            
            return result
        
        try:
            # 步骤1: Fetch远程更新
            if not no_fetch:
                self.log(f"  ✓ 获取远程更新...", "DEBUG")
                fetch_cmd = ["git", "fetch", "origin"]
                if prune:
                    fetch_cmd.append("--prune")
                
                success, stdout, stderr = self.run_command(fetch_cmd, cwd=repo_path, check=False)
                if not success:
                    result["error"] = f"Fetch失败: {stderr}"
                    result["suggestion"] = "检查网络连接或使用 --no-fetch 跳过"
                    return result
            
            # 步骤2: 强制模式下清理工作区
            if force and status["has_changes"]:
                self.log(f"  ⚠️  强制模式: 清理工作区", "WARNING")
                
                # 删除未跟踪的文件
                success, _, stderr = self.run_command(
                    ["git", "clean", "-fd"],
                    cwd=repo_path,
                    check=False
                )
                
                if not success:
                    self.log(f"    清理未跟踪文件失败: {stderr}", "DEBUG")
                
                # 重置所有修改
                success, _, stderr = self.run_command(
                    ["git", "reset", "--hard", "HEAD"],
                    cwd=repo_path,
                    check=False
                )
                
                if not success:
                    result["error"] = f"重置失败: {stderr}"
                    return result
            
            # 步骤3: 检查目标分支是否存在
            local_exists, remote_exists = self.branch_exists(repo_path, branch)
            
            if not local_exists and not remote_exists:
                result["error"] = f"分支 '{branch}' 不存在（本地和远程都没有）"
                result["suggestion"] = "检查分支名称是否正确"
                return result
            
            # 步骤4: 切换分支
            if status["current_branch"] != branch and not status["is_detached"]:
                self.log(f"  ✓ 切换到分支 {branch}", "DEBUG")
            
            checkout_cmd = ["git", "checkout", branch]
            
            # 如果本地不存在但远程存在，创建跟踪分支
            if not local_exists and remote_exists:
                checkout_cmd = ["git", "checkout", "-b", branch, f"origin/{branch}"]
                self.log(f"  ✓ 创建跟踪分支 {branch}", "DEBUG")
            
            success, stdout, stderr = self.run_command(checkout_cmd, cwd=repo_path, check=False)
            
            if not success:
                result["error"] = f"切换分支失败: {stderr}"
                return result
            
            # 步骤5: 更新到最新代码
            if force:
                # 强制模式：重置到远程状态
                self.log(f"  ✓ 强制重置到远程最新", "DEBUG")
                success, stdout, stderr = self.run_command(
                    ["git", "reset", "--hard", f"origin/{branch}"],
                    cwd=repo_path,
                    check=False
                )
                
                if not success:
                    result["error"] = f"重置到远程失败: {stderr}"
                    return result
            else:
                # 正常模式：pull
                self.log(f"  ✓ 拉取最新代码", "DEBUG")
                success, stdout, stderr = self.run_command(
                    ["git", "pull", "origin", branch],
                    cwd=repo_path,
                    check=False
                )
                
                if not success:
                    # 如果pull失败，可能是因为本地和远程有分歧
                    if "diverged" in stderr.lower() or "conflict" in stderr.lower():
                        result["error"] = "本地分支与远程分支有冲突"
                        result["suggestion"] = "使用 --force 参数强制重置到远程状态"
                        return result
                    else:
                        result["error"] = f"拉取代码失败: {stderr}"
                        return result
            
            # 成功
            result["success"] = True
            
            if result["from_branch"] == branch:
                result["message"] = "已在目标分支，代码已更新到最新"
            else:
                result["message"] = f"成功切换并更新 ({result['from_branch']} → {branch})"
            
        except Exception as e:
            result["error"] = f"未预期的错误: {str(e)}"
        
        return result
    
    def sync_repos(self, repos: List[str], branch: str, force: bool = False,
                  prune: bool = True, no_fetch: bool = False) -> Dict:
        """
        批量同步多个仓库
        """
        total = len(repos)
        succeeded = 0
        failed = 0
        
        self.log(f"\n📦 准备处理 {total} 个仓库")
        self.log(f"目标分支: {branch}")
        self.log(f"模式: {'强制' if force else '正常'}")
        
        if self.dry_run:
            self.log("\n⚠️  DRY RUN 模式 - 不会实际执行操作\n", "WARNING")
        
        for idx, repo in enumerate(repos, 1):
            repo_name = Path(repo).name
            self.log(f"\n📦 处理仓库: {repo_name} ({idx}/{total})")
            
            # 获取当前状态
            status = self.get_repo_status(repo)
            if status["is_valid"]:
                self.log(f"  当前分支: {status['current_branch']} → 目标分支: {branch}")
                
                if status["has_changes"]:
                    change_count = len(status["modified_files"]) + len(status["untracked_files"])
                    self.log(f"  ⚠️  检测到 {change_count} 个未提交的修改", "WARNING")
            
            # 执行同步
            result = self.sync_branch(repo, branch, force, prune, no_fetch)
            self.results.append(result)
            
            if result["success"]:
                succeeded += 1
                self.log(f"  ✅ {result['message']}", "SUCCESS")
            else:
                failed += 1
                self.log(f"  ❌ 失败: {result['error']}", "ERROR")
                if result.get("message"):
                    print(result["message"])
                if result.get("suggestion"):
                    self.log(f"  💡 建议: {result['suggestion']}", "INFO")
        
        # 输出统计
        summary = {
            "success": failed == 0,
            "total": total,
            "succeeded": succeeded,
            "failed": failed,
            "skipped": 0,
            "results": self.results
        }
        
        self.log("\n" + "="*60)
        self.log("📊 操作统计:")
        self.log(f"  ✅ 成功: {succeeded} 个仓库")
        self.log(f"  ❌ 失败: {failed} 个仓库")
        
        return summary


def main():
    parser = argparse.ArgumentParser(
        description="Git分支切换与代码同步工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 切换到master分支并更新
  python git_branch_sync.py --branch master
  
  # 强制模式：丢弃本地修改
  python git_branch_sync.py --branch develop --force
  
  # 多仓库批量操作
  python git_branch_sync.py --scan-repos --branch master --force
  
  # 预览操作
  python git_branch_sync.py --scan-repos --branch develop --dry-run
        """
    )
    
    # 基本参数
    parser.add_argument("-b", "--branch", required=True, help="目标分支名称")
    parser.add_argument("-f", "--force", action="store_true", 
                       help="强制模式：丢弃本地修改并重置到远程状态")
    parser.add_argument("-r", "--repo", help="仓库路径（可选，默认自动查找）")
    
    # 多仓库扫描
    parser.add_argument("--scan-repos", action="store_true", 
                       help="扫描多个仓库")
    parser.add_argument("--base-dir", default=r"d:\project\ecp",
                       help="扫描的基础目录（默认: d:\\project\\ecp）")
    parser.add_argument("--scan-depth", type=int, default=2,
                       help="扫描深度（默认: 2）")
    
    # 操作选项
    parser.add_argument("-p", "--prune", action="store_true", default=True,
                       help="清理远程已删除的分支（默认启用）")
    parser.add_argument("--no-prune", action="store_false", dest="prune",
                       help="不清理远程分支")
    parser.add_argument("--no-fetch", action="store_true",
                       help="跳过fetch操作（仅使用本地数据）")
    
    # 输出选项
    parser.add_argument("-v", "--verbose", action="store_true",
                       help="详细输出")
    parser.add_argument("--dry-run", action="store_true",
                       help="模拟运行，不实际执行")
    parser.add_argument("--json", action="store_true",
                       help="输出JSON格式结果")
    
    args = parser.parse_args()
    
    # 创建工具实例
    tool = GitBranchSync(verbose=args.verbose, dry_run=args.dry_run)
    
    start_time = time.time()
    
    # 确定要处理的仓库
    repos = []
    
    if args.scan_repos:
        # 扫描多个仓库
        repos = tool.find_git_repos(args.base_dir, args.scan_depth)
        if not repos:
            tool.log("❌ 未找到任何Git仓库", "ERROR")
            sys.exit(1)
    elif args.repo:
        # 使用指定的仓库
        if not Path(args.repo).exists():
            tool.log(f"❌ 仓库路径不存在: {args.repo}", "ERROR")
            sys.exit(1)
        repos = [args.repo]
    else:
        # 自动查找当前仓库
        repo = tool.find_current_repo()
        if not repo:
            tool.log("❌ 未找到Git仓库。请使用 --repo 指定路径或使用 --scan-repos 扫描", "ERROR")
            sys.exit(1)
        repos = [repo]
    
    # 执行同步
    if len(repos) == 1:
        # 单个仓库
        result = tool.sync_branch(
            repos[0], 
            args.branch, 
            force=args.force,
            prune=args.prune,
            no_fetch=args.no_fetch
        )
        
        if result["success"]:
            tool.log(f"\n✅ 成功: {result['message']}", "SUCCESS")
            exit_code = 0
        else:
            tool.log(f"\n❌ 失败: {result['error']}", "ERROR")
            if result.get("suggestion"):
                tool.log(f"💡 建议: {result['suggestion']}", "INFO")
            exit_code = 1
        
        summary = {
            "success": result["success"],
            "total": 1,
            "succeeded": 1 if result["success"] else 0,
            "failed": 0 if result["success"] else 1,
            "skipped": 0,
            "results": [result]
        }
    else:
        # 多个仓库
        summary = tool.sync_repos(
            repos,
            args.branch,
            force=args.force,
            prune=args.prune,
            no_fetch=args.no_fetch
        )
        
        exit_code = 0 if summary["success"] else 1
    
    # 输出耗时
    elapsed = time.time() - start_time
    tool.log(f"⏱️  总耗时: {elapsed:.1f} 秒\n")
    
    # 输出JSON结果（供AI处理）
    if args.json:
        print("\n" + "="*60)
        print("JSON结果:")
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
