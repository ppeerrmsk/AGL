param(
    [ValidateSet('C1','C2','Near','FastWest','FastNorth')][string]$Scenario='C1',
    [ValidateRange(10,120)][int]$Duration=36,
    [string]$Godot='',
    [switch]$Interactive,
    [switch]$Trace,
    [switch]$DeepTrace,
    [switch]$ExtendedCpuTrace,
    [ValidateRange(0,65535)][int]$RemoteProfilePort=0,
    [switch]$SynchronousSelectionControl,
    [switch]$Counterfactual
)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$package=Join-Path $projectRoot 'resources/maps/tokyo_playable/m20/package.json'
$expected='424e4aa1db195308389ffcce30ff672bc5b23851810801847199b4d9d572d858'
if (-not (Test-Path -LiteralPath $package)) {
    throw 'Missing or different M20 package. Install and verify the frozen Release bundle first.'
}
$hashAlgorithm=[Security.Cryptography.SHA256]::Create()
$packageStream=[IO.File]::OpenRead($package)
try { $actualHash=[BitConverter]::ToString($hashAlgorithm.ComputeHash($packageStream)).Replace('-','').ToLowerInvariant() }
finally { $packageStream.Dispose(); $hashAlgorithm.Dispose() }
if ($actualHash -ne $expected) { throw 'M20 package digest differs from the frozen baseline.' }
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'resources/maps/tokyo_volume_preview/downtown_lod.res'))) {
    throw 'Missing 3D entry gate resource; refusing a misleading 2D fallback benchmark.'
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.godot/global_script_class_cache.cfg'))) {
    throw 'Open project.godot with Godot 4.7+ and finish first import, then close the editor before reproducing.'
}
$lock=Join-Path $projectRoot 'tmp/godot-bench.lock'
if (Test-Path -LiteralPath $lock) { throw 'Another bench/install owns the lock; do not steal it.' }
$memory=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
if ([double]$memory.FreePhysicalMemory*1024 -lt 7.5GB) { throw 'Free RAM is below the project 7.5 GiB test gate; release memory before running.' }
# 只重放实际默认行为；清除继承的实验开关，结束后恢复调用者环境。
$previous=@{}
Get-ChildItem Env: | Where-Object { $_.Name.StartsWith('AGL_') } | ForEach-Object { $previous[$_.Name]=$_.Value }
$oldGodot=$env:GODOT
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$out=Join-Path $projectRoot ('tmp/map-runtime-repro/'+$stamp+'-'+$Scenario)
New-Item -ItemType Directory -Path $out -ErrorAction Stop | Out-Null
$resultCode=1
try {
    Get-ChildItem Env: | Where-Object { $_.Name.StartsWith('AGL_') } | ForEach-Object { Remove-Item -LiteralPath ('Env:'+ $_.Name) }
    if ($Godot -ne '') { $env:GODOT=$Godot }
    $env:AGL_TOKYO_INSTALLED_TEST='1'
    if ($Interactive) { $env:AGL_BENCH_INTERACTIVE='1' }
    if ($RemoteProfilePort -ne 0) {
        if ($RemoteProfilePort -lt 1024) { throw 'RemoteProfilePort must be 1024..65535, or 0 to disable.' }
        $env:AGL_BENCH_REMOTE_PROFILE_PORT=[string]$RemoteProfilePort
    }
    if ($SynchronousSelectionControl) { $env:AGL_TOKYO_SYNC_SELECTION='1' }
    if ($DeepTrace) { $Trace=$true; $env:AGL_TOKYO_RENDER_TIMELINE='1'; $env:AGL_BENCH_FRAME_TRACE_MODE='full' }
    if ($ExtendedCpuTrace) {
        if (-not $DeepTrace) { throw 'ExtendedCpuTrace requires -DeepTrace for complete leaf accounting.' }
        $env:AGL_BENCH_EXTENDED_CPU_TRACE='1'
    }
    if ($Trace) {
        $env:AGL_TOKYO_WALL_TRACE='1'
        $env:AGL_TOKYO_RENDER_TRACE='backend'
        $env:AGL_TOKYO_SELECTION_TRACE='1'
    }
    if ($Counterfactual) {
        if (-not $Trace) { throw 'Counterfactual requires -Trace; it performs extra diagnostic selections and is not a performance baseline.' }
        $env:AGL_TOKYO_HANDOFF_COUNTERFACTUAL='1'
    }
    $env:AGL_TOKYO_HLOD_PACKAGE='res://resources/maps/tokyo_playable/m20/package.json'
    $env:AGL_TOKYO_HLOD_PACKAGE_SHA=$expected
    $bench=@{C1='tokyo_volume_c1';C2='tokyo_volume_c2';Near='tokyo_volume_near'}[$Scenario]
    $seconds=$Duration
    $timeout=300
    if ($Scenario.StartsWith('Fast')) {
        $bench='tokyo_cells_lifecycle';$seconds=1
        $env:AGL_TOKYO_HLOD_PLAY_SECONDS=[string]$Duration
        $env:AGL_TOKYO_HLOD_INPUT_REPLAY='1'
        $env:AGL_TOKYO_HLOD_FAST_INPUT='1'
        $env:AGL_TOKYO_HLOD_REPLAY_FPS='60'
        $env:AGL_TOKYO_HLOD_REPLAY_COMBAT='1'
        $env:AGL_TOKYO_HLOD_INPUT_REGION= $(if($Scenario -eq 'FastWest'){'west'}else{'north'})
        $env:AGL_TOKYO_HLOD_ROUTE_OUT=Join-Path $out 'route'
    }
    $values=@{}
    Get-ChildItem Env: | Where-Object { $_.Name.StartsWith('AGL_') } | ForEach-Object { $values[$_.Name]=$_.Value }
    $codeVersion=(& git -C $projectRoot rev-parse HEAD 2>$null | Out-String).Trim()
    [ordered]@{scenario=$Scenario;bench=$bench;duration=$Duration;source_commit=$codeVersion;package_sha256=$expected;
        environment=$values;mode='Shadow Visual';started_at=(Get-Date).ToString('o');
        historical_175_fixture=$false;performance_pass_claimed=$false} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'request.json') -Encoding UTF8
    # Windows PowerShell把外部stderr包装为错误记录；保留日志/真实退出码，不让警告提前跳过结果记录。
    $ErrorActionPreference='Continue'
    & (Join-Path $projectRoot 'bench/run.cmd') $bench $seconds $timeout Shadow Visual 2>&1 |
        Tee-Object -FilePath (Join-Path $out 'wrapper.log')
    $resultCode=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    [ordered]@{wrapper_exit=$resultCode;finished_at=(Get-Date).ToString('o');
        bench_results=(Join-Path $projectRoot 'bench/results');output=$out} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'result.json') -Encoding UTF8
} finally {
    Get-ChildItem Env: | Where-Object { $_.Name.StartsWith('AGL_') } | ForEach-Object { Remove-Item -LiteralPath ('Env:'+ $_.Name) }
    foreach ($key in $previous.Keys) { Set-Item -LiteralPath ('Env:'+ $key) -Value $previous[$key] }
    if ($null -eq $oldGodot) { Remove-Item Env:GODOT -ErrorAction SilentlyContinue } else { $env:GODOT=$oldGodot }
}
Write-Output "Repro output: $out"
Write-Output "Wrapper exit: $resultCode (1 may record the expected performance/coverage failure; 86 is a runtime error; 124 is timeout)."
exit $resultCode
