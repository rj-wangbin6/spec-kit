#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Upload git-ai AI code usage statistics to a remote API.
.DESCRIPTION
    Collects commit-level AI authorship statistics via `git-ai stats` and
    POSTs them to the configured remote endpoint as a single batch request.

    Data flow:
    1. Determine target commits (branch diff, date range, or explicit list).
    2. For each commit, call `git-ai stats <sha> --json`.
    3. POST one request containing all collected commits.
    4. Interpret the remote `results[]` response per commit.

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
    [string]$Source = 'manual',
    [string]$ReviewDocumentId,
    [switch]$Json,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$script:JsonOutputMode = [bool]$Json

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

function Join-ProcessArguments {
    param([string[]]$Arguments)

    return ($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"{0}"' -f ($_.Replace('"', '\"'))
        } else {
            $_
        }
    }) -join ' '
}

function Invoke-ProcessCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $resolvedFilePath = $FilePath
    if (-not [System.IO.Path]::IsPathRooted($resolvedFilePath)) {
        $commandInfo = Get-Command $FilePath -ErrorAction SilentlyContinue
        if ($commandInfo -and $commandInfo.Path) {
            $resolvedFilePath = $commandInfo.Path
        }
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $resolvedFilePath
    $startInfo.Arguments = Join-ProcessArguments -Arguments $Arguments
    $startInfo.WorkingDirectory = Get-RepoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return @{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

function Get-AuthorshipNoteLookup {
    param([string]$RepoRoot)

    if (-not $script:AuthorshipNoteLookupCache) {
        $script:AuthorshipNoteLookupCache = @{}
    }

    if ($script:AuthorshipNoteLookupCache.ContainsKey($RepoRoot)) {
        return $script:AuthorshipNoteLookupCache[$RepoRoot]
    }

    $lookup = @{}
    $noteLines = git -C $RepoRoot notes --ref=ai list 2>$null
    if ($LASTEXITCODE -eq 0 -and $noteLines) {
        foreach ($line in ($noteLines -split "`n" | Where-Object { $_.Trim() })) {
            $parts = $line.Trim() -split '\s+', 2
            if ($parts.Count -eq 2) {
                $lookup[$parts[1]] = $true
            }
        }
    }

    $script:AuthorshipNoteLookupCache[$RepoRoot] = $lookup
    return $lookup
}

function Test-CommitHasAuthorshipNote {
    param(
        [string]$RepoRoot,
        [string]$CommitSha
    )

    $lookup = Get-AuthorshipNoteLookup -RepoRoot $RepoRoot
    return $lookup.ContainsKey($CommitSha)
}

function Get-CommitAiStats {
    param([string]$CommitSha)

    $repoRoot = Get-RepoRoot
    $hasAuthorshipNote = Test-CommitHasAuthorshipNote -RepoRoot $repoRoot -CommitSha $CommitSha

    $statsCommandResult = Invoke-ProcessCapture -FilePath 'git-ai' -Arguments @('stats', $CommitSha, '--json')
    $statsJson = $statsCommandResult.StdOut
    if ($statsCommandResult.ExitCode -ne 0 -or -not $statsJson) {
        Write-UploadWarning "[upload-ai-stats] Failed to read stats for $($CommitSha.Substring(0,7))"
        return $null
    }

    try {
        $statsObject = $statsJson | ConvertFrom-Json
    } catch {
        Write-UploadWarning "[upload-ai-stats] Failed to parse stats JSON for $($CommitSha.Substring(0,7))"
        return $null
    }

    $fileStats = @(Get-CommitAiFileStats -CommitSha $CommitSha)
    if ($statsObject.PSObject.Properties.Name -contains 'files') {
        $statsObject.files = $fileStats
    } else {
        $statsObject | Add-Member -NotePropertyName 'files' -NotePropertyValue $fileStats
    }

    return @{
        HasAuthorshipNote = $hasAuthorshipNote
        Stats = $statsObject
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
        Write-UploadWarning "[upload-ai-stats] Configure GIT_AI_REPORT_REMOTE_URL, or set both GIT_AI_REPORT_REMOTE_ENDPOINT and GIT_AI_REPORT_REMOTE_PATH."
        return $null
    }

    return @{
        Url = "{0}/{1}" -f $endpoint.TrimEnd('/'), $path.TrimStart('/')
        ApiKey = $env:GIT_AI_REPORT_REMOTE_API_KEY
    }
}

function Get-ResponsePropertyValue {
    param(
        [object]$Object,
        [string[]]$Names
    )

    if (-not $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($name in $Names) {
            if ($Object.Contains($name)) {
                return $Object[$name]
            }
        }

        return $null
    }

    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            return $Object.$name
        }
    }

    return $null
}

