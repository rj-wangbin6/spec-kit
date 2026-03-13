"""
Git提交记录收集工具
用途：收集指定Git仓库的提交记录（AI通过参数传递仓库信息）
适用场景：Code Review前获取代码变更记录
"""

import os
import json
import subprocess
import argparse
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional, Tuple


class CommitCollector:
    """提交记录收集器"""
    
    def __init__(self, verbose: bool = False):
        """
        初始化收集器
        
        Args:
            verbose: 是否显示详细日志
        """
        self.verbose = verbose
    
    def log(self, message: str, level: str = "INFO"):
        """打印日志"""
        if self.verbose or level == "ERROR" or level == "WARN":
            print(f"[{level}] {message}")
    
    def get_developer_info(self) -> Dict:
        """
        获取当前Git用户配置信息
        
        Returns:
            包含name和email的字典
        """
        result = subprocess.run(
            ['git', 'config', 'user.name'],
            capture_output=True,
            text=True,
            encoding='utf-8',
            errors='ignore'
        )
        name = result.stdout.strip() if result.returncode == 0 else "Unknown"
        
        result = subprocess.run(
            ['git', 'config', 'user.email'],
            capture_output=True,
            text=True,
            encoding='utf-8',
            errors='ignore'
        )
        email = result.stdout.strip() if result.returncode == 0 else "Unknown"
        
        return {"name": name, "email": email}
    
    def run_git_command(self, cmd: List[str], cwd: Path) -> Tuple[bool, str]:
        """
        执行Git命令并返回结果
        
        Returns:
            (成功标志, 输出内容)
        """
        try:
            full_cmd = ['git'] + cmd
            self.log(f"执行命令: {' '.join(full_cmd)}")
            result = subprocess.run(
                full_cmd,
                cwd=cwd,
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='ignore',
                timeout=30
            )
            self.log(f"命令返回码: {result.returncode}, 输出行数: {len(result.stdout.strip().split(chr(10))) if result.stdout else 0}")
            return (result.returncode == 0, result.stdout.strip())
        except Exception as e:
            self.log(f"命令执行失败 {' '.join(cmd)}: {e}", "ERROR")
            return (False, "")
    
    def get_commits(
        self,
        repo_path: Path,
        author: Optional[str] = None,
        since: Optional[str] = None,
        until: Optional[str] = None,
        max_count: Optional[int] = None
    ) -> List[Dict]:
        """
        获取指定仓库的提交记录
        
        Args:
            repo_path: 仓库路径
            author: 提交者（邮箱或用户名）
            since: 开始日期（YYYY-MM-DD）
            until: 结束日期（YYYY-MM-DD）
            max_count: 最大提交数量
            
        Returns:
            提交记录列表
        """
        self.log(f"获取仓库提交记录: {repo_path.name}")
        
        # 处理日期格式：如果只有日期没有时间，追加 00:00:00
        if since and len(since) == 10:  # YYYY-MM-DD
            since = f"{since} 00:00:00"
        if until and len(until) == 10:  # YYYY-MM-DD  
            until = f"{until} 23:59:59"
        
        # 构建git log命令（查询所有分支，包括远程分支）
        cmd = ['log', '--all', '--pretty=format:%H|%an|%ae|%ai|%s']
        
        if author:
            cmd.extend(['--author', author])
        if since:
            cmd.extend(['--since', since])
        if until:
            cmd.extend(['--until', until])
        if max_count:
            cmd.extend(['-n', str(max_count)])
        
        success, output = self.run_git_command(cmd, repo_path)
        
        if not success or not output:
            self.log(f"仓库 {repo_path.name} 无提交记录", "WARN")
            return []
        
        # 解析提交记录
        commits = []
        for line in output.split('\n'):
            if not line.strip():
                continue
            
            parts = line.split('|')
            if len(parts) != 5:
                continue
            
            commit_hash, author_name, author_email, commit_date, message = parts
            
            # 获取提交的文件变更统计
            success, stat = self.run_git_command(
                ['show', '--stat', '--pretty=format:', commit_hash],
                repo_path
            )
            
            # 解析统计信息
            files_changed = 0
            insertions = 0
            deletions = 0
            if success and stat:
                # 最后一行通常是统计信息，如: "3 files changed, 45 insertions(+), 12 deletions(-)"
                lines = stat.strip().split('\n')
                if lines:
                    last_line = lines[-1]
                    import re
                    match = re.search(r'(\d+) files? changed', last_line)
                    if match:
                        files_changed = int(match.group(1))
                    match = re.search(r'(\d+) insertions?', last_line)
                    if match:
                        insertions = int(match.group(1))
                    match = re.search(r'(\d+) deletions?', last_line)
                    if match:
                        deletions = int(match.group(1))
            
            commits.append({
                "hash": commit_hash[:7],  # 短hash
                "full_hash": commit_hash,
                "author_name": author_name,
                "author_email": author_email,
                "date": commit_date[:19],  # 只保留到秒
                "message": message,
                "files_changed": files_changed,
                "insertions": insertions,
                "deletions": deletions
            })
        
        self.log(f"找到 {len(commits)} 个提交")
        return commits
    
    def collect_commits(
        self,
        repo_path: str,
        repo_name: str,
        repo_url: str = "",
        author: Optional[str] = None,
        since: Optional[str] = None,
        until: Optional[str] = None,
        max_count: Optional[int] = None
    ) -> Dict:
        """
        收集指定仓库的提交记录
        
        Args:
            repo_path: 仓库路径
            repo_name: 仓库名称
            repo_url: 仓库URL（可选）
            author: 提交者筛选
            since: 开始日期
            until: 结束日期
            max_count: 最大提交数
            
        Returns:
            完整的提交记录数据
        """
        print("\n" + "=" * 60)
        print("开始收集提交记录")
        print("=" * 60)
        print(f"仓库: {repo_name}")
        print(f"路径: {repo_path}")
        if repo_url:
            print(f"URL: {repo_url}")
        if author:
            print(f"筛选提交者: {author}")
        if since:
            print(f"开始日期: {since}")
        if until:
            print(f"结束日期: {until}")
        if max_count:
            print(f"最大提交数: {max_count}")
        print()
        
        repo_path_obj = Path(repo_path)
        
        if not repo_path_obj.exists():
            raise FileNotFoundError(f"仓库路径不存在: {repo_path}")
        
        if not (repo_path_obj / '.git').exists():
            raise ValueError(f"指定路径不是Git仓库: {repo_path}")
        
        # 拉取远程最新代码
        self.log("正在拉取远程最新代码...")
        fetch_success, fetch_output = self.run_git_command(
            ['fetch', '--all'],
            repo_path_obj
        )
        if fetch_success:
            self.log("远程代码拉取成功")
        else:
            self.log("远程代码拉取失败，将继续使用本地数据", "WARN")
        
        # 获取当前分支
        success, current_branch = self.run_git_command(
            ['branch', '--show-current'],
            repo_path_obj
        )
        if not success:
            current_branch = "Unknown"
        
        # 收集提交记录
        commits = self.get_commits(
            repo_path=repo_path_obj,
            author=author,
            since=since,
            until=until,
            max_count=max_count
        )
        
        return self._build_result(
            repo_name=repo_name,
            repo_path=repo_path,
            repo_url=repo_url,
            current_branch=current_branch,
            commits=commits
        )
    
    def _build_result(
        self,
        repo_name: str,
        repo_path: str,
        repo_url: str,
        current_branch: str,
        commits: List[Dict]
    ) -> Dict:
        """构建结果数据结构"""
        developer_info = self.get_developer_info()
        
        return {
            "collection_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "developer": developer_info,
            "repository": {
                "name": repo_name,
                "path": repo_path,
                "url": repo_url,
                "current_branch": current_branch,
                "commits": commits,
                "total_commits": len(commits)
            }
        }
    
    def save_to_file(self, data: Dict, output_path: str, pretty: bool = False):
        """保存数据到JSON文件"""
        indent = 2 if pretty else None
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=indent)
        
        print(f"\n✅ 提交记录已保存到: {output_path}")
    
    def print_summary(self, data: Dict):
        """打印摘要信息"""
        print("\n" + "=" * 60)
        print("提交记录收集完成")
        print("=" * 60)
        print(f"开发者: {data['developer']['name']} <{data['developer']['email']}>")
        print(f"仓库: {data['repository']['name']}")
        print(f"提交总数: {data['repository']['total_commits']}")
        print("=" * 60)
        print()


