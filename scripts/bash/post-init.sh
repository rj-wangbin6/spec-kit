#!/usr/bin/env bash
# Post-init hook for Speckit: automatically installs and configures git-ai.
#
# This script is called by `specify init` after project scaffolding completes.
# It ensures git-ai is installed via the official installer flow and hooks are
# configured so that every commit automatically records AI authorship data.
#
# Behavior:
#   1. Detect whether git-ai is already installed.
#   2. If git-ai is missing, or if --force is provided, run the official installer.
#   3. If git-ai already exists and --force is not provided, keep the current install.
#   4. Refresh git-ai install-hooks configuration.
#
# Environment variables:
#   GIT_AI_INSTALLER_URL  Override the default installer download URL.
#
# Usage:
#   .specify/scripts/bash/post-init.sh
#   .specify/scripts/bash/post-init.sh --force   # Force git-ai reinstall via the remote installer
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
detail()  { echo -e "\033[90m[speckit/post-init] $*\033[0m"; }

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

    info "Downloading git-ai installer from the configured source..."
    detail "Installer URL: $GIT_AI_INSTALL_SCRIPT_URL"
    detail "Temporary installer path: $tmp_installer"
    if command -v curl &>/dev/null; then
        curl -fsSL "$GIT_AI_INSTALL_SCRIPT_URL" -o "$tmp_installer"
    elif command -v wget &>/dev/null; then
        wget -qO "$tmp_installer" "$GIT_AI_INSTALL_SCRIPT_URL"
    else
        warn "Neither curl nor wget found. Cannot download git-ai installer."
        rm -f "$tmp_installer"
        return 1
    fi

    detail "Installer download completed. Executing installer script..."
    chmod +x "$tmp_installer"
    bash "$tmp_installer"
    local rc=$?
    detail "Installer execution completed with exit code $rc."
    rm -f "$tmp_installer"
    detail "Temporary installer file removed."
    return $rc
}

refresh_git_ai_install_hooks() {
    local git_ai_cmd
    if ! git_ai_cmd="$(get_git_ai_command)"; then
        warn "git-ai is not available in this shell after setup. Checked PATH and '$GIT_AI_EXECUTABLE_PATH'. The installer already ran install-hooks; if needed, run 'git-ai install-hooks' manually after your PATH is refreshed."
        return
    fi

    info "Refreshing git-ai install-hooks configuration..."
    detail "Using git-ai command for install-hooks: $git_ai_cmd"
    if "$git_ai_cmd" install-hooks; then
        success "git-ai install-hooks completed successfully."
    else
        warn "git-ai install-hooks exited with non-zero status. Run it manually if the integration was not refreshed."
    fi
}

# ─── Main ─────────────────────────────────────────────────────

info "Starting git-ai post-init."
detail "Working directory: $(pwd)"
detail "Force=$FORCE; Skip=$SKIP"
detail "Configured installer URL: $GIT_AI_INSTALL_SCRIPT_URL"

if [ "$SKIP" = true ]; then
    info "Skipping git-ai setup because --skip was provided."
    exit 0
fi

if git_ai_cmd="$(get_git_ai_command)"; then
    detail "Resolved existing git-ai command: $git_ai_cmd"

    version=$("$git_ai_cmd" --version 2>/dev/null || true)
    if [ -n "$version" ]; then
        success "git-ai detected: $version"
    else
        success "git-ai detected."
    fi

    if [ "$FORCE" = true ]; then
        info "Force requested. Re-running the official git-ai installer."
        if ! invoke_git_ai_installer; then
            warn "git-ai installation failed."
            warn "You can rerun this script later without blocking Spec Kit initialization."
            exit 0
        fi
    else
        info "git-ai already installed. Skipping remote installer because --force was not provided."
    fi
else
    info "git-ai not detected. Running the official installer."
    if ! invoke_git_ai_installer; then
        warn "git-ai installation failed."
        warn "You can rerun this script later without blocking Spec Kit initialization."
        exit 0
    fi
fi

if git_ai_cmd="$(get_git_ai_command)"; then
    detail "Resolved git-ai command after setup: $git_ai_cmd"

    version=$("$git_ai_cmd" --version 2>/dev/null || true)
    if [ -n "$version" ]; then
        success "git-ai ready: $version"
    else
        success "git-ai ready."
    fi
else
    warn "git-ai setup completed, but the command is not yet available in this shell. Checked PATH and '$GIT_AI_EXECUTABLE_PATH'."
fi

refresh_git_ai_install_hooks

success "git-ai post-init completed."
echo "[speckit/post-init] Future git commits in this repository will record AI authorship data when git-ai is available."