function Convert-SnakeCaseNameToCamelCase {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -notmatch '_') {
        return $Name
    }

    $segments = $Name -split '_'
    if ($segments.Count -eq 0) {
        return $Name
    }

    $camelName = $segments[0]
    for ($i = 1; $i -lt $segments.Count; $i++) {
        if ([string]::IsNullOrEmpty($segments[$i])) {
            continue
        }

        $camelName += $segments[$i].Substring(0, 1).ToUpperInvariant() + $segments[$i].Substring(1)
    }

    return $camelName
}

function Get-ObjectEntries {
    param([object]$Object)

    if ($null -eq $Object) {
        return @()
    }

    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{
                Name = [string]$_.Key
                Value = $_.Value
            }
        })
    }

    return @($Object.PSObject.Properties | Where-Object {
        $_.MemberType -in @('NoteProperty', 'Property', 'AliasProperty', 'ScriptProperty')
    } | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.Name
            Value = $_.Value
        }
    })
}

function Write-UploadHost {
    param(
        [AllowEmptyString()][string]$Message = '',
        [string]$ForegroundColor
    )

    if ($script:JsonOutputMode) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($ForegroundColor)) {
        Write-Host $Message
    } else {
        Write-Host $Message -ForegroundColor $ForegroundColor
    }
}

function Write-UploadWarning {
    param([string]$Message)

    if ($script:JsonOutputMode) {
        [Console]::Error.WriteLine($Message)
        return
    }

    Write-Warning $Message
}

function Convert-ToObjectArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return @($Value)
    }

    return @($Value)
}

function Get-LineRangeCount {
    param([object]$RangeValue)

    if ($null -eq $RangeValue) {
        return 0
    }

    if ($RangeValue -is [string]) {
        $parsedLine = 0
        if ([int]::TryParse($RangeValue, [ref]$parsedLine)) {
            return 1
        }

        return 0
    }

    if ($RangeValue -is [ValueType]) {
        return 1
    }

    if ($RangeValue -is [System.Array]) {
        if ($RangeValue.Count -ge 2 -and $RangeValue[0] -is [ValueType] -and $RangeValue[1] -is [ValueType]) {
            return [Math]::Max(0, ([int]$RangeValue[1] - [int]$RangeValue[0] + 1))
        }

        $totalCount = 0
        foreach ($nestedRange in $RangeValue) {
            $totalCount += Get-LineRangeCount -RangeValue $nestedRange
        }

        return $totalCount
    }

    $startLine = Get-ResponsePropertyValue -Object $RangeValue -Names @('start', 'start_line', 'startLine')
    $endLine = Get-ResponsePropertyValue -Object $RangeValue -Names @('end', 'end_line', 'endLine')
    if ($null -ne $startLine -and $null -ne $endLine) {
        return [Math]::Max(0, ([int]$endLine - [int]$startLine + 1))
    }

    $lineNumber = Get-ResponsePropertyValue -Object $RangeValue -Names @('line', 'line_number', 'lineNumber')
    if ($null -ne $lineNumber) {
        return 1
    }

    return 0
}

function New-FileStatsAccumulator {
    param([string]$FilePath)

    return @{
        file_path = $FilePath
        git_diff_added_lines = 0
        git_diff_deleted_lines = 0
        ai_additions = 0
        human_additions = 0
        unknown_additions = 0
        tool_model_breakdown = @{}
    }
}

function Get-OrCreate-FileStatsAccumulator {
    param(
        [hashtable]$Lookup,
        [string]$FilePath
    )

    if (-not $Lookup.ContainsKey($FilePath)) {
        $Lookup[$FilePath] = New-FileStatsAccumulator -FilePath $FilePath
    }

    return $Lookup[$FilePath]
}