def main():
    """主函数"""
    parser = argparse.ArgumentParser(
        description="Git提交记录收集工具 - 收集指定仓库的代码变更",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例用法:
  # 基本用法（AI从步骤1的JSON中读取信息后传递参数）
  python collect_commits.py --repo-path "D:/projects/my-service" --repo-name "my-service"
  
  # 指定提交者和时间范围
  python collect_commits.py --repo-path "D:/projects/my-service" --repo-name "my-service" --author zhangsan --since 2026-03-01
  
  # 指定仓库URL并限制提交数量
  python collect_commits.py --repo-path "D:/projects/my-service" --repo-name "my-service" --repo-url "https://github.com/company/my-service.git" --max-count 50
  
  # 美化输出
  python collect_commits.py --repo-path "D:/projects/my-service" --repo-name "my-service" --pretty
        """
    )
    
    parser.add_argument(
        '--repo-path',
        required=True,
        help='仓库路径（必需）'
    )
    
    parser.add_argument(
        '--repo-name',
        required=True,
        help='仓库名称（必需）'
    )
    
    parser.add_argument(
        '--repo-url',
        default='',
        help='仓库URL（可选，用于输出展示）'
    )
    
    parser.add_argument(
        '--author', '-a',
        help='筛选提交者（用户名或邮箱）'
    )
    
    parser.add_argument(
        '--since', '-s',
        help='开始日期（YYYY-MM-DD 或 YYYY-MM-DD HH:MM:SS）'
    )
    
    parser.add_argument(
        '--until', '-u',
        help='结束日期（YYYY-MM-DD 或 YYYY-MM-DD HH:MM:SS）'
    )
    
    parser.add_argument(
        '--max-count', '-n',
        type=int,
        help='最大提交数量'
    )
    

    
    parser.add_argument(
        '--pretty', '-p',
        action='store_true',
        help='美化JSON输出'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='显示详细日志'
    )
    
    args = parser.parse_args()
    
    try:
        # 创建收集器
        collector = CommitCollector(verbose=args.verbose)
        
        # 收集提交记录
        data = collector.collect_commits(
            repo_path=args.repo_path,
            repo_name=args.repo_name,
            repo_url=args.repo_url,
            author=args.author,
            since=args.since,
            until=args.until,
            max_count=args.max_count
        )
        
        # 打印摘要
        collector.print_summary(data)
        
        # 输出JSON到控制台
        print("\n" + "=" * 60)
        print("完整数据（JSON格式）")
        print("=" * 60)
        indent = 2 if args.pretty else None
        print(json.dumps(data, ensure_ascii=False, indent=indent))
        print()
        
    except FileNotFoundError as e:
        print(f"❌ 错误: {e}")
        return 1
    except ValueError as e:
        print(f"❌ 错误: {e}")
        return 1
    except Exception as e:
        print(f"❌ 执行失败: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())
