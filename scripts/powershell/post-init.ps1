#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Post-init hook for Speckit: automatically installs and configures git-ai.
.DESCRIPTION
    This script is called by `specify init` after project scaffolding completes.
    It ensures git-ai is installed via the configured GitHub release source and hooks are
    configured so that every commit automatically records AI authorship data.

    Behaviour:
    1. Detect whether git-ai is already installed (PATH or default install path).
    2. If git-ai is missing, or if -Force is provided, download and run the configured installer.
    3. If git-ai already exists and -Force is not provided, keep the current install.
    4. Refresh git-ai install-hooks configuration.
    5. Set git-ai prompt storage to notes mode for prompt text preservation.
    6. Emit troubleshooting logs without blocking Speckit initialization on failure.

    Environment variables:
    - GIT_AI_INSTALLER_URL: Override the default installer download URL.
    - GIT_AI_GITHUB_REPO:  Override the default GitHub repository used by the installer.
    - GIT_AI_RELEASE_TAG:  Override the release tag used by the installer.
    - GIT_AI_LOCAL_BINARY: Use a prebuilt local git-ai binary instead of downloading one.
.EXAMPLE
    .\.specify\scripts\powershell\post-init.ps1
.EXAMPLE
    .\.specify\scripts\powershell\post-init.ps1 -Force   # Force git-ai reinstall via the configured release source
.EXAMPLE
    .\.specify\scripts\powershell\post-init.ps1 -Skip     # Skip git-ai setup entirely
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Skip
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/common.ps1"

$GitAiDefaultGithubRepo = 'rj-gaoang/git-ai'
$GitAiDefaultReleaseTag = 'latest'
$GitAiInstallScriptUrl = if ($env:GIT_AI_INSTALLER_URL) {
    $env:GIT_AI_INSTALLER_URL
} else {
    "https://github.com/$GitAiDefaultGithubRepo/releases/latest/download/install.ps1"
}
if ([string]::IsNullOrWhiteSpace($env:GIT_AI_GITHUB_REPO)) {
    $env:GIT_AI_GITHUB_REPO = $GitAiDefaultGithubRepo
}
if ([string]::IsNullOrWhiteSpace($env:GIT_AI_RELEASE_TAG)) {
    $env:GIT_AI_RELEASE_TAG = $GitAiDefaultReleaseTag
}
$GitAiExecutablePath = Join-Path $HOME '.git-ai\bin\git-ai.exe'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

function Write-PostInitInfo {
    param([string]$Message)
    Write-Host "[speckit/post-init] $Message" -ForegroundColor Cyan
}

function Write-PostInitSuccess {
    param([string]$Message)
    Write-Host "[speckit/post-init] $Message" -ForegroundColor Green
}

function Write-PostInitWarning {
    param([string]$Message)
    Write-Warning "[speckit/post-init] $Message"
}

function Write-PostInitDetail {
    param([string]$Message)
    Write-Host "[speckit/post-init] $Message" -ForegroundColor DarkGray
}

function Get-GitAiCommand {
    $command = Get-Command git-ai -ErrorAction SilentlyContinue
    if ($command -and $command.Path) {
        return $command.Path
    }

    if (Test-Path -LiteralPath $GitAiExecutablePath) {
        return $GitAiExecutablePath
    }

    return $null
}

function Invoke-GitAiInstaller {
    $tempInstaller = Join-Path ([System.IO.Path]::GetTempPath()) ("git-ai-install-{0}.ps1" -f [System.Guid]::NewGuid().ToString('N'))

    try {
        Write-PostInitInfo 'Downloading git-ai installer from the configured source...'
        Write-PostInitDetail "Installer URL: $GitAiInstallScriptUrl"
        Write-PostInitDetail "GitHub repo: $($env:GIT_AI_GITHUB_REPO)"
        Write-PostInitDetail "Release tag: $($env:GIT_AI_RELEASE_TAG)"
        if (-not [string]::IsNullOrWhiteSpace($env:GIT_AI_LOCAL_BINARY)) {
            Write-PostInitDetail "Local binary override: $($env:GIT_AI_LOCAL_BINARY)"
        }
        Write-PostInitDetail "Temporary installer path: $tempInstaller"
        Invoke-WebRequest -Uri $GitAiInstallScriptUrl -OutFile $tempInstaller -UseBasicParsing
        Write-PostInitDetail 'Installer download completed. Executing installer script...'
        & $tempInstaller
        Write-PostInitDetail 'Installer execution completed.'
    } finally {
        Remove-Item -LiteralPath $tempInstaller -ErrorAction SilentlyContinue
        Write-PostInitDetail 'Temporary installer file removed.'
    }
}