function Add-FileToolModelBreakdown {
    param(
        [hashtable]$FileStats,
        [hashtable]$PromptLookup,
        [string]$PromptId,
        [int]$LineCount
    )

    if ([string]::IsNullOrWhiteSpace($PromptId) -or $LineCount -le 0) {
        return
    }

    $tool = 'unknown'
    $model = $null

    if ($PromptLookup.ContainsKey($PromptId)) {
        $promptRecord = $PromptLookup[$PromptId]
        $agentId = Get-ResponsePropertyValue -Object $promptRecord -Names @('agent_id', 'agentId')
        $toolValue = Get-ResponsePropertyValue -Object $agentId -Names @('tool')
        $modelValue = Get-ResponsePropertyValue -Object $agentId -Names @('model')

        if ($toolValue) {
            $tool = [string]$toolValue
        }

        if ($modelValue) {
            $model = [string]$modelValue
        }
    }

    $breakdownKey = if ([string]::IsNullOrWhiteSpace($model)) {
        $tool
    } else {
        '{0}::{1}' -f $tool, $model
    }

    if (-not $FileStats['tool_model_breakdown'].ContainsKey($breakdownKey)) {
        $FileStats['tool_model_breakdown'][$breakdownKey] = @{ ai_additions = 0 }
    }

    $FileStats['tool_model_breakdown'][$breakdownKey]['ai_additions'] = [int]$FileStats['tool_model_breakdown'][$breakdownKey]['ai_additions'] + $LineCount
}

function Get-CommitAiFileStats {
    param([string]$CommitSha)

    $diffCommandResult = Invoke-ProcessCapture -FilePath 'git-ai' -Arguments @('diff', $CommitSha, '--json', '--include-stats')
    $diffJson = $diffCommandResult.StdOut
    if ($diffCommandResult.ExitCode -ne 0 -or -not $diffJson) {
        return @()
    }

    try {
        $diffData = $diffJson | ConvertFrom-Json
    } catch {
        Write-UploadWarning "[upload-ai-stats] Failed to parse file details for $($CommitSha.Substring(0,7))"
        return @()
    }

    $fileStatsLookup = @{}
    $promptLookup = @{}
    foreach ($promptEntry in (Get-ObjectEntries -Object (Get-ResponsePropertyValue -Object $diffData -Names @('prompts')))) {
        $promptLookup[[string]$promptEntry.Name] = $promptEntry.Value
    }

    $annotatedPromptIdsByFile = @{}
    foreach ($fileEntry in (Get-ObjectEntries -Object (Get-ResponsePropertyValue -Object $diffData -Names @('files')))) {
        $filePath = [string]$fileEntry.Name
        if ([string]::IsNullOrWhiteSpace($filePath)) {
            continue
        }

        $fileStats = Get-OrCreate-FileStatsAccumulator -Lookup $fileStatsLookup -FilePath $filePath
        $annotatedPromptIdsByFile[$filePath] = @{}

        $annotations = Get-ResponsePropertyValue -Object $fileEntry.Value -Names @('annotations')
        foreach ($annotationEntry in (Get-ObjectEntries -Object $annotations)) {
            $promptId = [string]$annotationEntry.Name
            if ([string]::IsNullOrWhiteSpace($promptId)) {
                continue
            }

            $lineCount = 0
            foreach ($rangeEntry in (Convert-ToObjectArray -Value $annotationEntry.Value)) {
                $lineCount += Get-LineRangeCount -RangeValue $rangeEntry
            }

            if ($lineCount -le 0) {
                continue
            }

            $annotatedPromptIdsByFile[$filePath][$promptId] = $true
            $fileStats['ai_additions'] = [int]$fileStats['ai_additions'] + $lineCount
            Add-FileToolModelBreakdown -FileStats $fileStats -PromptLookup $promptLookup -PromptId $promptId -LineCount $lineCount
        }
    }

    foreach ($hunk in (Convert-ToObjectArray -Value (Get-ResponsePropertyValue -Object $diffData -Names @('hunks')))) {
        $filePath = [string](Get-ResponsePropertyValue -Object $hunk -Names @('file_path', 'filePath'))
        if ([string]::IsNullOrWhiteSpace($filePath)) {
            continue
        }

        $fileStats = Get-OrCreate-FileStatsAccumulator -Lookup $fileStatsLookup -FilePath $filePath
        $startLine = Get-ResponsePropertyValue -Object $hunk -Names @('start_line', 'startLine')
        $endLine = Get-ResponsePropertyValue -Object $hunk -Names @('end_line', 'endLine')
        if ($null -eq $startLine -or $null -eq $endLine) {
            continue
        }

        $lineCount = [Math]::Max(0, ([int]$endLine - [int]$startLine + 1))
        if ($lineCount -le 0) {
            continue
        }

        $hunkKind = [string](Get-ResponsePropertyValue -Object $hunk -Names @('hunk_kind', 'hunkKind'))
        switch ($hunkKind) {
            'addition' {
                $fileStats['git_diff_added_lines'] = [int]$fileStats['git_diff_added_lines'] + $lineCount

                $promptId = [string](Get-ResponsePropertyValue -Object $hunk -Names @('prompt_id', 'promptId'))
                $humanId = [string](Get-ResponsePropertyValue -Object $hunk -Names @('human_id', 'humanId'))
                if (-not [string]::IsNullOrWhiteSpace($promptId)) {
                    if (-not $annotatedPromptIdsByFile.ContainsKey($filePath)) {
                        $annotatedPromptIdsByFile[$filePath] = @{}
                    }

                    if (-not $annotatedPromptIdsByFile[$filePath].ContainsKey($promptId)) {
                        $fileStats['ai_additions'] = [int]$fileStats['ai_additions'] + $lineCount
                        Add-FileToolModelBreakdown -FileStats $fileStats -PromptLookup $promptLookup -PromptId $promptId -LineCount $lineCount
                    }
                } elseif (-not [string]::IsNullOrWhiteSpace($humanId)) {
                    $fileStats['human_additions'] = [int]$fileStats['human_additions'] + $lineCount
                } else {
                    $fileStats['unknown_additions'] = [int]$fileStats['unknown_additions'] + $lineCount
                }
            }
            'deletion' {
                $fileStats['git_diff_deleted_lines'] = [int]$fileStats['git_diff_deleted_lines'] + $lineCount
            }
        }
    }

    return @($fileStatsLookup.Keys | Sort-Object | ForEach-Object {
        [pscustomobject]$fileStatsLookup[$_]
    })
}

