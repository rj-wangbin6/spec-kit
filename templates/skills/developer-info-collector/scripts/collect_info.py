"""
开发者信息收集工具
用途：自动扫描当前目录的所有Git项目，收集开发者配置、项目信息、分支状态等
适用场景：Code Review前的信息准备
"""

import os
import json
import subprocess
import argparse
import re
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional, Tuple


class DeveloperInfoCollector:
    """开发者信息收集器"""
    
    def __init__(self, base_dir: str = ".", depth: int = 3, verbose: bool = False):
        """
        初始化收集器
        
        Args:
            base_dir: 扫描的基础目录
            depth: 扫描深度（1-5层）
            verbose: 是否显示详细日志
        """
        self.base_dir = Path(base_dir).resolve()
        self.depth = max(1, min(5, depth))  # 限制在1-5层
        self.verbose = verbose
        self.git_projects: List[Path] = []
        
    def log(self, message: str, level: str = "INFO"):
        """打印日志"""
        if self.verbose or level == "ERROR" or level == "WARN":
            print(f"[{level}] {message}")
    
    def run_command(self, cmd: List[str], cwd: Optional[Path] = None) -> Tuple[bool, str]:
        """
        执行命令并返回结果
        
        Returns:
            (成功标志, 输出内容)
        """
        try:
            result = subprocess.run(
                cmd,
                cwd=cwd or self.base_dir,
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='ignore',
                timeout=10
            )
            return (result.returncode == 0, result.stdout.strip())
        except Exception as e:
            self.log(f"命令执行失败 {' '.join(cmd)}: {e}", "ERROR")
            return (False, "")
    
    def find_git_projects(self) -> List[Path]:
        """
        扫描目录找到所有Git项目
        
        Returns:
            Git项目路径列表
        """
        self.log(f"开始扫描目录: {self.base_dir}，深度: {self.depth}")
        projects = []
        
        def scan_directory(current_path: Path, current_depth: int):
            """递归扫描目录"""
            if current_depth > self.depth:
                return
            
            try:
                # 检查当前目录是否是Git项目
                git_dir = current_path / ".git"
                if git_dir.exists() and git_dir.is_dir():
                    projects.append(current_path)
                    self.log(f"找到Git项目: {current_path}")
                    return  # 找到后不再深入子目录
                
                # 扫描子目录
                if current_depth < self.depth:
                    for entry in current_path.iterdir():
                        if entry.is_dir() and not entry.name.startswith('.'):
                            scan_directory(entry, current_depth + 1)
            except PermissionError:
                self.log(f"无权限访问: {current_path}", "WARN")
            except Exception as e:
                self.log(f"扫描失败 {current_path}: {e}", "ERROR")
        
        scan_directory(self.base_dir, 0)
        self.git_projects = projects
        self.log(f"扫描完成，找到 {len(projects)} 个Git项目")
        return projects
    
    def get_developer_info(self) -> Dict:
        """
        获取开发者配置信息
        
        Returns:
            开发者信息字典
        """
        self.log("获取开发者配置信息...")
        
        # 获取用户名
        success, username = self.run_command(["git", "config", "user.name"])
        if not success or not username:
            username = "Unknown"
            self.log("未找到Git用户名配置", "WARN")
        
        # 获取邮箱
        success, email = self.run_command(["git", "config", "user.email"])
        if not success or not email:
            email = "Unknown"
            self.log("未找到Git邮箱配置", "WARN")
        
        # 获取Git版本
        success, git_version = self.run_command(["git", "--version"])
        if success and git_version:
            # 提取版本号 "git version 2.40.0.windows.1" -> "2.40.0"
            match = re.search(r'git version ([\d.]+)', git_version)
            git_version = match.group(1) if match else git_version
        else:
            git_version = "Unknown"
        
        return {
            "name": username,
            "email": email,
            "git_version": git_version
        }
    
    def extract_project_name(self, remote_url: str) -> str:
        """
        从远程仓库地址提取项目名
        
        Examples:
            https://github.com/company/my-service.git -> my-service
            git@github.com:company/my-service.git -> my-service
        """
        if not remote_url:
            return "Unknown"
        
        # 移除 .git 后缀
        url = remote_url.rstrip('/')
        if url.endswith('.git'):
            url = url[:-4]
        
        # 提取最后一部分作为项目名
        project_name = url.split('/')[-1]
        return project_name    
    def get_contributors(self, project_path: Path) -> List[Dict]:
        """
        获取仓库的所有提交者列表
        
        Args:
            project_path: 项目路径
            
        Returns:
            提交者列表，每个元素包含 name 和 email
        """
        self.log(f"获取提交者列表: {project_path.name}")
        
        # 获取所有提交者（去重）
        success, output = self.run_command(
            ["git", "log", "--all", "--format=%an|%ae"],
            cwd=project_path
        )
        
        if not success or not output:
            self.log(f"项目 {project_path.name} 无提交记录", "WARN")
            return []
        
        # 解析并去重
        contributors_set = set()
        contributors = []
        
        for line in output.split('\n'):
            line = line.strip()
            if not line or '|' not in line:
                continue
            
            parts = line.split('|')
            if len(parts) != 2:
                continue
            
            name, email = parts[0].strip(), parts[1].strip()
            
            # 使用email作为唯一标识去重
            if email and email not in contributors_set:
                contributors_set.add(email)
                contributors.append({
                    "name": name,
                    "email": email
                })
        
        self.log(f"找到 {len(contributors)} 个提交者")
        return contributors    
    def get_project_info(self, project_path: Path) -> Optional[Dict]:
        """
        获取单个项目的详细信息
        
        Args:
            project_path: 项目路径
            
        Returns:
            项目信息字典，失败返回None
        """
        self.log(f"收集项目信息: {project_path.name}")
        
        try:
            # 获取远程仓库地址
            success, remote_url = self.run_command(
                ["git", "config", "--get", "remote.origin.url"],
                cwd=project_path
            )
            if not success or not remote_url:
                remote_url = ""
                self.log(f"项目 {project_path.name} 未配置远程仓库", "WARN")
            
            # 提取项目名
            project_name = self.extract_project_name(remote_url)
            if project_name == "Unknown":
                project_name = project_path.name  # 使用目录名作为备选
            
            # 获取当前分支
            success, current_branch = self.run_command(
                ["git", "branch", "--show-current"],
                cwd=project_path
            )
            if not success:
                current_branch = "Unknown"
            
            # 检查本地修改状态
            success, status_output = self.run_command(
                ["git", "status", "--porcelain"],
                cwd=project_path
            )
            has_uncommitted_changes = bool(status_output)
            uncommitted_files = len(status_output.split('\n')) if status_output else 0
            
            # 获取最近一次提交
            success, log_output = self.run_command(
                ["git", "log", "-1", "--pretty=format:%H|%an|%ai|%s"],
                cwd=project_path
            )
            
            last_commit = {}
            if success and log_output:
                parts = log_output.split('|')
                if len(parts) == 4:
                    last_commit = {
                        "hash": parts[0][:7],  # 短hash
                        "author": parts[1],
                        "date": parts[2][:19],  # 只保留到秒
                        "message": parts[3]
                    }
            
            # 获取所有提交者列表
            contributors = self.get_contributors(project_path)
            
            return {
                "project_name": project_name,
                "project_path": str(project_path).replace('\\', '/'),
                "remote_url": remote_url,
                "current_branch": current_branch,
                "has_uncommitted_changes": has_uncommitted_changes,
                "uncommitted_files": uncommitted_files,
                "last_commit": last_commit,
                "contributors": contributors
            }
            
        except Exception as e:
            self.log(f"获取项目信息失败 {project_path.name}: {e}", "ERROR")
            return None
    
    def collect_all_info(self) -> Dict:
        """
        收集所有信息
        
        Returns:
            完整的信息字典
        """
        # 扫描Git项目
        projects = self.find_git_projects()
        
        # 获取开发者信息
        developer_info = self.get_developer_info()
        
        # 收集所有项目信息
        projects_info = []
        projects_with_changes = 0
        
        for project_path in projects:
            info = self.get_project_info(project_path)
            if info:
                projects_info.append(info)
                if info.get('has_uncommitted_changes'):
                    projects_with_changes += 1
        
        # 构建完整数据
        return {
            "scan_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "base_directory": str(self.base_dir).replace('\\', '/'),
            "scan_depth": self.depth,
            "developer": developer_info,
            "projects": projects_info,
            "summary": {
                "total_projects": len(projects_info),
                "projects_with_changes": projects_with_changes
            }
        }
    
    def print_summary(self, data: Dict):
        """打印摘要信息"""
        print("\n" + "=" * 60)
        print("开发者信息收集完成")
        print("=" * 60)
        print(f"开发者: {data['developer']['name']} <{data['developer']['email']}>")
        print(f"扫描目录: {data['base_directory']}")
        print(f"扫描深度: {data['scan_depth']} 层")
        print(f"找到项目: {data['summary']['total_projects']} 个")
        print(f"有未提交修改: {data['summary']['projects_with_changes']} 个")
        print("=" * 60)
        
        if data['projects']:
            print("\n项目列表:")
            for i, proj in enumerate(data['projects'], 1):
                status = "🔴 有修改" if proj['has_uncommitted_changes'] else "✅ 干净"
                print(f"{i}. [{status}] {proj['project_name']} ({proj['current_branch']})")
        print()


def main():
    """主函数"""
    parser = argparse.ArgumentParser(
        description="开发者信息收集工具 - Code Review信息准备",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例用法:
  python collect_info.py
  python collect_info.py --base-dir "D:\\projects" --depth 2
  python collect_info.py --pretty
  python collect_info.py -v
        """
    )
    
    parser.add_argument(
        '--base-dir', '-d',
        default='.',
        help='扫描的基础目录（默认: 当前目录）'
    )
    
    parser.add_argument(
        '--depth',
        type=int,
        default=3,
        choices=range(1, 6),
        metavar='1-5',
        help='扫描深度，1-5层（默认: 3）'
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
    
    # 创建收集器
    collector = DeveloperInfoCollector(
        base_dir=args.base_dir,
        depth=args.depth,
        verbose=args.verbose
    )
    
    # 收集信息
    data = collector.collect_all_info()
    
    # 打印摘要
    collector.print_summary(data)
    
    # 输出JSON到控制台
    print("\n" + "=" * 60)
    print("完整数据（JSON格式）")
    print("=" * 60)
    indent = 2 if args.pretty else None
    print(json.dumps(data, ensure_ascii=False, indent=indent))
    print()


if __name__ == "__main__":
    main()
