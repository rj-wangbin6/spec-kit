#!/bin/bash
# Spec Kit自动同步脚本
# 功能: 从GitHub拉取最新版本,构建wheel包,下载跨平台依赖

set -e  # 遇到错误立即退出

REPO_DIR="/opt/spec-kit-packages/sync-workspace/spec-kit-repo"
PACKAGES_DIR="/opt/spec-kit-packages/packages"
LOG_FILE="/opt/spec-kit-packages/logs/sync-$(date +%Y%m%d-%H%M%S).log"
UV_BIN="/root/.local/bin/uv"

echo "========================================" | tee -a "$LOG_FILE"
echo "Spec Kit同步开始: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# 1. 检查GitHub连通性
echo "[1/6] 检查GitHub连通性..." | tee -a "$LOG_FILE"
if ! curl -s --connect-timeout 5 https://api.github.com > /dev/null; then
    echo "错误: 无法连接GitHub,请检查网络" | tee -a "$LOG_FILE"
    exit 1
fi
echo "✓ GitHub连接正常" | tee -a "$LOG_FILE"

# 2. 拉取最新代码
echo "[2/6] 拉取最新代码..." | tee -a "$LOG_FILE"
cd "$REPO_DIR"
OLD_COMMIT=$(git rev-parse --short HEAD)
git fetch origin main 2>&1 | tee -a "$LOG_FILE"
git reset --hard origin/main 2>&1 | tee -a "$LOG_FILE"
NEW_COMMIT=$(git rev-parse --short HEAD)

if [ "$OLD_COMMIT" = "$NEW_COMMIT" ]; then
    echo "✓ 已是最新版本 ($NEW_COMMIT)" | tee -a "$LOG_FILE"
else
    echo "✓ 更新成功: $OLD_COMMIT -> $NEW_COMMIT" | tee -a "$LOG_FILE"
fi

# 3. 构建wheel包
echo "[3/6] 构建wheel包..." | tee -a "$LOG_FILE"
rm -rf dist/ build/ *.egg-info
"$UV_BIN" build 2>&1 | tee -a "$LOG_FILE"

# 4. 拷贝wheel到发布目录
echo "[4/6] 更新spec-kit包..." | tee -a "$LOG_FILE"
WHL_FILE=$(ls -t dist/*.whl | head -1)
cp -f "$WHL_FILE" "$PACKAGES_DIR/spec-kit/"
echo "✓ 已复制: $(basename $WHL_FILE)" | tee -a "$LOG_FILE"

# 5. 更新Windows依赖(Python 3.11)
echo "[5/7] 更新Windows依赖..." | tee -a "$LOG_FILE"
TEMP_DEPS="/tmp/win-deps-$(date +%s).txt"
"$UV_BIN" pip compile pyproject.toml --python-version 3.11 --python-platform windows 2>/dev/null | grep -E '^[a-zA-Z]' > "$TEMP_DEPS"

python3 -m pip download -r "$TEMP_DEPS" \
    --python-version 3.11 \
    --platform win_amd64 \
    --only-binary=:all: \
    -d "$PACKAGES_DIR/dependencies/" 2>&1 | tee -a "$LOG_FILE"

rm -f "$TEMP_DEPS"
echo "✓ Windows依赖更新完成" | tee -a "$LOG_FILE"

# 6. 更新macOS依赖(Python 3.11)
echo "[6/7] 更新macOS依赖..." | tee -a "$LOG_FILE"
TEMP_MAC_DEPS="/tmp/mac-deps-$(date +%s).txt"
"$UV_BIN" pip compile pyproject.toml --python-version 3.11 --python-platform macos 2>/dev/null | grep -E '^[a-zA-Z]' > "$TEMP_MAC_DEPS"

# 下载macOS x86_64版本(Intel Mac)
python3 -m pip download -r "$TEMP_MAC_DEPS" \
    --python-version 3.11 \
    --platform macosx_10_9_x86_64 \
    --only-binary=:all: \
    -d "$PACKAGES_DIR/dependencies/" 2>&1 | tee -a "$LOG_FILE"

# 下载macOS ARM64版本(Apple Silicon)
python3 -m pip download -r "$TEMP_MAC_DEPS" \
    --python-version 3.11 \
    --platform macosx_11_0_arm64 \
    --only-binary=:all: \
    -d "$PACKAGES_DIR/dependencies/" 2>&1 | tee -a "$LOG_FILE"

rm -f "$TEMP_MAC_DEPS"
echo "✓ macOS依赖更新完成" | tee -a "$LOG_FILE"

# 7. 统计结果
echo "[7/7] 同步完成统计..." | tee -a "$LOG_FILE"
SPEC_SIZE=$(du -sh "$PACKAGES_DIR/spec-kit/" | awk '{print $1}')
DEPS_COUNT=$(ls "$PACKAGES_DIR/dependencies/"*.whl 2>/dev/null | wc -l)
DEPS_SIZE=$(du -sh "$PACKAGES_DIR/dependencies/" | awk '{print $1}')

echo "========================================" | tee -a "$LOG_FILE"
echo "同步完成摘要:" | tee -a "$LOG_FILE"
echo "  - Commit版本: $NEW_COMMIT" | tee -a "$LOG_FILE"
echo "  - Wheel包: $(basename $WHL_FILE)" | tee -a "$LOG_FILE"
echo "  - 项目包大小: $SPEC_SIZE" | tee -a "$LOG_FILE"
echo "  - 依赖包数量: $DEPS_COUNT 个" | tee -a "$LOG_FILE"
echo "  - 依赖包大小: $DEPS_SIZE" | tee -a "$LOG_FILE"
echo "  - 完成时间: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

exit 0