function Get-NormalizedUploadSource {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'manual'
    }

    switch ($Value.ToLowerInvariant()) {
        'manual' { return 'manual' }
        'code-review' { return 'codeReview' }
        'code_review' { return 'codeReview' }
        'codereview' { return 'codeReview' }
        default { return $Value }
    }
}

function Convert-ToolModelBreakdownToDto {
    param([object]$Breakdown)

    if ($null -eq $Breakdown) {
        return @()
    }

    $items = @()
    foreach ($entry in (Get-ObjectEntries -Object $Breakdown)) {
        $entryName = [string]$entry.Name
        $tool = $entryName
        $model = $null

        $nameParts = $entryName -split '::', 2
        if ($nameParts.Count -eq 2) {
            $tool = $nameParts[0]
            $model = $nameParts[1]
        }

        $dtoItem = [ordered]@{
            tool = $tool
            model = $model
        }

        $convertedMetrics = Convert-ObjectKeysToCamelCase -Value $entry.Value
        foreach ($metricEntry in (Get-ObjectEntries -Object $convertedMetrics)) {
            $dtoItem[[string]$metricEntry.Name] = $metricEntry.Value
        }

        $items += [pscustomobject]$dtoItem
    }

    return @($items)
}

function Convert-ObjectKeysToCamelCase {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string] -or $Value -is [ValueType]) {
        return $Value
    }

    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { Convert-ObjectKeysToCamelCase -Value $_ })
    }

    $entries = Get-ObjectEntries -Object $Value
    if ($entries.Count -eq 0) {
        return $Value
    }

    $convertedObject = [ordered]@{}
    foreach ($entry in $entries) {
        $propertyName = [string]$entry.Name
        if ($propertyName -in @('tool_model_breakdown', 'toolModelBreakdown')) {
            $convertedObject['toolModelBreakdown'] = @(Convert-ToolModelBreakdownToDto -Breakdown $entry.Value)
            continue
        }

        $convertedName = Convert-SnakeCaseNameToCamelCase -Name $propertyName
        $convertedObject[$convertedName] = Convert-ObjectKeysToCamelCase -Value $entry.Value
    }

    return [pscustomobject]$convertedObject
}

function New-CommitUploadItem {
    param(
        [string]$CommitSha,
        [hashtable]$StatsResult
    )

    $repoRoot = Get-RepoRoot
    $commitInfo = git -C $repoRoot log -1 --format="%ae|%s|%aI" $CommitSha 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $commitInfo) {
        Write-UploadWarning "[upload-ai-stats] Failed to read commit metadata for $($CommitSha.Substring(0,7))"
        return $null
    }

    $parts = $commitInfo -split '\|', 3
    return @{
        commitSha = $CommitSha
        commitMessage = if ($parts.Count -ge 2) { $parts[1] } else { "" }
        author = if ($parts.Count -ge 1) { $parts[0] } else { "" }
        timestamp = if ($parts.Count -ge 3) { $parts[2] } else { "" }
        hasAuthorshipNote = [bool]$StatsResult.HasAuthorshipNote
        stats = (Convert-ObjectKeysToCamelCase -Value $StatsResult.Stats)
    }
}

