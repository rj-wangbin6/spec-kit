#!/usr/bin/env bash
# Post-init hook for Speckit: automatically installs and configures git-ai.
#
# This script is called by `specify init` after project scaffolding completes.
# It ensures git-ai is installed via the configured GitHub release source and hooks are
# configured so that every commit automatically records AI authorship data.
#
# Behavior:
#   1. Detect whether git-ai is already installed.
#   2. If git-ai is missing, or if --force is provided, run the configured installer.
#   3. If git-ai already exists and --force is not provided, keep the current install.
#   4. Refresh git-ai install-hooks configuration.
#   5. Set git-ai prompt storage to notes mode for prompt text preservation.
#
# Environment variables:
#   GIT_AI_INSTALLER_URL  Override the default installer download URL.
#   GIT_AI_GITHUB_REPO   Override the default GitHub repository used by the installer.
#   GIT_AI_RELEASE_TAG   Override the release tag used by the installer.
#   GIT_AI_LOCAL_BINARY  Use a prebuilt local git-ai binary instead of downloading one.
#
# Usage:
#   .specify/scripts/bash/post-init.sh
#   .specify/scripts/bash/post-init.sh --force   # Force git-ai reinstall via the configured release source
#   .specify/scripts/bash/post-init.sh --skip     # Skip git-ai setup entirely

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

GIT_AI_DEFAULT_GITHUB_REPO="rj-gaoang/git-ai"
GIT_AI_DEFAULT_RELEASE_TAG="latest"
GIT_AI_INSTALL_SCRIPT_URL="${GIT_AI_INSTALLER_URL:-https://github.com/${GIT_AI_DEFAULT_GITHUB_REPO}/releases/latest/download/install.sh}"
export GIT_AI_GITHUB_REPO="${GIT_AI_GITHUB_REPO:-$GIT_AI_DEFAULT_GITHUB_REPO}"
export GIT_AI_RELEASE_TAG="${GIT_AI_RELEASE_TAG:-$GIT_AI_DEFAULT_RELEASE_TAG}"
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
    detail "GitHub repo: $GIT_AI_GITHUB_REPO"
    detail "Release tag: $GIT_AI_RELEASE_TAG"
    if [ -n "${GIT_AI_LOCAL_BINARY:-}" ]; then
        detail "Local binary override: $GIT_AI_LOCAL_BINARY"
    fi
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

configure_git_ai_prompt_storage_notes() {
    local git_ai_cmd
    if ! git_ai_cmd="$(get_git_ai_command)"; then
        warn "git-ai is not available in this shell, so prompt_storage could not be set to notes automatically."
        return
    fi

    info "Configuring git-ai prompt storage to notes mode..."
    detail "Using git-ai command for prompt_storage: $git_ai_cmd"
    if ! "$git_ai_cmd" config set prompt_storage notes; then
        warn "git-ai config set prompt_storage notes exited with non-zero status. Run it manually if prompt text does not persist."
        return
    fi

    local prompt_storage
    prompt_storage="$($git_ai_cmd config prompt_storage 2>/dev/null | head -n 1 || true)"
    if [ "$prompt_storage" = "notes" ]; then
        success "git-ai prompt_storage is now notes."
    else
        warn "git-ai prompt_storage verification did not return notes. Run 'git-ai config prompt_storage' manually to confirm."
    fi
}

# ─── Main ─────────────────────────────────────────────────────

info "Starting git-ai post-init."
detail "Working directory: $(pwd)"
detail "Force=$FORCE; Skip=$SKIP"
detail "Configured installer URL: $GIT_AI_INSTALL_SCRIPT_URL"
detail "Configured GitHub repo: $GIT_AI_GITHUB_REPO"
detail "Configured release tag: $GIT_AI_RELEASE_TAG"

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
        info "Force requested. Re-running the configured git-ai installer."
        if ! invoke_git_ai_installer; then
            warn "git-ai installation failed."
            warn "You can rerun this script later without blocking Spec Kit initialization."
            exit 0
        fi
    else
        info "git-ai already installed. Skipping remote installer because --force was not provided."
    fi
else
    info "git-ai not detected. Running the configured installer."
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
configure_git_ai_prompt_storage_notes

success "git-ai post-init completed."
echo "[speckit/post-init] Future git commits in this repository will record AI authorship data when git-ai is available."
