#!/usr/bin/env bash
# Post-init hook for Speckit: automatically installs and configures git-ai.
#
# This script is called by `specify init` after project scaffolding completes.
# It ensures git-ai is installed and hooks are configured so that every commit
# automatically records AI authorship data.
#
# Environment variables:
#   GIT_AI_INSTALLER_URL  Override the default installer download URL.
#
# Usage:
#   .specify/scripts/bash/post-init.sh
#   .specify/scripts/bash/post-init.sh --force   # Re-install even if present
#   .specify/scripts/bash/post-init.sh --skip     # Skip git-ai setup entirely

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

GIT_AI_INSTALL_SCRIPT_URL="${GIT_AI_INSTALLER_URL:-https://usegitai.com/install.sh}"
GIT_AI_EXECUTABLE_PATH="$HOME/.git-ai/bin/git-ai"

FORCE=false
SKIP=false

for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=true ;;
        --skip|-s)  SKIP=true ;;
    esac
done

info()    { echo -e "\033[36m[speckit/post-init] $*\033[0m"; }
success() { echo -e "\033[32m[speckit/post-init] $*\033[0m"; }
warn()    { echo -e "\033[33m[speckit/post-init] WARNING: $*\033[0m" >&2; }

get_git_ai_command() {
    if command -v git-ai &>/dev/null; then
        command -v git-ai
        return 0
    fi
    if [ -x "$GIT_AI_EXECUTABLE_PATH" ]; then
        echo "$GIT_AI_EXECUTABLE_PATH"
        return 0
    fi
    return 1
}

invoke_git_ai_installer() {
    local tmp_installer
    tmp_installer="$(mktemp /tmp/git-ai-install-XXXXXX.sh)"

    info "Downloading git-ai installer..."
    if command -v curl &>/dev/null; then
        curl -fsSL "$GIT_AI_INSTALL_SCRIPT_URL" -o "$tmp_installer"
    elif command -v wget &>/dev/null; then
        wget -qO "$tmp_installer" "$GIT_AI_INSTALL_SCRIPT_URL"
    else
        warn "Neither curl nor wget found. Cannot download git-ai installer."
        rm -f "$tmp_installer"
        return 1
    fi

    chmod +x "$tmp_installer"
    bash "$tmp_installer"
    local rc=$?
    rm -f "$tmp_installer"
    return $rc
}

refresh_git_ai_install_hooks() {
    local git_ai_cmd
    if ! git_ai_cmd="$(get_git_ai_command)"; then
        warn "git-ai is not available in this shell. The installer already ran install-hooks; if needed, run 'git-ai install-hooks' manually after your PATH is refreshed."
        return
    fi

    info "Refreshing git-ai install-hooks configuration..."
    if "$git_ai_cmd" install-hooks; then
        success "git-ai install-hooks completed successfully."
    else
        warn "git-ai install-hooks exited with non-zero status. Run it manually if the integration was not refreshed."
    fi
}

# ─── Main ─────────────────────────────────────────────────────

if [ "$SKIP" = true ]; then
    info "Skipping git-ai setup because --skip was provided."
    exit 0
fi

if git_ai_cmd="$(get_git_ai_command)" && [ "$FORCE" = false ]; then
    version=$("$git_ai_cmd" --version 2>/dev/null || true)
    if [ -n "$version" ]; then
        success "git-ai already installed: $version"
    else
        success "git-ai already installed."
    fi
else
    if ! invoke_git_ai_installer; then
        warn "git-ai installation failed."
        warn "You can rerun this script later without blocking Spec Kit initialization."
        exit 0
    fi

    if git_ai_cmd="$(get_git_ai_command)"; then
        version=$("$git_ai_cmd" --version 2>/dev/null || true)
        if [ -n "$version" ]; then
            success "git-ai installed successfully: $version"
        else
            success "git-ai installed successfully."
        fi
    else
        warn "git-ai installer completed, but the command is not yet available in this shell."
    fi
fi

refresh_git_ai_install_hooks

success "git-ai post-init completed."
echo "[speckit/post-init] Future git commits in this repository will record AI authorship data when git-ai is available."
