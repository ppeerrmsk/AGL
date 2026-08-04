param(
    [switch]$IncludeHistorical
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$docsRoot = Join-Path $projectRoot "docs"
$specRoot = Join-Path $docsRoot "specs"
$errors = New-Object System.Collections.Generic.List[string]

function Relative-To-Project([string]$path) {
    return $path.Substring($projectRoot.Length + 1).Replace([char]92, [char]47)
}

function Add-Error([string]$message) {
    $errors.Add($message)
}

function Read-Meta([string]$text, [string]$field) {
    $match = [regex]::Match($text, "(?m)^$([regex]::Escape($field)):\s*([^\r\n#]+)")
    if (-not $match.Success) {
        return ""
    }
    return $match.Groups[1].Value.Trim()
}

Write-Output "[docs] checking current Markdown links..."
$markdownFiles = @(Get-ChildItem $docsRoot -Recurse -File -Filter "*.md")
$markdownFiles += @(Get-Item (Join-Path $projectRoot "AGENTS.md"), (Join-Path $projectRoot "CLAUDE.md"))

foreach ($doc in $markdownFiles) {
    $rel = Relative-To-Project $doc.FullName
    if (-not $IncludeHistorical) {
        if ($rel -match '^docs/(changelogs|design reference|handoffs)/' -or $rel -match '^docs/HANDOFF-') {
            continue
        }
    }

    $text = Get-Content $doc.FullName -Raw -Encoding UTF8
    foreach ($match in [regex]::Matches($text, '\[[^\]]*\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value.Trim().Trim('<', '>')
        if ($target -match '^(https?://|mailto:|#|data:)') {
            continue
        }

        $pathOnly = ($target -split '#', 2)[0].Trim()
        if ([string]::IsNullOrWhiteSpace($pathOnly) -or $pathOnly -match '^[\d.,-]+$') {
            continue
        }

        # A file.gd:123 editor pointer is checked as the underlying file path here.
        $pathOnly = $pathOnly -replace ':(\d+)(?:-\d+)?$', ''
        try {
            $resolved = [System.IO.Path]::GetFullPath((Join-Path $doc.DirectoryName $pathOnly))
        }
        catch {
            Add-Error "$rel -> invalid link target: $target"
            continue
        }
        if (-not (Test-Path -LiteralPath $resolved)) {
            Add-Error "$rel -> missing link target: $target"
        }
    }
}

Write-Output "[docs] checking spec registration and metadata..."
$specFiles = @(Get-ChildItem $specRoot -Recurse -File -Filter "*.md" |
    Where-Object { $_.Name -notin @('_INDEX.md', '_TEMPLATE.md') })
$indexPath = Join-Path $specRoot "_INDEX.md"
$indexText = Get-Content $indexPath -Raw -Encoding UTF8
$indexLines = Get-Content $indexPath -Encoding UTF8

$metaByRelativePath = @{}
$allowedKinds = @('boss', 'enemy', 'weapon', 'skill', 'aircraft', 'system', 'balance', 'map', 'event')
$allowedStatuses = @('draft', 'approved', 'in-progress', 'done', 'superseded')

foreach ($spec in $specFiles) {
    $relative = $spec.FullName.Substring($specRoot.Length + 1).Replace([char]92, [char]47)
    $text = Get-Content $spec.FullName -Raw -Encoding UTF8
    $meta = [pscustomobject]@{
        Id = Read-Meta $text 'id'
        Kind = Read-Meta $text 'kind'
        Status = Read-Meta $text 'status'
        Reconstruction = Read-Meta $text 'reconstruction_complete'
    }
    $metaByRelativePath[$relative] = $meta

    foreach ($required in @('Id', 'Kind', 'Status', 'Reconstruction')) {
        if ([string]::IsNullOrWhiteSpace([string]$meta.$required)) {
            Add-Error "docs/specs/$relative -> missing metadata: $required"
        }
    }
    if ($meta.Id -and $meta.Id -ne [System.IO.Path]::GetFileNameWithoutExtension($spec.Name)) {
        Add-Error "docs/specs/$relative -> id '$($meta.Id)' does not match the filename"
    }
    if ($meta.Kind -and $meta.Kind -notin $allowedKinds) {
        Add-Error "docs/specs/$relative -> invalid kind '$($meta.Kind)'"
    }
    if ($meta.Status -and $meta.Status -notin $allowedStatuses) {
        Add-Error "docs/specs/$relative -> invalid status '$($meta.Status)'"
    }
    if ($meta.Reconstruction -and $meta.Reconstruction -notin @('true', 'false')) {
        Add-Error "docs/specs/$relative -> reconstruction_complete must be true/false, got '$($meta.Reconstruction)'"
    }
}

$indexedPaths = New-Object System.Collections.Generic.HashSet[string]
foreach ($line in $indexLines) {
    $row = [regex]::Match($line, '^\| \[[^\]]+\]\(([^)]+\.md)\) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|')
    if (-not $row.Success) {
        continue
    }

    $relative = $row.Groups[1].Value
    [void]$indexedPaths.Add($relative)
    if (-not $metaByRelativePath.ContainsKey($relative)) {
        Add-Error "docs/specs/_INDEX.md -> indexed spec is missing: $relative"
        continue
    }

    $meta = $metaByRelativePath[$relative]
    $indexKind = $row.Groups[2].Value.Trim()
    $indexStatus = $row.Groups[3].Value.Trim()
    $indexReconstruction = $row.Groups[4].Value.Trim()
    $expectedReconstruction = if ($meta.Reconstruction -eq 'true') { [string][char]0x2705 } else { [string][char]0x2717 }

    if ($indexKind -ne $meta.Kind) {
        Add-Error "docs/specs/_INDEX.md -> $relative kind drift: index=$indexKind, meta=$($meta.Kind)"
    }
    if ($indexStatus -ne $meta.Status) {
        Add-Error "docs/specs/_INDEX.md -> $relative status drift: index=$indexStatus, meta=$($meta.Status)"
    }
    if ($indexReconstruction -ne $expectedReconstruction) {
        Add-Error "docs/specs/_INDEX.md -> $relative reconstruction drift: index=$indexReconstruction, meta=$($meta.Reconstruction)"
    }
}

foreach ($relative in $metaByRelativePath.Keys) {
    if (-not $indexedPaths.Contains($relative)) {
        Add-Error "docs/specs/$relative -> not registered in docs/specs/_INDEX.md"
    }
}

if ($errors.Count -gt 0) {
    Write-Output "[docs] FAILED: $($errors.Count) problem(s)"
    $errors | Sort-Object -Unique | ForEach-Object { Write-Output "  - $_" }
    exit 1
}

Write-Output "[docs] OK: links, spec registration, metadata and index state are consistent."
Write-Output "[docs] Note: code-line anchors are checked separately by tools/verify_doc_anchors.py."
exit 0