function Test-BatchUploadItemSucceeded {
    param([object]$ResponseItem)

    $success = Get-ResponsePropertyValue -Object $ResponseItem -Names @('success', 'succeeded', 'isSuccess')
    if ($null -ne $success) {
        return [bool]$success
    }

    $status = Get-ResponsePropertyValue -Object $ResponseItem -Names @('status', 'result')
    if ($status) {
        return @('uploaded', 'upserted', 'created', 'updated', 'ok', 'success', 'accepted') -contains ([string]$status).ToLowerInvariant()
    }

    return $true
}

function Convert-BatchUploadResponse {
    param(
        [object]$Response,
        [object[]]$CommitItems
    )

    $responseItems = @(Get-ResponsePropertyValue -Object $Response -Names @('results', 'commits', 'items'))
    if (-not $responseItems -or $responseItems.Count -eq 0) {
        return @($CommitItems | ForEach-Object {
            @{
                commitSha = [string]$_.commitSha
                succeeded = $true
                status = 'uploaded'
                error = $null
                hasAuthorshipNote = [bool]$_.hasAuthorshipNote
                stats = $_.stats
            }
        })
    }

    $responseBySha = @{}
    foreach ($responseItem in $responseItems) {
        $sha = Get-ResponsePropertyValue -Object $responseItem -Names @('commitSha', 'commit_sha', 'sha')
        if ($sha) {
            $responseBySha[[string]$sha] = $responseItem
        }
    }

    $normalized = @()
    foreach ($commitItem in $CommitItems) {
        $responseItem = if ($responseBySha.ContainsKey([string]$commitItem.commitSha)) {
            $responseBySha[[string]$commitItem.commitSha]
        } else {
            $null
        }

        $succeeded = if ($responseItem) {
            Test-BatchUploadItemSucceeded -ResponseItem $responseItem
        } else {
            $true
        }

        $status = if ($responseItem) {
            Get-ResponsePropertyValue -Object $responseItem -Names @('status', 'result')
        } else {
            $null
        }

        if (-not $status) {
            $status = if ($succeeded) { 'uploaded' } else { 'failed' }
        }

        $error = if ($responseItem) {
            Get-ResponsePropertyValue -Object $responseItem -Names @('error', 'errorMessage', 'message', 'reason')
        } else {
            $null
        }

        $normalized += @{
            commitSha = [string]$commitItem.commitSha
            succeeded = $succeeded
            status = [string]$status
            error = if ($error) { [string]$error } else { $null }
            hasAuthorshipNote = [bool]$commitItem.hasAuthorshipNote
            stats = $commitItem.stats
        }
    }

    return $normalized
}

