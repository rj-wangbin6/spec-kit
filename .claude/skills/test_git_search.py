#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
测试Git技能的仓库搜索功能
"""

import sys
from pathlib import Path

# 添加脚本路径
sys.path.insert(0, str(Path(__file__).parent.parent / 'git-commit-log' / 'scripts'))
sys.path.insert(0, str(Path(__file__).parent.parent / 'git-branch-sync' / 'scripts'))

from git_commit_log import GitCommitLog
from git_branch_sync import GitBranchSync

def test_commit_log_search():
    """测试git-commit-log的仓库搜索"""
    print("=" * 60)
    print("测试 git-commit-log 仓库搜索功能")
    print("=" * 60)
    
    # 测试从当前目录搜索（无限深度）
    print("\n1. 测试无限深度搜索...")
    tool = GitCommitLog(
        scan_repos=True,
        base_dir='.',
        scan_depth=0  # 无限深度
    )
    print(f"   找到 {len(tool.repos)} 个仓库")
    for repo in tool.repos[:5]:  # 只显示前5个
        print(f"   - {repo}")
    if len(tool.repos) > 5:
        print(f"   ... 还有 {len(tool.repos) - 5} 个")
    
    # 测试深度限制
    print("\n2. 测试深度限制（depth=1）...")
    tool = GitCommitLog(
        scan_repos=True,
        base_dir='.',
        scan_depth=1
    )
    print(f"   找到 {len(tool.repos)} 个仓库")
    
    # 测试深度限制2
    print("\n3. 测试深度限制（depth=2）...")
    tool = GitCommitLog(
        scan_repos=True,
        base_dir='.',
        scan_depth=2
    )
    print(f"   找到 {len(tool.repos)} 个仓库")

def test_branch_sync_search():
    """测试git-branch-sync的仓库搜索"""
    print("\n" + "=" * 60)
    print("测试 git-branch-sync 仓库搜索功能")
    print("=" * 60)
    
    sync = GitBranchSync(verbose=True)
    
    # 测试无限深度搜索
    print("\n1. 测试无限深度搜索...")
    repos = sync.find_git_repos('.', depth=0)
    print(f"   找到 {len(repos)} 个仓库")
    
    # 测试深度限制
    print("\n2. 测试深度限制（depth=1）...")
    repos = sync.find_git_repos('.', depth=1)
    print(f"   找到 {len(repos)} 个仓库")
    
    # 测试深度限制2
    print("\n3. 测试深度限制（depth=2）...")
    repos = sync.find_git_repos('.', depth=2)
    print(f"   找到 {len(repos)} 个仓库")

if __name__ == '__main__':
    try:
        test_commit_log_search()
        test_branch_sync_search()
        print("\n" + "=" * 60)
        print("✅ 测试完成！")
        print("=" * 60)
    except Exception as e:
        print(f"\n❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()
