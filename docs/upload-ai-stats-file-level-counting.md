# Upload AI Stats File-Level Counting

## Context

`scripts/powershell/upload-ai-stats.ps1` augments `git-ai stats <sha> --json` with per-file details derived from `git-ai diff <sha> --json --include-stats`.

The file-level aggregation path lives in `Get-CommitAiFileStats` and uses diff annotations to calculate `files[].aiAdditions` and `files[].toolModelBreakdown`.

## Range Shapes

`git-ai diff` can serialize an annotation range in either of these shapes:

- Single range: `[startLine, endLine]`
- Multiple ranges: `[[startLine, endLine], ...]`

The counting helper `Get-LineRangeCount` already supports both forms, including nested arrays.

## Bug

The previous implementation iterated over `annotationEntry.Value` after passing it through `Convert-ToObjectArray`.

For a single tuple like `[1, 13]`, PowerShell enumeration exposed the two scalar elements separately. That made the loop count the tuple as:

- `1` -> `1 line`
- `13` -> `1 line`

Result: a 13-line range was undercounted as 2 lines.

Commit-level stats from `git-ai stats` remained correct. The bug only affected file-level enrichment in `upload-ai-stats.ps1`.

## Fix

Call `Get-LineRangeCount` on the entire annotation value instead of iterating the range entries manually.

This keeps the tuple shape intact for `[startLine, endLine]` and still correctly sums nested arrays for `[[startLine, endLine], ...]`.

## Expected Result

- `files[].aiAdditions` matches the landed diff annotation ranges.
- `files[].toolModelBreakdown[].aiAdditions` stays aligned with the same file-level count.
- Commit-level headline stats remain unchanged.