function Refresh-GitAiInstallHooks {
    $gitAiCommand = Get-GitAiCommand

    if (-not $gitAiCommand) {
        Write-PostInitWarning "git-ai is not available in this shell after setup. Checked PATH and '$GitAiExecutablePath'. The installer already ran install-hooks; if needed, run 'git-ai install-hooks' manually after your PATH is refreshed."
        return
    }

    try {
        Write-PostInitInfo 'Refreshing git-ai install-hooks configuration...'
        Write-PostInitDetail "Using git-ai command for install-hooks: $gitAiCommand"
        & $gitAiCommand install-hooks | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Write-PostInitSuccess 'git-ai install-hooks completed successfully.'
        } else {
            Write-PostInitWarning "git-ai install-hooks exited with code $LASTEXITCODE. Run it manually if the integration was not refreshed."
        }
    } catch {
        Write-PostInitWarning "install-hooks refresh failed: $_"
    }
}

function Set-GitAiPromptStorageNotes {
    $gitAiCommand = Get-GitAiCommand

    if (-not $gitAiCommand) {
        Write-PostInitWarning "git-ai is not available in this shell, so prompt_storage could not be set to notes automatically."
        return
    }

    try {
        Write-PostInitInfo 'Configuring git-ai prompt storage to notes mode...'
        Write-PostInitDetail "Using git-ai command for prompt_storage: $gitAiCommand"
        & $gitAiCommand config set prompt_storage notes | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-PostInitWarning "git-ai config set prompt_storage notes exited with code $LASTEXITCODE. Run it manually if prompt text does not persist."
            return
        }

        $promptStorage = (& $gitAiCommand config prompt_storage 2>$null | Select-Object -First 1)
        if ($promptStorage -and $promptStorage.Trim() -eq 'notes') {
            Write-PostInitSuccess 'git-ai prompt_storage is now notes.'
        } else {
            Write-PostInitWarning 'git-ai prompt_storage verification did not return notes. Run `git-ai config prompt_storage` manually to confirm.'
        }
    } catch {
        Write-PostInitWarning "prompt_storage configuration failed: $_"
    }
}

# ─── Main ─────────────────────────────────────────────────────

Write-PostInitInfo 'Starting git-ai post-init.'
Write-PostInitDetail "Working directory: $((Get-Location).Path)"
Write-PostInitDetail "Force=$([bool]$Force); Skip=$([bool]$Skip)"
Write-PostInitDetail "Configured installer URL: $GitAiInstallScriptUrl"
Write-PostInitDetail "Configured GitHub repo: $($env:GIT_AI_GITHUB_REPO)"
Write-PostInitDetail "Configured release tag: $($env:GIT_AI_RELEASE_TAG)"

if ($Skip) {
    Write-PostInitInfo 'Skipping git-ai setup because -Skip was provided.'
    exit 0
}

$existingCommand = Get-GitAiCommand
if ($existingCommand) {
    Write-PostInitDetail "Resolved existing git-ai command: $existingCommand"

    $version = & $existingCommand --version 2>$null
    if ($version) {
        Write-PostInitSuccess "git-ai detected: $version"
    } else {
        Write-PostInitSuccess 'git-ai detected.'
    }

    if ($Force) {
        Write-PostInitInfo 'Force requested. Re-running the configured git-ai installer.'
        try {
            Invoke-GitAiInstaller
        } catch {
            Write-PostInitWarning "git-ai installation failed: $_"
            Write-PostInitWarning 'You can rerun this script later without blocking Spec Kit initialization.'
            exit 0
        }
    } else {
        Write-PostInitInfo 'git-ai already installed. Skipping remote installer because -Force was not provided.'
    }
} else {
    Write-PostInitInfo 'git-ai not detected. Running the configured installer.'

    try {
        Invoke-GitAiInstaller
    } catch {
        Write-PostInitWarning "git-ai installation failed: $_"
        Write-PostInitWarning 'You can rerun this script later without blocking Spec Kit initialization.'
        exit 0
    }
}

$resolvedCommand = Get-GitAiCommand
if ($resolvedCommand) {
    Write-PostInitDetail "Resolved git-ai command after setup: $resolvedCommand"

    $version = & $resolvedCommand --version 2>$null
    if ($version) {
        Write-PostInitSuccess "git-ai ready: $version"
    } else {
        Write-PostInitSuccess 'git-ai ready.'
    }
} else {
    Write-PostInitWarning "git-ai setup completed, but the command is not yet available in this shell. Checked PATH and '$GitAiExecutablePath'."
}

Refresh-GitAiInstallHooks
Set-GitAiPromptStorageNotes

Write-PostInitSuccess 'git-ai post-init completed.'
Write-Host '[speckit/post-init] Future git commits in this repository will record AI authorship data when git-ai is available.'
