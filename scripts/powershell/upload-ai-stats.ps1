#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Upload git-ai AI code usage statistics to a remote API.
.DESCRIPTION
    Collects commit-level AI authorship statistics via `git-ai stats` and
    POSTs them to the configured remote endpoint.

    Data flow:
    1. Determine target commits (branch diff, date range, or explicit list).
    2. For each commit, call `git-ai stats <sha> --json`.
    3. POST each result to the remote API (upsert by repo_url + commit_sha).

    Environment variables:
    - GIT_AI_REPORT_REMOTE_URL:      Preferred. Full request URL of the remote API.
    - GIT_AI_REPORT_REMOTE_ENDPOINT: Optional. Base URL of the remote API.
    - GIT_AI_REPORT_REMOTE_PATH:     Optional. Request path when using ENDPOINT.
    - GIT_AI_REPORT_REMOTE_API_KEY:  Optional. Bearer token for authentication.
.EXAMPLE
    .\.specify\scripts\powershell\upload-ai-stats.ps1
.EXAMPLE
    .\.specify\scripts\powershell\upload-ai-stats.ps1 -DryRun
.EXAMPLE
    .\.specify\scripts\powershell\upload-ai-stats.ps1 -Since "2026-04-01" -Until "2026-04-14"
.EXAMPLE
    .\.specify\scripts\powershell\upload-ai-stats.ps1 -Commits "abc123,def456"
#>
[CmdletBinding()]
param(
    [string]$Since,
    [string]$Until,
    [string]$Commits,
    [string]$Author,
    [switch]$Json,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/common.ps1"

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# ─── Functions ────────────────────────────────────────────────

function Get-TargetCommits {
    $repoRoot = Get-RepoRoot
    $gitArgs = @("log", "--format=%H")

    if ($Commits) {
        return $Commits -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    if ($Since) { $gitArgs += "--since=$Since" }
    if ($Until) { $gitArgs += "--until=$Until" }
    if ($Author) { $gitArgs += "--author=$Author" }

    if (-not $Since -and -not $Until) {
        $baseBranch = git -C $repoRoot symbolic-ref refs/remotes/origin/HEAD 2>$null
        if (-not $baseBranch) { $baseBranch = "origin/main" }
        $baseBranch = $baseBranch -replace 'refs/remotes/', ''
        $gitArgs += "$baseBranch..HEAD"
    }

    $result = git -C $repoRoot @gitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return ($result -split "`n" | Where-Object { $_ })
}

function Get-CommitAiStats {
    param([string]$CommitSha)

    $repoRoot = Get-RepoRoot
    $noteInfo = git -C $repoRoot notes --ref=ai list $CommitSha 2>$null
    $hasAuthorshipNote = ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($noteInfo))

    $statsJson = git-ai stats $CommitSha --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $statsJson) {
        Write-Warning "[upload-ai-stats] Failed to read stats for $($CommitSha.Substring(0,7))"
        return $null
    }

    return @{
        HasAuthorshipNote = $hasAuthorshipNote
        Stats = ($statsJson | ConvertFrom-Json)
    }
}

function Get-UploadRemoteConfig {
    $url = $env:GIT_AI_REPORT_REMOTE_URL
    if ($url) {
        return @{
            Url = $url
            ApiKey = $env:GIT_AI_REPORT_REMOTE_API_KEY
        }
    }

    $endpoint = $env:GIT_AI_REPORT_REMOTE_ENDPOINT
    $path = $env:GIT_AI_REPORT_REMOTE_PATH
    if (-not $endpoint -or -not $path) {
        Write-Warning "[upload-ai-stats] Configure GIT_AI_REPORT_REMOTE_URL, or set both GIT_AI_REPORT_REMOTE_ENDPOINT and GIT_AI_REPORT_REMOTE_PATH."
        return $null
    }

    return @{
        Url = "{0}/{1}" -f $endpoint.TrimEnd('/'), $path.TrimStart('/')
        ApiKey = $env:GIT_AI_REPORT_REMOTE_API_KEY
    }
}