function Send-AiStatsBatchToRemote {
    param(
        [object[]]$CommitItems,
        [string]$ProjectName,
        [hashtable]$RemoteConfig,
        [string]$Source,
        [string]$ReviewDocumentId
    )

    $repoRoot = Get-RepoRoot
    $repoUrl = git -C $repoRoot remote get-url origin 2>$null
    $branch = git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null

    $payload = @{
        repoUrl = $repoUrl
        projectName = $ProjectName
        branch = $branch
        source = (Get-NormalizedUploadSource -Value $Source)
        reviewDocumentId = if ($ReviewDocumentId) { $ReviewDocumentId } else { $null }
        authorshipSchemaVersion = 'authorship/3.0.0'
        commits = $CommitItems
    } | ConvertTo-Json -Depth 12

    $headers = @{ "Content-Type" = "application/json" }
    if ($RemoteConfig.ApiKey) { $headers["Authorization"] = "Bearer $($RemoteConfig.ApiKey)" }

    try {
        $response = Invoke-RestMethod -Uri $RemoteConfig.Url `
            -Method POST -Body $payload -Headers $headers -TimeoutSec 10

        return @{
            Succeeded = $true
            Results = @(Convert-BatchUploadResponse -Response $response -CommitItems $CommitItems)
        }
    } catch {
        Write-UploadWarning "[upload-ai-stats] Batch upload failed: $_"

        return @{
            Succeeded = $false
            Results = @($CommitItems | ForEach-Object {
                @{
                    commitSha = [string]$_.commitSha
                    succeeded = $false
                    status = 'failed'
                    error = 'batch request failed'
                    hasAuthorshipNote = [bool]$_.hasAuthorshipNote
                    stats = $_.stats
                }
            })
        }
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
    if ($Json) {
        @() | ConvertTo-Json -Depth 10
    } else {
        Write-UploadHost "[upload-ai-stats] No matching commits found (current branch may equal base branch)."
    }
    exit 0
}

Write-UploadHost "[upload-ai-stats] Found $($commits.Count) commit(s), collecting AI statistics..."
Write-UploadHost ""

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
$preparedCommitItems = @()
$successCount = 0
$skipCount = 0
$failCount = 0
$withoutNoteCount = 0

foreach ($sha in $commits) {
    $shortSha = $sha.Substring(0, [Math]::Min(7, $sha.Length))

    $statsResult = Get-CommitAiStats -CommitSha $sha
    if (-not $statsResult) {
        Write-UploadHost "  $shortSha : stats read failed, skipping" -ForegroundColor DarkGray
        $skipCount++
        continue
    }

    $commitItem = New-CommitUploadItem -CommitSha $sha -StatsResult $statsResult
    if (-not $commitItem) {
        Write-UploadHost "  $shortSha : commit metadata read failed, skipping" -ForegroundColor DarkGray
        $skipCount++
        continue
    }

    $stats = $commitItem.stats
    $hasAuthorshipNote = [bool]$commitItem.hasAuthorshipNote
    if (-not $hasAuthorshipNote) { $withoutNoteCount++ }

    if ($DryRun) {
        if ($hasAuthorshipNote) {
            Write-UploadHost "  $shortSha : [preview] note=yes, added=$($stats.gitDiffAddedLines), aiAdditions=$($stats.aiAdditions), mixedAdditions=$($stats.mixedAdditions)" -ForegroundColor Cyan
        } else {
            Write-UploadHost "  $shortSha : [preview] note=no, added=$($stats.gitDiffAddedLines), unknownAdditions=$($stats.unknownAdditions)" -ForegroundColor Yellow
        }

        $results += @{
            commitSha = $sha
            succeeded = $true
            status = 'dry-run'
            hasAuthorshipNote = $hasAuthorshipNote
            stats = $stats
        }

        continue
    }

    $preparedCommitItems += $commitItem
}

if (-not $DryRun -and $preparedCommitItems.Count -gt 0) {
    $batchUploadResult = Send-AiStatsBatchToRemote -CommitItems $preparedCommitItems -ProjectName $projectName -RemoteConfig $remoteConfig -Source $Source -ReviewDocumentId $ReviewDocumentId

    foreach ($uploadResult in $batchUploadResult.Results) {
        $shortSha = $uploadResult.commitSha.Substring(0, [Math]::Min(7, $uploadResult.commitSha.Length))

        if ($uploadResult.succeeded) {
            if ($uploadResult.hasAuthorshipNote) {
                Write-UploadHost "  $shortSha : uploaded (note=yes, added=$($uploadResult.stats.gitDiffAddedLines), aiAdditions=$($uploadResult.stats.aiAdditions), mixedAdditions=$($uploadResult.stats.mixedAdditions))" -ForegroundColor Green
            } else {
                Write-UploadHost "  $shortSha : uploaded (note=no, added=$($uploadResult.stats.gitDiffAddedLines), unknownAdditions=$($uploadResult.stats.unknownAdditions))" -ForegroundColor Green
            }
            $successCount++
        } else {
            $errorSuffix = if ($uploadResult.error) { " ($($uploadResult.error))" } else { "" }
            Write-UploadHost "  $shortSha : upload failed$errorSuffix" -ForegroundColor Red
            $failCount++
        }

        $resultEntry = @{
            commitSha = $uploadResult.commitSha
            succeeded = [bool]$uploadResult.succeeded
            status = [string]$uploadResult.status
            hasAuthorshipNote = [bool]$uploadResult.hasAuthorshipNote
            stats = $uploadResult.stats
        }

        if ($uploadResult.error) {
            $resultEntry['error'] = [string]$uploadResult.error
        }

        $results += $resultEntry
    }
}

Write-UploadHost ""
if ($DryRun) {
    Write-UploadHost "[upload-ai-stats] [preview] $($results.Count) commit(s) collected, $withoutNoteCount without authorship note, $skipCount skipped"
    Write-UploadHost "[upload-ai-stats] Remove -DryRun to upload."
} else {
    Write-UploadHost "[upload-ai-stats] Done: $successCount uploaded, $failCount failed, $skipCount skipped, $withoutNoteCount without authorship note"
}

if ($Json) {
    @($results) | ConvertTo-Json -Depth 10
}
