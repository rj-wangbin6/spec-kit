#!/usr/bin/env pwsh
<#!
.SYNOPSIS
    Post-init hook for Speckit: automatically installs, updates, and configures git-ai.
.DESCRIPTION
    This script is called by `specify init` after project scaffolding completes.
    It ensures git-ai is installed, upgraded when already present, and hooks are
    configured so that every commit automatically records AI authorship data.

    Behaviour:
    1. Detect whether git-ai is already installed (PATH or default install path).
    2. If already installed, attempt `git-ai upgrade` (or `git-ai upgrade --force`).
    3. If not installed, or if upgrade fails, download and run the official installer.
    4. Refresh git-ai install-hooks configuration.
    5. All failures emit warnings but never block Speckit initialization.

    Environment variables:
    - GIT_AI_INSTALLER_URL: Override the default installer download URL.
.EXAMPLE
    .\.specify\scripts\powershell\post-init.ps1
.EXAMPLE
    .\.specify\scripts\powershell\post-init.ps1 -Force   # Force git-ai reinstall/upgrade even if present
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

$GitAiInstallScriptUrl = if ($env:GIT_AI_INSTALLER_URL) {
    $env:GIT_AI_INSTALLER_URL
} else {
    'https://usegitai.com/install.ps1'
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
        Write-PostInitInfo "Downloading git-ai installer from GitHub..."
        Invoke-WebRequest -Uri $GitAiInstallScriptUrl -OutFile $tempInstaller -UseBasicParsing
        & $tempInstaller
    } finally {
        Remove-Item -LiteralPath $tempInstaller -ErrorAction SilentlyContinue
    }
}

function Invoke-GitAiUpgrade {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GitAiCommand,
        [switch]$ForceUpgrade
    )

    $upgradeArgs = @('upgrade')
    if ($ForceUpgrade) {
        $upgradeArgs += '--force'
    }

    try {
        Write-PostInitInfo 'Checking for git-ai updates...'
        & $GitAiCommand @upgradeArgs | Out-Host
        if ($LASTEXITCODE -eq 0) {
            return $true
        }

        Write-PostInitWarning "git-ai upgrade exited with code $LASTEXITCODE."
        return $false
    } catch {
        Write-PostInitWarning "git-ai upgrade failed: $_"
        return $false
    }
}

function Refresh-GitAiInstallHooks {
    $gitAiCommand = Get-GitAiCommand

    if (-not $gitAiCommand) {
        Write-PostInitWarning "git-ai is not available in this shell. The installer already ran install-hooks; if needed, run 'git-ai install-hooks' manually after your PATH is refreshed."
        return
    }

    try {
        Write-PostInitInfo 'Refreshing git-ai install-hooks configuration...'
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

# ─── Main ─────────────────────────────────────────────────────

if ($Skip) {
    Write-PostInitInfo 'Skipping git-ai setup because -Skip was provided.'
    exit 0
}

$existingCommand = Get-GitAiCommand
if ($existingCommand) {
    $version = & $existingCommand --version 2>$null
    if ($version) {
        Write-PostInitSuccess "git-ai detected: $version"
    } else {
        Write-PostInitSuccess 'git-ai detected.'
    }

    if (-not (Invoke-GitAiUpgrade -GitAiCommand $existingCommand -ForceUpgrade:$Force)) {
        Write-PostInitWarning 'Falling back to installer-based git-ai update.'
        try {
            Invoke-GitAiInstaller
        } catch {
            Write-PostInitWarning "git-ai installation failed: $_"
            Write-PostInitWarning 'You can rerun this script later without blocking Spec Kit initialization.'
            exit 0
        }
    }
} else {
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
    $version = & $resolvedCommand --version 2>$null
    if ($version) {
        Write-PostInitSuccess "git-ai ready: $version"
    } else {
        Write-PostInitSuccess 'git-ai ready.'
    }
} else {
    Write-PostInitWarning 'git-ai setup completed, but the command is not yet available in this shell. The default install path will still be used if present.'
}

Refresh-GitAiInstallHooks

Write-PostInitSuccess 'git-ai post-init completed.'
Write-Host '[speckit/post-init] Future git commits in this repository will record AI authorship data when git-ai is available.'
