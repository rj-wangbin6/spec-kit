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
    - GIT_AI_REPORT_REMOTE_URL:      Optional. Full request URL override for the remote API.
    - GIT_AI_REPORT_REMOTE_ENDPOINT: Optional. Base URL override for the remote API.
    - GIT_AI_REPORT_REMOTE_PATH:     Optional. Request path override when using ENDPOINT.
    - GIT_AI_REPORT_REMOTE_API_KEY:  Optional. Bearer token for authentication.
    - GIT_AI_REPORT_REMOTE_USER_ID:  Optional. Explicit X-USER-ID value for upload requests.
    - GIT_AI_REPORT_LOG_REQUEST:     Optional. When set to 1/true/yes/on, print request URL, headers, and body before upload.
    - GIT_AI_VSCODE_MCP_CONFIG_PATH: Optional. Override path to the VS Code MCP config file.
    - GIT_AI_IDEA_MCP_CONFIG_PATH:   Optional. Override path to the IDEA MCP JSON config file.

    When GIT_AI_REPORT_REMOTE_USER_ID is not set, the script will try to read
    X-USER-ID from local VS Code or IDEA MCP configuration.

    When remote URL variables are not provided, the script defaults to:
    https://service-gw.ruijie.com.cn/api/ai-cr-manage-service/api/public/upload/ai-stats
.EXAMPLE
    .\.specify\scripts\powershell\upload-ai-stats.ps1
.EXAMPLE
    .\.specify\scripts\powershell\upload-ai-stats.ps1 -DryRun
.EXAMPLE
    .\.specify\scripts\powershell\upload-ai-stats.ps1 -Since "2026-04-01" -Until "2026-04-14"
.EXAMPLE
    .\.specify\scripts\powershell\upload-ai-stats.ps1 -Commits "abc123,def456"
.EXAMPLE
    .\.specify\scripts\powershell\upload-ai-stats.ps1 -Commits "abc123" -LogHttpPayload
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
    [switch]$LogHttpPayload,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$script:JsonOutputMode = [bool]$Json
$script:LogHttpPayload = [bool]$LogHttpPayload

if (-not $script:LogHttpPayload -and -not [string]::IsNullOrWhiteSpace($env:GIT_AI_REPORT_LOG_REQUEST)) {
    $script:LogHttpPayload = @('1', 'true', 'yes', 'on') -contains $env:GIT_AI_REPORT_LOG_REQUEST.Trim().ToLowerInvariant()
}

. "$PSScriptRoot/common.ps1"

$script:DefaultRemoteEndpoint = 'https://service-gw.ruijie.com.cn'
$script:DefaultRemotePath = '/api/ai-cr-manage-service/api/public/upload/ai-stats'
$script:DefaultRemoteUrl = '{0}{1}' -f $script:DefaultRemoteEndpoint, $script:DefaultRemotePath

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# ─── Functions ────────────────────────────────────────────────