function Send-AiStatsToRemote {
    param(
        [string]$CommitSha,
        [object]$Stats,
        [string]$ProjectName,
        [bool]$HasAuthorshipNote,
        [hashtable]$RemoteConfig
    )

    $repoRoot = Get-RepoRoot
    $commitInfo = git -C $repoRoot log -1 --format="%ae|%s|%aI" $CommitSha 2>$null
    $parts = $commitInfo -split '\|', 3
    $repoUrl = git -C $repoRoot remote get-url origin 2>$null
    $branch = git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null

    $payload = @{
        repo_url                  = $repoUrl
        project_name              = $ProjectName
        commit_sha                = $CommitSha
        commit_message            = $parts[1]
        author                    = $parts[0]
        branch                    = $branch
        timestamp                 = $parts[2]
        source                    = "manual"
        review_document_id        = $null
        has_authorship_note       = $HasAuthorshipNote
        authorship_schema_version = "authorship/3.0.0"
        stats                     = $Stats
    } | ConvertTo-Json -Depth 10

    $headers = @{ "Content-Type" = "application/json" }
    if ($RemoteConfig.ApiKey) { $headers["Authorization"] = "Bearer $($RemoteConfig.ApiKey)" }

    try {
        Invoke-RestMethod -Uri $RemoteConfig.Url `
            -Method POST -Body $payload -Headers $headers -TimeoutSec 10 | Out-Null
        return $true
    } catch {
        Write-Warning "[upload-ai-stats] Upload failed for $($CommitSha.Substring(0,7)): $_"
        return $false
    }
}

# ─── Main ─────────────────────────────────────────────────────

$gitAiCmd = Get-Command git-ai -ErrorAction SilentlyContinue
if (-not $gitAiCmd) {
    Write-Error "[upload-ai-stats] git-ai is not installed. Run: .\.specify\scripts\powershell\post-init.ps1"
    exit 1
}

$commits = Get-TargetCommits
if (-not $commits -or $commits.Count -eq 0) {
    Write-Host "[upload-ai-stats] No matching commits found (current branch may equal base branch)."
    exit 0
}

Write-Host "[upload-ai-stats] Found $($commits.Count) commit(s), collecting AI statistics..."
Write-Host ""

$repoRoot = Get-RepoRoot
$repoUrl = git -C $repoRoot remote get-url origin 2>$null
$projectName = ($repoUrl -split '/')[-1] -replace '\.git$', ''
$remoteConfig = $null

if (-not $DryRun) {
    $remoteConfig = Get-UploadRemoteConfig
    if (-not $remoteConfig) {
        exit 1
    }
}

$results = @()
$successCount = 0
$skipCount = 0
$failCount = 0
$withoutNoteCount = 0

foreach ($sha in $commits) {
    $shortSha = $sha.Substring(0, [Math]::Min(7, $sha.Length))

    $statsResult = Get-CommitAiStats -CommitSha $sha
    if (-not $statsResult) {
        Write-Host "  $shortSha : stats read failed, skipping" -ForegroundColor DarkGray
        $skipCount++
        continue
    }

    $stats = $statsResult.Stats
    $hasAuthorshipNote = [bool]$statsResult.HasAuthorshipNote
    if (-not $hasAuthorshipNote) { $withoutNoteCount++ }

    if ($DryRun) {
        if ($hasAuthorshipNote) {
            Write-Host "  $shortSha : [preview] note=yes, added=$($stats.git_diff_added_lines), ai_additions=$($stats.ai_additions), mixed=$($stats.mixed_additions)" -ForegroundColor Cyan
        } else {
            Write-Host "  $shortSha : [preview] note=no, added=$($stats.git_diff_added_lines), unknown=$($stats.unknown_additions)" -ForegroundColor Yellow
        }
        $results += @{ sha = $sha; status = "dry-run"; has_authorship_note = $hasAuthorshipNote; stats = $stats }
    } else {
        $ok = Send-AiStatsToRemote -CommitSha $sha -Stats $stats -ProjectName $projectName -HasAuthorshipNote:$hasAuthorshipNote -RemoteConfig $remoteConfig
        if ($ok) {
            if ($hasAuthorshipNote) {
                Write-Host "  $shortSha : uploaded (note=yes, added=$($stats.git_diff_added_lines), ai=$($stats.ai_additions), mixed=$($stats.mixed_additions))" -ForegroundColor Green
            } else {
                Write-Host "  $shortSha : uploaded (note=no, added=$($stats.git_diff_added_lines), unknown=$($stats.unknown_additions))" -ForegroundColor Green
            }
            $successCount++
        } else {
            Write-Host "  $shortSha : upload failed" -ForegroundColor Red
            $failCount++
        }
        $results += @{ sha = $sha; status = $(if ($ok) {"uploaded"} else {"failed"}); has_authorship_note = $hasAuthorshipNote; stats = $stats }
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "[upload-ai-stats] [preview] $($results.Count) commit(s) collected, $withoutNoteCount without authorship note, $skipCount skipped"
    Write-Host "[upload-ai-stats] Remove -DryRun to upload."
} else {
    Write-Host "[upload-ai-stats] Done: $successCount uploaded, $failCount failed, $skipCount skipped, $withoutNoteCount without authorship note"
}

if ($Json) {
    $results | ConvertTo-Json -Depth 10
}
