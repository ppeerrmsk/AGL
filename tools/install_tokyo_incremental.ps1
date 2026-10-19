param(
    [Parameter(Mandatory=$true)][string]$Inventory,
    [Parameter(Mandatory=$true)][string]$ExpectedSha,
    [Parameter(Mandatory=$true)][string]$Project
)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath($Project).TrimEnd('\','/')
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot'))) { throw 'Not an AGL project' }
if ((Get-FileHash -LiteralPath $Inventory -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedSha.ToLowerInvariant()) { throw 'Inventory digest mismatch' }
$data=Get-Content -LiteralPath $Inventory -Raw | ConvertFrom-Json
if ($data.schema -ne 1 -or $data.target -notmatch '^res://resources/maps/tokyo_playable/[a-z][a-z0-9_]+/$' -or $data.default_changed -ne $false) { throw 'Invalid incremental inventory' }
$targetRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot $data.target.Substring(6))).TrimEnd('\','/')
$mapRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot 'resources/maps/tokyo_playable')).TrimEnd('\','/')
if (-not $targetRoot.StartsWith($mapRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $targetRoot)) { throw 'Destination must be a fresh map version' }
$stagingRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp')).TrimEnd('\','/')
$sources=@{}
$jobs=New-Object System.Collections.Generic.List[object]
$bytes=0L
foreach ($item in $data.copies) {
    $relative=[string]$item.relative
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::GetExtension($relative) -notin @('.res','.bin','.json')) { throw "Unsafe destination: $relative" }
    $destination=[IO.Path]::GetFullPath((Join-Path $targetRoot $relative))
    if (-not $destination.StartsWith($targetRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or $sources.ContainsKey($destination)) { throw "Duplicate or escaped destination: $relative" }
    $sourceValue=[string]$item.source
    $fromProject=$sourceValue.StartsWith('res://',[StringComparison]::Ordinal)
    $source=[IO.Path]::GetFullPath($(if($fromProject){Join-Path $projectRoot $sourceValue.Substring(6)}else{$sourceValue}))
    $allowedRoot=$(if($fromProject){$mapRoot}else{$stagingRoot})
    if (-not $source.StartsWith($allowedRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw "Source outside approved map/staging area: $source" }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.sha256) { throw "Source digest mismatch: $relative" }
    $sources[$destination]=$item.sha256
    $bytes+=(Get-Item -LiteralPath $source).Length
    $jobs.Add([PSCustomObject]@{Source=$source;Destination=$destination;Sha=$item.sha256})
}
$packageFile=Join-Path $targetRoot 'package.json'
if ($jobs.Count -eq 0 -or $data.package.path -ne ($data.target+'package.json') -or $sources[$packageFile] -ne $data.package.sha256) { throw 'Missing or inconsistent package entry' }
$drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($targetRoot))
if ($drive.AvailableFreeSpace -lt $bytes+1GB) { throw 'Insufficient installation space plus 1 GiB safety reserve' }
# 与引擎测试共用owner锁；从不回收或覆盖其他进程的锁。
$lockRoot=Join-Path $stagingRoot 'godot-bench.lock'
$lockOwner=Join-Path $lockRoot 'owner.pid'
$ownsLock=$false
try {
    New-Item -ItemType Directory -Path $lockRoot -ErrorAction Stop | Out-Null
    $ownsLock=$true
    Set-Content -LiteralPath $lockOwner -Value $PID -NoNewline
    if (Test-Path -LiteralPath $targetRoot) { throw 'Destination appeared while preparing installation' }
    New-Item -ItemType Directory -Path $targetRoot | Out-Null
    # 整批复制/回读完成前隔离编辑器扫描；失败保留隔离目录，不删用户或测试资源。
    $ignoreFile=Join-Path $targetRoot '.gdignore'
    [IO.File]::WriteAllText($ignoreFile,'')
    foreach ($job in $jobs) {
        $directory=Split-Path -Parent $job.Destination
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
        if (Test-Path -LiteralPath $job.Destination) { throw 'Refusing to overwrite an existing asset' }
        Copy-Item -LiteralPath $job.Source -Destination $job.Destination
        if ((Get-FileHash -LiteralPath $job.Destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $job.Sha) { throw 'Copied asset digest mismatch' }
    }
    Remove-Item -LiteralPath $ignoreFile
    Write-Output "Installed candidate: $targetRoot"
    Write-Output "Verified files=$($jobs.Count) bytes=$bytes default_changed=false"
} finally {
    if ($ownsLock -and (Test-Path -LiteralPath $lockOwner) -and (Get-Content -LiteralPath $lockOwner -Raw).Trim() -eq [string]$PID) {
        Remove-Item -LiteralPath $lockOwner
        # 不递归删除；如目录里出现非本安装器文件，保留并报错。
        if (@(Get-ChildItem -LiteralPath $lockRoot -Force).Count -ne 0) { throw 'Unexpected lock contents retained' }
        Remove-Item -LiteralPath $lockRoot
    }
}