function Get-TargetCommits {
    $repoRoot = Get-RepoRoot
    $gitArgs = @("log", "--format=%H")

    if ($Commits) {
        $repoRoot = Get-RepoRoot
        $explicitCommits = @($Commits -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

        # Resolve short SHAs to full 40-char SHAs so they match authorship note lookup keys
        $resolvedCommits = @()
        foreach ($rawSha in $explicitCommits) {
            $resolveResult = Invoke-ProcessCapture -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', '--verify', "$rawSha^{commit}")
            $fullSha = $resolveResult.StdOut.Trim()
            if ($resolveResult.ExitCode -eq 0 -and $fullSha) {
                $resolvedCommits += $fullSha
            } else {
                Write-UploadWarning "[upload-ai-stats] Failed to resolve commit '$rawSha': $(Format-ProcessFailureDetail -ProcessResult $resolveResult)"
            }
        }

        Write-UploadTrace "[upload-ai-stats] Using explicit commit list ($($resolvedCommits.Count))."
        return $resolvedCommits
    }

    if ($Since) { $gitArgs += "--since=$Since" }
    if ($Until) { $gitArgs += "--until=$Until" }
    if ($Author) { $gitArgs += "--author=$Author" }

    if (-not $Since -and -not $Until) {
        $baseBranchResult = Invoke-ProcessCapture -FilePath 'git' -Arguments @('-C', $repoRoot, 'symbolic-ref', 'refs/remotes/origin/HEAD')
        $baseBranch = $baseBranchResult.StdOut.Trim()
        if ($baseBranchResult.ExitCode -ne 0 -or -not $baseBranch) {
            if ($baseBranchResult.ExitCode -ne 0) {
                Write-UploadTrace "[upload-ai-stats] Failed to resolve origin/HEAD, defaulting to origin/main: $(Format-ProcessFailureDetail -ProcessResult $baseBranchResult)"
            }
            $baseBranch = "origin/main"
        } else {
            $baseBranch = $baseBranch -replace 'refs/remotes/', ''
        }

        Write-UploadTrace "[upload-ai-stats] Using default commit range $baseBranch..HEAD"
        $gitArgs += "$baseBranch..HEAD"
    } else {
        $filters = @()
        if ($Since) { $filters += "since=$Since" }
        if ($Until) { $filters += "until=$Until" }
        if ($Author) { $filters += "author=$Author" }
        if ($filters.Count -gt 0) {
            Write-UploadTrace "[upload-ai-stats] Using filtered commit query: $($filters -join ', ')"
        }
    }

    $commitResult = Invoke-ProcessCapture -FilePath 'git' -Arguments (@('-C', $repoRoot) + $gitArgs)
    if ($commitResult.ExitCode -ne 0) {
        Write-UploadWarning "[upload-ai-stats] Failed to collect target commits: $(Format-ProcessFailureDetail -ProcessResult $commitResult)"
        return @()
    }

    $resolvedCommitShas = @($commitResult.StdOut -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    Write-UploadTrace "[upload-ai-stats] Collected $($resolvedCommitShas.Count) target commit(s) from $repoRoot"
    return $resolvedCommitShas
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
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        [void]$process.Start()
    } catch {
        return @{
            ExitCode = -1
            StdOut = ''
            StdErr = $_.Exception.Message
        }
    }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return @{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

function Get-CompactProcessText {
    param(
        [string]$Text,
        [int]$MaxLength = 240
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $normalized = ($Text -replace '\s+', ' ').Trim()
    if ($normalized.Length -le $MaxLength) {
        return $normalized
    }

    return '{0}...' -f $normalized.Substring(0, $MaxLength)
}

function Format-ProcessFailureDetail {
    param([hashtable]$ProcessResult)

    if (-not $ProcessResult) {
        return 'no process result available'
    }

    $details = @("exitCode=$($ProcessResult.ExitCode)")
    $stderr = Get-CompactProcessText -Text $ProcessResult.StdErr
    if ($stderr) {
        $details += "stderr=$stderr"
    }

    $stdout = Get-CompactProcessText -Text $ProcessResult.StdOut
    if ($stdout) {
        $details += "stdout=$stdout"
    }

    return ($details -join '; ')
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
    $noteCommandResult = Invoke-ProcessCapture -FilePath 'git' -Arguments @('-C', $RepoRoot, 'notes', '--ref=ai', 'list')
    $noteLines = $noteCommandResult.StdOut
    if ($noteCommandResult.ExitCode -eq 0 -and $noteLines) {
        foreach ($line in ($noteLines -split "`n" | Where-Object { $_.Trim() })) {
            $parts = $line.Trim() -split '\s+', 2
            if ($parts.Count -eq 2) {
                $lookup[$parts[1]] = $true
            }
        }
    } elseif ($noteCommandResult.ExitCode -ne 0) {
        Write-UploadWarning "[upload-ai-stats] Failed to read git-ai authorship notes: $(Format-ProcessFailureDetail -ProcessResult $noteCommandResult)"
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
    $shortSha = $CommitSha.Substring(0, [Math]::Min(7, $CommitSha.Length))
    $noteStatus = if ($hasAuthorshipNote) { 'yes' } else { 'no' }

    Write-UploadTrace "[upload-ai-stats] $shortSha : reading commit statistics (authorshipNote=$noteStatus)"

    $statsCommandResult = Invoke-ProcessCapture -FilePath 'git-ai' -Arguments @('stats', $CommitSha, '--json')
    $statsJson = $statsCommandResult.StdOut
    if ($statsCommandResult.ExitCode -ne 0 -or -not $statsJson) {
        Write-UploadWarning "[upload-ai-stats] Failed to read stats for ${shortSha}: $(Format-ProcessFailureDetail -ProcessResult $statsCommandResult)"
        return $null
    }

    try {
        $statsObject = $statsJson | ConvertFrom-Json
    } catch {
        $statsPreview = Get-CompactProcessText -Text $statsJson
        if ($statsPreview) {
            Write-UploadWarning "[upload-ai-stats] Failed to parse stats JSON for $shortSha. stdout=$statsPreview"
        } else {
            Write-UploadWarning "[upload-ai-stats] Failed to parse stats JSON for $shortSha."
        }
        return $null
    }

    $fileStats = @(Get-CommitAiFileStats -CommitSha $CommitSha)
    if ($statsObject.PSObject.Properties.Name -contains 'files') {
        $statsObject.files = $fileStats
    } else {
        $statsObject | Add-Member -NotePropertyName 'files' -NotePropertyValue $fileStats
    }

    Write-UploadTrace "[upload-ai-stats] $shortSha : collected $($fileStats.Count) file detail record(s)"

    return @{
        HasAuthorshipNote = $hasAuthorshipNote
        Stats = $statsObject
    }
}

function Get-McpUserIdFromServerConfig {
    param([object]$ServerConfig)

    if (-not $ServerConfig) {
        return $null
    }

    $headers = Get-ResponsePropertyValue -Object $ServerConfig -Names @('headers')
    $headerUserId = Get-ResponsePropertyValue -Object $headers -Names @('X-USER-ID', 'x-user-id')
    if ($headerUserId) {
        return [string]$headerUserId
    }

    $requestInit = Get-ResponsePropertyValue -Object $ServerConfig -Names @('requestInit', 'request_init')
    if (-not $requestInit) {
        return $null
    }

    $requestHeaders = Get-ResponsePropertyValue -Object $requestInit -Names @('headers')
    $requestHeaderUserId = Get-ResponsePropertyValue -Object $requestHeaders -Names @('X-USER-ID', 'x-user-id')
    if ($requestHeaderUserId) {
        return [string]$requestHeaderUserId
    }

    return $null
}

function Find-McpUserIdInConfigObject {
    param([object]$ConfigObject)

    if (-not $ConfigObject) {
        return $null
    }

    $serverEntries = @()
    $serversObject = Get-ResponsePropertyValue -Object $ConfigObject -Names @('servers')
    if ($serversObject) {
        $serverEntries += @(Get-ObjectEntries -Object $serversObject)
    }

    $serverEntries += @(Get-ObjectEntries -Object $ConfigObject)

    $preferredServerConfigs = @()
    $fallbackServerConfigs = @()

    foreach ($entry in $serverEntries) {
        $entryValue = $entry.Value
        if ($null -eq $entryValue -or $entryValue -is [string] -or $entryValue -is [ValueType]) {
            continue
        }

        $url = [string](Get-ResponsePropertyValue -Object $entryValue -Names @('url'))
        $type = [string](Get-ResponsePropertyValue -Object $entryValue -Names @('type'))
        $hasMcpUrl = -not [string]::IsNullOrWhiteSpace($url) -and $url -match '/mcp(?:$|[/?#])'
        $isHttpType = [string]::IsNullOrWhiteSpace($type) -or $type.ToLowerInvariant() -eq 'http'

        if (-not $hasMcpUrl -or -not $isHttpType) {
            continue
        }

        $entryName = [string]$entry.Name
        if ($entryName -eq 'codereview-mcp-server' -or $entryName -like '*codereview*') {
            $preferredServerConfigs += $entryValue
        } else {
            $fallbackServerConfigs += $entryValue
        }
    }

    foreach ($serverConfig in ($preferredServerConfigs + $fallbackServerConfigs)) {
        $resolvedUserId = Get-McpUserIdFromServerConfig -ServerConfig $serverConfig
        if ($resolvedUserId) {
            return $resolvedUserId
        }
    }

    foreach ($entry in (Get-ObjectEntries -Object $ConfigObject)) {
        $nestedValue = $entry.Value
        if ($null -eq $nestedValue -or $nestedValue -is [string] -or $nestedValue -is [ValueType]) {
            continue
        }

        if ($nestedValue -is [System.Array]) {
            foreach ($nestedItem in $nestedValue) {
                $resolvedUserId = Find-McpUserIdInConfigObject -ConfigObject $nestedItem
                if ($resolvedUserId) {
                    return $resolvedUserId
                }
            }

            continue
        }

        $resolvedUserId = Find-McpUserIdInConfigObject -ConfigObject $nestedValue
        if ($resolvedUserId) {
            return $resolvedUserId
        }
    }

    return $null
}

function Remove-JsonCommentText {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $isEscaped = $false
    $inLineComment = $false
    $inBlockComment = $false

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $char = $Text[$index]
        $nextChar = if (($index + 1) -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($char -eq "`r" -or $char -eq "`n") {
                $inLineComment = $false
                [void]$builder.Append($char)
            }

            continue
        }

        if ($inBlockComment) {
            if ($char -eq '*' -and $nextChar -eq '/') {
                $inBlockComment = $false
                $index++
            }

            continue
        }

        if ($inString) {
            [void]$builder.Append($char)

            if ($isEscaped) {
                $isEscaped = $false
            } elseif ($char -eq '\\') {
                $isEscaped = $true
            } elseif ($char -eq '"') {
                $inString = $false
            }

            continue
        }

        if ($char -eq '"') {
            $inString = $true
            [void]$builder.Append($char)
            continue
        }

        if ($char -eq '/' -and $nextChar -eq '/') {
            $inLineComment = $true
            $index++
            continue
        }

        if ($char -eq '/' -and $nextChar -eq '*') {
            $inBlockComment = $true
            $index++
            continue
        }

        [void]$builder.Append($char)
    }

    return $builder.ToString()
}

function Remove-JsonTrailingCommas {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $isEscaped = $false

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $char = $Text[$index]

        if ($inString) {
            [void]$builder.Append($char)

            if ($isEscaped) {
                $isEscaped = $false
            } elseif ($char -eq '\\') {
                $isEscaped = $true
            } elseif ($char -eq '"') {
                $inString = $false
            }

            continue
        }

        if ($char -eq '"') {
            $inString = $true
            [void]$builder.Append($char)
            continue
        }

        if ($char -eq ',') {
            $nextIndex = $index + 1
            while ($nextIndex -lt $Text.Length -and [char]::IsWhiteSpace($Text[$nextIndex])) {
                $nextIndex++
            }

            if ($nextIndex -lt $Text.Length -and ($Text[$nextIndex] -eq '}' -or $Text[$nextIndex] -eq ']')) {
                continue
            }
        }

        [void]$builder.Append($char)
    }

    return $builder.ToString()
}

function ConvertFrom-JsonWithComments {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    try {
        return ($Text | ConvertFrom-Json)
    } catch {
        $withoutComments = Remove-JsonCommentText -Text $Text
        $normalizedJson = Remove-JsonTrailingCommas -Text $withoutComments
        return ($normalizedJson | ConvertFrom-Json)
    }
}

function Get-McpUserIdFromConfigFile {
    param(
        [string]$ConfigPath,
        [string]$ClientName
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath) -or -not (Test-Path -LiteralPath $ConfigPath)) {
        return $null
    }

    try {
        $configText = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
    } catch {
        Write-UploadTrace "[upload-ai-stats] Failed to read $ClientName MCP config at ${ConfigPath}: $($_.Exception.Message)"
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($configText) -or $configText -notmatch 'X-USER-ID|x-user-id') {
        return $null
    }

    try {
        $configObject = ConvertFrom-JsonWithComments -Text $configText
    } catch {
        Write-UploadTrace "[upload-ai-stats] Failed to parse $ClientName MCP config at ${ConfigPath}: $($_.Exception.Message)"
        return $null
    }

    $resolvedUserId = Find-McpUserIdInConfigObject -ConfigObject $configObject
    if (-not $resolvedUserId) {
        return $null
    }

    return @{
        UserId = [string]$resolvedUserId
        Source = "$ClientName MCP config"
        Path = $ConfigPath
    }
}

function Get-VSCodeMcpConfigPaths {
    $candidatePaths = @()

    if ($env:GIT_AI_VSCODE_MCP_CONFIG_PATH) {
        $candidatePaths += $env:GIT_AI_VSCODE_MCP_CONFIG_PATH
    }

    if ($env:APPDATA) {
        $candidatePaths += (Join-Path $env:APPDATA 'Code\User\mcp.json')
        $candidatePaths += (Join-Path $env:APPDATA 'Code\User\settings.json')
        $candidatePaths += (Join-Path $env:APPDATA 'Code - Insiders\User\mcp.json')
        $candidatePaths += (Join-Path $env:APPDATA 'Code - Insiders\User\settings.json')
    }

    return @($candidatePaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

function Get-IdeaMcpConfigPaths {
    $candidatePaths = @()

    if ($env:GIT_AI_IDEA_MCP_CONFIG_PATH) {
        $candidatePaths += $env:GIT_AI_IDEA_MCP_CONFIG_PATH
    }

    if ($env:LOCALAPPDATA) {
        $candidatePaths += (Join-Path $env:LOCALAPPDATA 'github-copilot\intellij\mcp.json')
    }

    if ($env:APPDATA) {
        $candidatePaths += (Join-Path $env:APPDATA 'github-copilot\intellij\mcp.json')
    }

    $jetBrainsRoots = @()
    if ($env:APPDATA) {
        $jetBrainsRoots += (Join-Path $env:APPDATA 'JetBrains')
    }

    if ($env:LOCALAPPDATA) {
        $jetBrainsRoots += (Join-Path $env:LOCALAPPDATA 'JetBrains')
    }

    foreach ($jetBrainsRoot in ($jetBrainsRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
        foreach ($candidateFile in (Get-ChildItem -Path $jetBrainsRoot -Recurse -File -Filter *.json -ErrorAction SilentlyContinue | Where-Object {
            $_.Length -gt 0 -and $_.Length -lt 1048576
        })) {
            if ($candidatePaths -contains $candidateFile.FullName) {
                continue
            }

            try {
                $candidateText = Get-Content -LiteralPath $candidateFile.FullName -Raw -ErrorAction Stop
            } catch {
                continue
            }

            if ($candidateText -match 'X-USER-ID|x-user-id|requestInit|codereview-mcp-server|/mcp') {
                $candidatePaths += $candidateFile.FullName
            }
        }
    }

    return @($candidatePaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

function Resolve-ConfiguredRemoteUserId {
    $explicitUserId = $env:GIT_AI_REPORT_REMOTE_USER_ID
    if ($explicitUserId) {
        return @{
            UserId = [string]$explicitUserId
            Source = 'GIT_AI_REPORT_REMOTE_USER_ID'
            Path = $null
        }
    }

    foreach ($configPath in (Get-VSCodeMcpConfigPaths)) {
        $resolvedUserId = Get-McpUserIdFromConfigFile -ConfigPath $configPath -ClientName 'VS Code'
        if ($resolvedUserId) {
            return $resolvedUserId
        }
    }

    foreach ($configPath in (Get-IdeaMcpConfigPaths)) {
        $resolvedUserId = Get-McpUserIdFromConfigFile -ConfigPath $configPath -ClientName 'IDEA'
        if ($resolvedUserId) {
            return $resolvedUserId
        }
    }

    return $null
}

function Get-UploadRemoteConfig {
    $resolvedUserIdInfo = Resolve-ConfiguredRemoteUserId
    if ($resolvedUserIdInfo) {
        $resolvedUserIdSource = if ($resolvedUserIdInfo.Path) {
            '{0}: {1}' -f $resolvedUserIdInfo.Source, $resolvedUserIdInfo.Path
        } else {
            [string]$resolvedUserIdInfo.Source
        }

        Write-UploadTrace "[upload-ai-stats] Using X-USER-ID '$($resolvedUserIdInfo.UserId)' from $resolvedUserIdSource"
    } else {
        Write-UploadTrace '[upload-ai-stats] No X-USER-ID configured via GIT_AI_REPORT_REMOTE_USER_ID or local IDE MCP config.'
    }

    $url = $env:GIT_AI_REPORT_REMOTE_URL
    if ($url) {
        Write-UploadTrace "[upload-ai-stats] Using remote URL from GIT_AI_REPORT_REMOTE_URL: $url"
        return @{
            Url = $url
            ApiKey = $env:GIT_AI_REPORT_REMOTE_API_KEY
            UserId = if ($resolvedUserIdInfo) { $resolvedUserIdInfo.UserId } else { $null }
        }
    }

    $endpoint = $env:GIT_AI_REPORT_REMOTE_ENDPOINT
    if (-not $endpoint) {
        $endpoint = $script:DefaultRemoteEndpoint
    }

    $path = $env:GIT_AI_REPORT_REMOTE_PATH
    if (-not $path) {
        $path = $script:DefaultRemotePath
    }

    $resolvedUrl = "{0}/{1}" -f $endpoint.TrimEnd('/'), $path.TrimStart('/')
    if ($env:GIT_AI_REPORT_REMOTE_ENDPOINT -or $env:GIT_AI_REPORT_REMOTE_PATH) {
        Write-UploadTrace "[upload-ai-stats] Using remote URL from endpoint/path variables: $resolvedUrl"
    } else {
        Write-UploadTrace "[upload-ai-stats] Using built-in default remote URL: $resolvedUrl"
    }

    return @{
        Url = $resolvedUrl
        ApiKey = $env:GIT_AI_REPORT_REMOTE_API_KEY
        UserId = if ($resolvedUserIdInfo) { $resolvedUserIdInfo.UserId } else { $null }
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
        $property = $Object.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if ($property) {
            return $property.Value
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

function Write-UploadTrace {
    param([string]$Message)

    if ($script:JsonOutputMode) {
        return
    }

    Write-Host $Message -ForegroundColor DarkGray
}

function Write-UploadDiagnostic {
    param([string]$Message)

    if ($script:JsonOutputMode) {
        [Console]::Error.WriteLine($Message)
        return
    }

    Write-Host $Message -ForegroundColor DarkGray
}

function Format-UploadHeadersForLog {
    param([hashtable]$Headers)

    $formattedHeaders = [ordered]@{}
    if (-not $Headers) {
        return $formattedHeaders
    }

    foreach ($headerName in ($Headers.Keys | Sort-Object)) {
        $headerValue = $Headers[$headerName]
        if ($headerName -ieq 'Authorization' -and -not [string]::IsNullOrWhiteSpace([string]$headerValue)) {
            $headerText = [string]$headerValue
            if ($headerText.Length -le 12) {
                $formattedHeaders[$headerName] = '***'
            } else {
                $formattedHeaders[$headerName] = '{0}***{1}' -f $headerText.Substring(0, 10), $headerText.Substring($headerText.Length - 4)
            }
            continue
        }

        $formattedHeaders[$headerName] = $headerValue
    }

    return $formattedHeaders
}

function Write-UploadRequestLog {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Body
    )

    if (-not $script:LogHttpPayload) {
        return
    }

    $headersForLog = Format-UploadHeadersForLog -Headers $Headers
    $headersJson = ConvertTo-Json -InputObject $headersForLog -Depth 5

    Write-UploadDiagnostic '[upload-ai-stats] HTTP request URL:'
    Write-UploadDiagnostic $Uri
    Write-UploadDiagnostic '[upload-ai-stats] HTTP request headers:'
    Write-UploadDiagnostic $headersJson
    Write-UploadDiagnostic '[upload-ai-stats] HTTP request body:'
    Write-UploadDiagnostic $Body
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

    $repoRoot = Get-RepoRoot
    $shortSha = $CommitSha.Substring(0, [Math]::Min(7, $CommitSha.Length))

    # Step 1: Per-file added/deleted line counts from git diff-tree --numstat
    $numstatResult = Invoke-ProcessCapture -FilePath 'git' -Arguments @('-C', $repoRoot, 'diff-tree', '--no-commit-id', '--numstat', '-r', $CommitSha)
    if ($numstatResult.ExitCode -ne 0 -or -not $numstatResult.StdOut) {
        Write-UploadTrace "[upload-ai-stats] $shortSha : git diff-tree --numstat unavailable"
        return @()
    }

    $fileLineCounts = [ordered]@{}
    foreach ($numLine in ($numstatResult.StdOut -split "`n")) {
        $numLine = $numLine.Trim()
        if (-not $numLine) { continue }
        $parts = $numLine -split "`t", 3
        if ($parts.Count -lt 3) { continue }
        $added   = if ($parts[0] -eq '-') { 0 } else { [int]$parts[0] }
        $deleted = if ($parts[1] -eq '-') { 0 } else { [int]$parts[1] }
        $fileLineCounts[$parts[2]] = @{ added = $added; deleted = $deleted }
    }

    if ($fileLineCounts.Count -eq 0) {
        return @()
    }

    # Step 2: Read the commit's own authorship note (commit-local, no provenance tracing)
    $noteResult = Invoke-ProcessCapture -FilePath 'git' -Arguments @('-C', $repoRoot, 'notes', '--ref=ai', 'show', $CommitSha)

    $fileAttestations = @{}
    $promptsMetadata  = @{}

    if ($noteResult.ExitCode -eq 0 -and $noteResult.StdOut) {
        $noteText = $noteResult.StdOut
        # Note format: attestation lines before "---", JSON metadata after "---"
        $sepMatch = [regex]::Match($noteText, '(?m)^---\s*$')
        $attestationText = ''
        $jsonText = ''
        if ($sepMatch.Success) {
            $attestationText = $noteText.Substring(0, $sepMatch.Index)
            $jsonText = $noteText.Substring($sepMatch.Index + $sepMatch.Length)
        }

        # Parse JSON metadata for prompt tool/model info
        if ($jsonText) {
            try {
                $metadata = $jsonText.Trim() | ConvertFrom-Json
                $prompts = Get-ResponsePropertyValue -Object $metadata -Names @('prompts')
                if ($prompts) {
                    foreach ($pe in (Get-ObjectEntries -Object $prompts)) {
                        $promptsMetadata[[string]$pe.Name] = $pe.Value
                    }
                }
            } catch {
                Write-UploadTrace "[upload-ai-stats] $shortSha : failed to parse authorship note JSON metadata"
            }
        }

        # Parse attestation section: non-indented line = file path, indented = "<id> <range>"
        $currentFile = $null
        foreach ($attLine in ($attestationText -split "`n")) {
            if ([string]::IsNullOrWhiteSpace($attLine)) { continue }

            if ($attLine -match '^\S') {
                $currentFile = $attLine.Trim()
                if (-not $fileAttestations.ContainsKey($currentFile)) {
                    $fileAttestations[$currentFile] = @{ ai = 0; human = 0; tool_model_breakdown = @{} }
                }
                continue
            }

            if (-not $currentFile) { continue }
            if ($attLine -notmatch '^\s+(\S+)\s+(.+)$') { continue }

            $entryId  = $Matches[1]
            $rangeStr = $Matches[2]
            $lineCount = 0
            foreach ($rp in ($rangeStr -split ',')) {
                $rp = $rp.Trim()
                if ($rp -match '^(\d+)-(\d+)$') {
                    $lineCount += [int]$Matches[2] - [int]$Matches[1] + 1
                } elseif ($rp -match '^\d+$') {
                    $lineCount += 1
                }
            }
            if ($lineCount -le 0) { continue }

            if (-not $fileAttestations.ContainsKey($currentFile)) {
                $fileAttestations[$currentFile] = @{ ai = 0; human = 0; tool_model_breakdown = @{} }
            }

            if ($entryId -like 'h_*') {
                $fileAttestations[$currentFile]['human'] += $lineCount
            } else {
                $fileAttestations[$currentFile]['ai'] += $lineCount

                # Build tool_model_breakdown from prompt metadata
                $tool = 'unknown'; $model = $null
                if ($promptsMetadata.ContainsKey($entryId)) {
                    $agentId = Get-ResponsePropertyValue -Object $promptsMetadata[$entryId] -Names @('agent_id', 'agentId')
                    $toolVal  = Get-ResponsePropertyValue -Object $agentId -Names @('tool')
                    $modelVal = Get-ResponsePropertyValue -Object $agentId -Names @('model')
                    if ($toolVal) { $tool = [string]$toolVal }
                    if ($modelVal) { $model = [string]$modelVal }
                }
                $bkKey = if ([string]::IsNullOrWhiteSpace($model)) { $tool } else { '{0}::{1}' -f $tool, $model }
                if (-not $fileAttestations[$currentFile]['tool_model_breakdown'].ContainsKey($bkKey)) {
                    $fileAttestations[$currentFile]['tool_model_breakdown'][$bkKey] = @{ ai_additions = 0 }
                }
                $fileAttestations[$currentFile]['tool_model_breakdown'][$bkKey]['ai_additions'] += $lineCount
            }
        }
    }

    # Step 3: Build per-file stats from numstat + attestation
    $results = @()
    foreach ($filePath in $fileLineCounts.Keys) {
        $lc  = $fileLineCounts[$filePath]
        $att = if ($fileAttestations.ContainsKey($filePath)) { $fileAttestations[$filePath] } else { $null }

        $aiAdd    = if ($att) { [Math]::Min([int]$att['ai'], $lc.added) } else { 0 }
        $humanAdd = if ($att) { [Math]::Min([int]$att['human'], [Math]::Max(0, $lc.added - $aiAdd)) } else { $lc.added }
        $unknown  = [Math]::Max(0, $lc.added - $aiAdd - $humanAdd)
        $breakdown = if ($att) { $att['tool_model_breakdown'] } else { @{} }

        $results += [pscustomobject]@{
            file_path              = $filePath
            git_diff_added_lines   = $lc.added
            git_diff_deleted_lines = $lc.deleted
            ai_additions           = $aiAdd
            human_additions        = $humanAdd
            unknown_additions      = $unknown
            tool_model_breakdown   = $breakdown
        }
    }

    return @($results)
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
        return ,@($Value | ForEach-Object { Convert-ObjectKeysToCamelCase -Value $_ })
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

        if ($propertyName -in @('files', 'Files')) {
            $convertedObject['files'] = @((Convert-ToObjectArray -Value $entry.Value) | ForEach-Object {
                Convert-ObjectKeysToCamelCase -Value $_
            })
            continue
        }

        $convertedName = Convert-SnakeCaseNameToCamelCase -Name $propertyName
        $convertedObject[$convertedName] = Convert-ObjectKeysToCamelCase -Value $entry.Value
    }

    return [pscustomobject]$convertedObject
}

function Convert-CommitTimestampToUploadFormat {
    param([AllowEmptyString()][string]$Timestamp)

    $trimmedTimestamp = if ($null -eq $Timestamp) { '' } else { $Timestamp.Trim() }
    if (-not $trimmedTimestamp) {
        return ''
    }

    $parsedTimestamp = [System.DateTimeOffset]::MinValue
    $parseSucceeded = [System.DateTimeOffset]::TryParse(
        $trimmedTimestamp,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsedTimestamp
    )

    if ($parseSucceeded) {
        return $parsedTimestamp.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    Write-UploadTrace "[upload-ai-stats] Using original commit timestamp because parsing failed: $trimmedTimestamp"
    return $trimmedTimestamp
}

function New-CommitUploadItem {
    param(
        [string]$CommitSha,
        [hashtable]$StatsResult
    )

    $repoRoot = Get-RepoRoot
    # Use record separator (0x1e) as delimiter to avoid conflicts with | in commit messages
    $commitInfoResult = Invoke-ProcessCapture -FilePath 'git' -Arguments @('-C', $repoRoot, 'log', '-1', '--format=%ae%x1e%s%x1e%aI', $CommitSha)
    $commitInfo = $commitInfoResult.StdOut.Trim()
    if ($commitInfoResult.ExitCode -ne 0 -or -not $commitInfo) {
        $shortSha = $CommitSha.Substring(0, [Math]::Min(7, $CommitSha.Length))
        Write-UploadWarning "[upload-ai-stats] Failed to read commit metadata for ${shortSha}: $(Format-ProcessFailureDetail -ProcessResult $commitInfoResult)"
        return $null
    }

    $recordSep = [char]0x1e
    $parts = $commitInfo -split [regex]::Escape($recordSep), 3
    $formattedTimestamp = if ($parts.Count -ge 3) { Convert-CommitTimestampToUploadFormat -Timestamp $parts[2] } else { "" }
    return @{
        commitSha = $CommitSha
        commitMessage = if ($parts.Count -ge 2) { $parts[1] } else { "" }
        author = if ($parts.Count -ge 1) { $parts[0] } else { "" }
        timestamp = $formattedTimestamp
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

        $responseError = if ($responseItem) {
            Get-ResponsePropertyValue -Object $responseItem -Names @('error', 'errorMessage', 'message', 'reason')
        } else {
            $null
        }

        $normalized += @{
            commitSha = [string]$commitItem.commitSha
            succeeded = $succeeded
            status = [string]$status
            error = if ($responseError) { [string]$responseError } else { $null }
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
    }
    $payload = ConvertTo-Json -InputObject $payload -Depth 12

    $headers = @{ "Content-Type" = "application/json" }
    if ($RemoteConfig.ApiKey) { $headers["Authorization"] = "Bearer $($RemoteConfig.ApiKey)" }
    if ($RemoteConfig.UserId) { $headers["X-USER-ID"] = [string]$RemoteConfig.UserId }

    try {
        $userIdTrace = if ($RemoteConfig.UserId) {
            ' with X-USER-ID={0}' -f $RemoteConfig.UserId
        } else {
            ''
        }

        Write-UploadTrace "[upload-ai-stats] Uploading $($CommitItems.Count) commit(s) to $($RemoteConfig.Url)$userIdTrace"
        Write-UploadRequestLog -Uri $RemoteConfig.Url -Headers $headers -Body $payload
        $response = Invoke-RestMethod -Uri $RemoteConfig.Url `
            -Method POST -Body $payload -Headers $headers -TimeoutSec 10

        return @{
            Succeeded = $true
            Results = @(Convert-BatchUploadResponse -Response $response -CommitItems $CommitItems)
        }
    } catch {
        Write-UploadWarning "[upload-ai-stats] Batch upload failed for $($CommitItems.Count) commit(s) to $($RemoteConfig.Url): $_"

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

Write-UploadTrace "[upload-ai-stats] git-ai command: $($gitAiCmd.Path)"
Write-UploadTrace "[upload-ai-stats] Mode: dryRun=$([bool]$DryRun); json=$([bool]$Json); source=$Source"

$targetCommitShas = @(Get-TargetCommits)
if (-not $targetCommitShas -or $targetCommitShas.Count -eq 0) {
    if ($Json) {
        ConvertTo-Json -InputObject @() -Depth 10
    } else {
        Write-UploadHost "[upload-ai-stats] No matching commits found (current branch may equal base branch)."
    }
    exit 0
}

Write-UploadHost "[upload-ai-stats] Found $($targetCommitShas.Count) commit(s), collecting AI statistics..."
Write-UploadHost ""

$repoRoot = Get-RepoRoot
$repoUrl = git -C $repoRoot remote get-url origin 2>$null
$projectName = ($repoUrl -split '/')[-1] -replace '\.git$', ''
$remoteConfig = $null

Write-UploadTrace "[upload-ai-stats] Repo root: $repoRoot"
Write-UploadTrace "[upload-ai-stats] Project name: $projectName"

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

foreach ($sha in $targetCommitShas) {
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
            Write-UploadHost "  $shortSha : [preview] note=yes, added=$($stats.gitDiffAddedLines), aiAdditions=$($stats.aiAdditions), humanAdditions=$($stats.humanAdditions), unknownAdditions=$($stats.unknownAdditions)" -ForegroundColor Cyan
        } else {
            Write-UploadHost "  $shortSha : [preview] note=no, added=$($stats.gitDiffAddedLines), humanAdditions=$($stats.humanAdditions), unknownAdditions=$($stats.unknownAdditions)" -ForegroundColor Yellow
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
                Write-UploadHost "  $shortSha : uploaded (note=yes, added=$($uploadResult.stats.gitDiffAddedLines), aiAdditions=$($uploadResult.stats.aiAdditions), humanAdditions=$($uploadResult.stats.humanAdditions), unknownAdditions=$($uploadResult.stats.unknownAdditions))" -ForegroundColor Green
            } else {
                Write-UploadHost "  $shortSha : uploaded (note=no, added=$($uploadResult.stats.gitDiffAddedLines), humanAdditions=$($uploadResult.stats.humanAdditions), unknownAdditions=$($uploadResult.stats.unknownAdditions))" -ForegroundColor Green
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
    ConvertTo-Json -InputObject @($results) -Depth 10
}
