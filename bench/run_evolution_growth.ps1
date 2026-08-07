param(
    [ValidateRange(1, 86400)]
    [int]$DurationSeconds = 840,
    [ValidateRange(1, 1000)]
    [int]$SamplesPerGroup = 20,
    [ValidateRange(1, 100)]
    [int]$MaxAttemptsPerSample = 50,
    [ValidateRange(1, 2147480000)]
    [int]$BaseSeed = 41001,
    [switch]$Smoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runCmd = Join-Path $PSScriptRoot 'run.cmd'
$pythonExe = 'C:\Users\noelu\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$aggregateScript = Join-Path $projectDir 'scripts\tools\aggregate_evolution_growth.py'
$outputRoot = Join-Path $projectDir 'bench\results\evolution_growth'
if ($Smoke) {
    $outputRoot = Join-Path $outputRoot 'smoke'
    if ($DurationSeconds -eq 840) {
        $DurationSeconds = 20
    }
    $SamplesPerGroup = 1
}
$rawDir = Join-Path $outputRoot 'raw'
$aggregateDir = Join-Path $outputRoot 'aggregate'
$progressPath = Join-Path $outputRoot 'progress.json'
New-Item -ItemType Directory -Path $rawDir -Force | Out-Null
New-Item -ItemType Directory -Path $aggregateDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $runCmd -PathType Leaf)) {
    throw "missing bench launcher: $runCmd"
}
if (-not (Test-Path -LiteralPath $pythonExe -PathType Leaf)) {
    throw "missing Codex Python runtime: $pythonExe"
}

$starters = @('f15', 'f14', 'a6e', 'mirage3')
$squadSizes = @(1, 3, 5, 9)
if ($Smoke) {
    $starters = @('f15')
    $squadSizes = @(1)
}

function Read-RunResult([string]$path) {
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-Progress {
    $all = @(Get-ChildItem -LiteralPath $rawDir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    $valid = 0
    $invalid = 0
    foreach ($file in $all) {
        $row = Read-RunResult $file.FullName
        if ([bool]$row.valid) { $valid += 1 } else { $invalid += 1 }
    }
    $progress = [ordered]@{
        updated_utc = [DateTime]::UtcNow.ToString('o')
        smoke = [bool]$Smoke
        duration_seconds = $DurationSeconds
        samples_per_group = $SamplesPerGroup
        expected_valid = $starters.Count * $squadSizes.Count * $SamplesPerGroup
        valid = $valid
        invalid = $invalid
        running = $true
    }
    $progress | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $progressPath -Encoding UTF8
}

function Invoke-Aggregate {
    & $pythonExe $aggregateScript --raw-dir $rawDir --out $aggregateDir --expected-per-group $SamplesPerGroup
    if ($LASTEXITCODE -ne 0) {
        throw "aggregate failed with exit code $LASTEXITCODE"
    }
}

$previousFixedFps = $env:AGL_BENCH_FIXED_FPS
try {
    $env:AGL_BENCH_FIXED_FPS = '60'
    Write-Progress
    foreach ($starter in $starters) {
        foreach ($squadSize in $squadSizes) {
            for ($sample = 1; $sample -le $SamplesPerGroup; $sample++) {
                $accepted = $false
                for ($attempt = 0; $attempt -lt $MaxAttemptsPerSample; $attempt++) {
                    $prefix = if ($Smoke) { 'smoke' } else { 'full' }
                    $runId = '{0}_{1}_s{2}_sample{3:D2}_a{4:D2}' -f `
                        $prefix, $starter, $squadSize, $sample, $attempt
                    $rawPath = Join-Path $rawDir "$runId.json"
                    if (Test-Path -LiteralPath $rawPath -PathType Leaf) {
                        $existing = Read-RunResult $rawPath
                        if ([bool]$existing.valid) {
                            Write-Host "[growth] resume valid $runId"
                            $accepted = $true
                            break
                        }
                        Write-Host "[growth] resume invalid $runId; trying replacement seed"
                        continue
                    }

                    $seed = $BaseSeed + ($sample - 1) + ($attempt * 1000)
                    $env:AGL_GROWTH_RUN_ID = $runId
                    $env:AGL_GROWTH_STARTER = $starter
                    $env:AGL_GROWTH_SQUAD_SIZE = [string]$squadSize
                    $env:AGL_GROWTH_SEED = [string]$seed
                    Write-Host "[growth] start $runId duration=${DurationSeconds}s seed=$seed"
                    & $runCmd evolution_growth $DurationSeconds 1800 Shadow
                    if ($LASTEXITCODE -ne 0) {
                        throw "bench failed: $runId exit=$LASTEXITCODE"
                    }
                    $copiedPath = Join-Path $projectDir "bench\results\evolution_growth_$runId.json"
                    if (-not (Test-Path -LiteralPath $copiedPath -PathType Leaf)) {
                        throw "bench produced no JSON: $copiedPath"
                    }
                    Move-Item -LiteralPath $copiedPath -Destination $rawPath
                    $result = Read-RunResult $rawPath
                    Write-Progress
                    Invoke-Aggregate
                    if ([bool]$result.valid) {
                        Write-Host "[growth] accepted $runId level=$($result.final_level) tier=$($result.final_tier)"
                        $accepted = $true
                        break
                    }
                    Write-Host "[growth] invalid $runId reasons=$($result.invalid_reasons -join ',');补跑"
                }
                if (-not $accepted) {
                    throw "no valid sample after $MaxAttemptsPerSample attempts: starter=$starter squad=$squadSize sample=$sample"
                }
            }
        }
    }
    Invoke-Aggregate
    Write-Progress
    $progress = Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $progress.running = $false
    $progress | Add-Member -NotePropertyName completed_utc `
        -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $progress | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $progressPath -Encoding UTF8
    Write-Host "[growth] complete valid=$($progress.valid)/$($progress.expected_valid) invalid=$($progress.invalid)"
} finally {
    $env:AGL_BENCH_FIXED_FPS = $previousFixedFps
    Remove-Item Env:AGL_GROWTH_RUN_ID -ErrorAction SilentlyContinue
    Remove-Item Env:AGL_GROWTH_STARTER -ErrorAction SilentlyContinue
    Remove-Item Env:AGL_GROWTH_SQUAD_SIZE -ErrorAction SilentlyContinue
    Remove-Item Env:AGL_GROWTH_SEED -ErrorAction SilentlyContinue
}
