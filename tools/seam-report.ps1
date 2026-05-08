# seam-report.ps1 — 扫 git log 统计 SEAM 引用次数
#
# 约定：修 bug 时撞到 known-seams.md 里某个 seam，commit message 里写 [ref:SEAM-XXX]
# 这个脚本扫所有历史 commit，按 SEAM id 聚合"git log 投票数"，配合 known-seams.md
# 文档里记的"踩到次数（基线）"判断 seam 是否到了 refactor 优先级阈值。
#
# 用法：
#   .\tools\seam-report.ps1              # 全历史
#   .\tools\seam-report.ps1 -Since 30    # 最近 30 天
#   .\tools\seam-report.ps1 -Verbose     # 同时打印每条 commit 的 hash + 标题
#
# 阈值（与 docs/architecture/known-seams.md "维护约定"对齐）：
#   ≥ 2 git refs 且都在 30 天内 → 升级到 refactor 分支档 3 修

[CmdletBinding()]
param(
    [int]$Since = 0,
    [string]$RefPattern = '\[ref:SEAM-\d+\]'
)

$repoRoot = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not in a git repo"
    exit 1
}

$logArgs = @('log', '--no-merges', '--pretty=format:%H|%s|%b%n---END---')
if ($Since -gt 0) {
    $logArgs += "--since=$Since.days.ago"
}

$rawLog = & git @logArgs 2>$null
if (-not $rawLog) {
    Write-Host "(no commits in range)"
    exit 0
}

# 解析 commit 块
$commits = ($rawLog -join "`n") -split "---END---" |
    Where-Object { $_.Trim() -ne '' } |
    ForEach-Object {
        $first, $rest = $_.Trim() -split "`n", 2
        $parts = $first -split '\|', 3
        [PSCustomObject]@{
            Hash    = $parts[0]
            Subject = $parts[1]
            Body    = if ($parts.Length -gt 2) { $parts[2] } else { '' }
            Full    = $_
        }
    }

# 找所有含 [ref:SEAM-XXX] 的 commit
$matched = $commits | Where-Object { $_.Full -match $RefPattern }
$totalRefs = 0
$bySeam = @{}

foreach ($c in $matched) {
    $hits = [regex]::Matches($c.Full, $RefPattern)
    foreach ($h in $hits) {
        $id = $h.Value -replace '\[ref:|\]', ''
        if (-not $bySeam.ContainsKey($id)) {
            $bySeam[$id] = @()
        }
        $bySeam[$id] += $c
        $totalRefs++
    }
}

# 输出
$range = if ($Since -gt 0) { "last $Since days" } else { "full history" }
Write-Host ""
Write-Host "SEAM votes ($range, $($commits.Count) commits scanned):" -ForegroundColor Cyan
Write-Host ""

if ($bySeam.Count -eq 0) {
    Write-Host "  (no [ref:SEAM-xxx] mentions found)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "提示：修 bug 撞到 known-seams.md 记录的 seam 时，commit message 末尾加" -ForegroundColor Yellow
    Write-Host "  [ref:SEAM-XXX]"
    Write-Host "本脚本就能统计票数。" -ForegroundColor Yellow
    exit 0
}

# 按票数降序
$sorted = $bySeam.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending

foreach ($entry in $sorted) {
    $id = $entry.Key
    $hits = $entry.Value
    $threshold = if ($hits.Count -ge 2 -and $Since -le 30 -and $Since -gt 0) {
        " ⚠ 已达 refactor 阈值"
    } elseif ($hits.Count -ge 2) {
        " (⚠ 全历史 ≥2，需检查时间窗)"
    } else {
        ""
    }
    Write-Host ("  {0}: {1} ref{2}{3}" -f $id, $hits.Count, $(if ($hits.Count -eq 1) {''} else {'s'}), $threshold) -ForegroundColor Green
    if ($VerbosePreference -eq 'Continue') {
        foreach ($c in $hits) {
            Write-Host ("      {0,-9} {1}" -f $c.Hash.Substring(0, 8), $c.Subject) -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "Total refs: $totalRefs" -ForegroundColor Cyan
Write-Host ""
Write-Host "对照 known-seams.md 文档里的 '踩到次数' 基线判断是否到 refactor 阈值。" -ForegroundColor DarkGray
