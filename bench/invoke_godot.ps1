param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExe,
    [Parameter(Mandatory = $true)]
    [string]$ProjectDir,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Scenario,
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 86400)]
    [int]$DurationSeconds,
    [ValidateRange(0, 86400)]
    [int]$TimeoutSeconds = 0,
    [string]$ProcDumpExe = '',
    [ValidateSet('Shadow', 'InPlace')]
    [string]$RunMode = 'Shadow',
    [ValidateSet('Headless', 'Visual')]
    [string]$DisplayMode = 'Headless'
)

$ErrorActionPreference = 'Stop'
$lockDir = Join-Path $ProjectDir 'tmp\godot-bench.lock'
$lockOwner = Join-Path $lockDir 'owner.pid'
$jobHandle = [IntPtr]::Zero
$child = $null
$watchdog = $null
$childStarted = $false
$watchdogStarted = $false
$ownsLock = $false
$runProjectDir = $ProjectDir
$shadowProjectDir = ''

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AglBenchNative {
    public const uint SEM_FAILCRITICALERRORS = 0x0001;
    public const uint SEM_NOGPFAULTERRORBOX = 0x0002;
    public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetErrorMode(uint uMode);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetInformationJobObject(
        IntPtr hJob,
        int infoType,
        IntPtr lpJobObjectInfo,
        uint cbJobObjectInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
'@

function Test-OwnerAlive([string]$ownerFile) {
    if (-not (Test-Path -LiteralPath $ownerFile)) {
        return $false
    }
    $ownerText = (Get-Content -LiteralPath $ownerFile -Raw).Trim()
    if ($ownerText -notmatch '^\d+$') {
        return $false
    }
    return $null -ne (Get-Process -Id ([int]$ownerText) -ErrorAction SilentlyContinue)
}

function Get-RunningGodotProcess {
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'godot*' })
}

function Assert-SafeShadowPath([string]$path) {
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedPath = [System.IO.Path]::GetFullPath($path)
    $leaf = Split-Path -Leaf $resolvedPath
    if (-not $resolvedPath.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $leaf.StartsWith('agl-bench-shadow-', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "refusing unsafe shadow path: $resolvedPath"
    }
}

function Get-ShadowProjectDir([string]$sourceDir) {
    $normalized = [System.IO.Path]::GetFullPath($sourceDir).ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').Substring(0, 12)
    } finally {
        $sha.Dispose()
    }
    return Join-Path ([System.IO.Path]::GetTempPath()) "agl-bench-shadow-$hash"
}

function Invoke-RobocopyMirror([string]$source, [string]$destination) {
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $null = & "$env:SystemRoot\System32\robocopy.exe" $source $destination /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
    $code = $LASTEXITCODE
    if ($code -ge 8) {
        throw "robocopy failed for $source (exit=$code)"
    }
}

function Sync-ShadowProject([string]$sourceDir, [string]$destinationDir) {
    Assert-SafeShadowPath $destinationDir
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null

    # Only directories reachable by project.godot are mirrored. Keeping the
    # shadow .godot directory makes subsequent runs fast while isolating the editor cache.
    foreach ($name in @('addons', 'audio', 'i18n', 'resources', 'scenes', 'scripts')) {
        $source = Join-Path $sourceDir $name
        if (Test-Path -LiteralPath $source -PathType Container) {
            Invoke-RobocopyMirror $source (Join-Path $destinationDir $name)
        }
    }
    Get-ChildItem -LiteralPath $sourceDir -File -Force | Where-Object {
        $_.Name -ne 'AGL.console.exe'
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destinationDir $_.Name) -Force
    }

    # Runtime Godot does not rebuild global class_name metadata from an empty
    # project cache. Seed a private copy of the editor-generated type/UID cache
    # and imported artifacts; the headless process never writes the source cache.
    $sourceCache = Join-Path $sourceDir '.godot'
    $shadowCache = Join-Path $destinationDir '.godot'
    if (Test-Path -LiteralPath $sourceCache -PathType Container) {
        New-Item -ItemType Directory -Path $shadowCache -Force | Out-Null
        $sourceImported = Join-Path $sourceCache 'imported'
        if (Test-Path -LiteralPath $sourceImported -PathType Container) {
            Invoke-RobocopyMirror $sourceImported (Join-Path $shadowCache 'imported')
        }
        foreach ($cacheFile in @('.gdignore', 'global_script_class_cache.cfg', 'scene_groups_cache.cfg', 'uid_cache.bin')) {
            $sourceFile = Join-Path $sourceCache $cacheFile
            if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
                Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $shadowCache $cacheFile) -Force
            }
        }
    }

    foreach ($relative in @('bench\results', 'logs')) {
        $outputDir = Join-Path $destinationDir $relative
        if (Test-Path -LiteralPath $outputDir) {
            Get-ChildItem -LiteralPath $outputDir -File -Force | Remove-Item -Force
        } else {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
    }

    # Visual captures must belong to this invocation. A failed Godot startup may
    # otherwise copy a previous run back and make a stale image look like a pass.
    $visualOutputDir = [System.IO.Path]::GetFullPath((Join-Path $destinationDir 'tmp\map_visual_qa'))
    $shadowPrefix = [System.IO.Path]::GetFullPath($destinationDir).TrimEnd('\') + '\'
    if (-not $visualOutputDir.StartsWith($shadowPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "refusing unsafe visual output path: $visualOutputDir"
    }
    if (Test-Path -LiteralPath $visualOutputDir -PathType Container) {
        Remove-Item -LiteralPath $visualOutputDir -Recurse -Force
    }
}

function Copy-ShadowOutputs([string]$sourceShadow, [string]$destinationProject) {
    if ($sourceShadow -eq '') {
        return
    }
    foreach ($relative in @('bench\results', 'logs')) {
        $from = Join-Path $sourceShadow $relative
        if (-not (Test-Path -LiteralPath $from -PathType Container)) {
            continue
        }
        $to = Join-Path $destinationProject $relative
        New-Item -ItemType Directory -Path $to -Force | Out-Null
        Get-ChildItem -LiteralPath $from -File -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $to $_.Name) -Force
        }
    }
    $visualFrom = Join-Path $sourceShadow 'tmp\map_visual_qa'
    if (Test-Path -LiteralPath $visualFrom -PathType Container) {
        $visualTo = Join-Path $destinationProject 'tmp\map_visual_qa'
        New-Item -ItemType Directory -Path $visualTo -Force | Out-Null
        & "$env:SystemRoot\System32\robocopy.exe" $visualFrom $visualTo /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "visual QA output copy failed (exit=$LASTEXITCODE)"
        }
    }
}

function Acquire-BenchLock {
    New-Item -ItemType Directory -Path (Split-Path -Parent $lockDir) -Force | Out-Null
    try {
        New-Item -ItemType Directory -Path $lockDir -ErrorAction Stop | Out-Null
    } catch {
        Start-Sleep -Milliseconds 250
        if (Test-OwnerAlive $lockOwner) {
            throw "another bench owns $lockDir"
        }
        $age = (Get-Date) - (Get-Item -LiteralPath $lockDir).LastWriteTime
        if ((Test-Path -LiteralPath $lockOwner) -or $age.TotalSeconds -ge 10) {
            Remove-Item -LiteralPath $lockDir -Recurse -Force
            New-Item -ItemType Directory -Path $lockDir -ErrorAction Stop | Out-Null
        } else {
            throw "another bench is acquiring $lockDir"
        }
    }
    Set-Content -LiteralPath $lockOwner -Value $PID -NoNewline
    $script:ownsLock = $true
}

function New-KillOnCloseJob {
    $handle = [AglBenchNative]::CreateJobObject([IntPtr]::Zero, $null)
    if ($handle -eq [IntPtr]::Zero) {
        throw "CreateJobObject failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    $info = New-Object AglBenchNative+JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    $info.BasicLimitInformation.LimitFlags = [AglBenchNative]::JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    $size = [Runtime.InteropServices.Marshal]::SizeOf($info)
    $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal($size)
    try {
        [Runtime.InteropServices.Marshal]::StructureToPtr($info, $ptr, $false)
        if (-not [AglBenchNative]::SetInformationJobObject($handle, 9, $ptr, [uint32]$size)) {
            throw "SetInformationJobObject failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
    } catch {
        [AglBenchNative]::CloseHandle($handle) | Out-Null
        throw
    } finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }
    return $handle
}

function Get-BenchRuntimeErrorBlocks([string]$stdoutText, [string]$stderrText) {
    # Godot can abort only the current GDScript method, print a red runtime error,
    # and still exit the process with code 0. Treat those diagnostics as test failures.
    # Compiler warnings and known non-script shutdown noise are intentionally excluded.
    $combined = $stdoutText + "`n" + $stderrText
    $lines = @($combined -split "`r?`n")
    $fatalPatterns = @(
        '^\s*SCRIPT ERROR:',
        'Trying to (?:cast|assign).*freed',
        'previously freed',
        'freed instance',
        '^\s*ERROR:\s+.*(?:Invalid call|Invalid access|Invalid type in function)',
        '^\s*ERROR:\s+.*(?:Attempt to call|Attempted to erase|on a null value|Stack overflow)',
        '^\s*ERROR:\s+\[BenchRuntimeErrorProbe\]'
    )
    $blocks = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $fatal = $false
        foreach ($pattern in $fatalPatterns) {
            if ($line -match $pattern) {
                $fatal = $true
                break
            }
        }
        if (-not $fatal) {
            continue
        }
        $end = [Math]::Min($lines.Count - 1, $i + 3)
        $block = (($lines[$i..$end] | Where-Object { $_ -ne '' }) -join [Environment]::NewLine).Trim()
        if ($block -ne '' -and -not $seen.ContainsKey($block)) {
            $seen[$block] = $true
            $blocks.Add($block)
        }
    }
    return @($blocks)
}

try {
    if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
        throw "Godot does not exist: $GodotExe"
    }
    $version = (Get-Item -LiteralPath $GodotExe).VersionInfo.FileVersion
    if ($version -notlike '4.7*') {
        throw "project.godot requires Godot 4.7; found $version"
    }
    if ($ProcDumpExe -ne '' -and -not (Test-Path -LiteralPath $ProcDumpExe -PathType Leaf)) {
        throw "ProcDump does not exist: $ProcDumpExe"
    }
    Acquire-BenchLock

    if ($RunMode -eq 'InPlace') {
        if (Get-RunningGodotProcess) {
            [Console]::Error.WriteLine('[bench] ERROR: InPlace mode requires all Godot processes to be closed.')
            exit 3
        }
    } else {
        $shadowProjectDir = Get-ShadowProjectDir $ProjectDir
        Write-Host "[bench] syncing isolated shadow=$shadowProjectDir"
        Sync-ShadowProject $ProjectDir $shadowProjectDir
        $runProjectDir = $shadowProjectDir
    }

    if ($TimeoutSeconds -eq 0) {
        $TimeoutSeconds = [Math]::Max(120, $DurationSeconds + 90)
    }

    # Inherited by Godot: suppress Windows critical-error/GP-fault dialog boxes.
    [AglBenchNative]::SetErrorMode(
        [AglBenchNative]::SEM_FAILCRITICALERRORS -bor [AglBenchNative]::SEM_NOGPFAULTERRORBOX
    ) | Out-Null

    $jobHandle = New-KillOnCloseJob
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $fixedFpsOption = ''
    if ($env:AGL_BENCH_FIXED_FPS) {
        $fixedFps = 0
        if (-not [int]::TryParse($env:AGL_BENCH_FIXED_FPS, [ref]$fixedFps) -or
            $fixedFps -lt 1 -or $fixedFps -gt 240) {
            throw "AGL_BENCH_FIXED_FPS must be an integer in 1..240"
        }
        # Deterministic simulation: advance a fixed physics/render delta without
        # synchronizing to wall clock. Growth benches still simulate every 60 Hz tick.
        $fixedFpsOption = "--fixed-fps $fixedFps "
    }
    if ($DisplayMode -eq 'Visual') {
        # Keep the real GL Compatibility renderer while placing the transient test
        # window off-screen. The process remains owned by the same watchdog/job.
        $godotArguments = '{0}--path "{1}" --rendering-method gl_compatibility --windowed --resolution 1600x900 --position 32000,32000 -- --bench={2} --duration={3}' -f `
            $fixedFpsOption, $runProjectDir.Replace('"', '\"'), $Scenario, $DurationSeconds
    } else {
        $godotArguments = '{0}--headless --path "{1}" -- --bench={2} --duration={3}' -f `
            $fixedFpsOption, $runProjectDir.Replace('"', '\"'), $Scenario, $DurationSeconds
    }
    if ($ProcDumpExe -ne '') {
        $dumpDir = Join-Path $ProjectDir 'tmp\crash-dumps'
        New-Item -ItemType Directory -Path $dumpDir -Force | Out-Null
        $psi.FileName = $ProcDumpExe
        $psi.Arguments = '-accepteula -ma -e -x "{0}" "{1}" {2}' -f `
            $dumpDir.Replace('"', '\"'), $GodotExe.Replace('"', '\"'), $godotArguments
        Write-Host "[bench] procdump=$ProcDumpExe"
    } else {
        $psi.FileName = $GodotExe
        $psi.Arguments = $godotArguments
    }
    $psi.WorkingDirectory = $runProjectDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $psi

    Write-Host "[bench] godot=$GodotExe"
    Write-Host "[bench] mode=$RunMode display=$DisplayMode project=$runProjectDir"
    if ($fixedFpsOption -ne '') {
        Write-Host "[bench] deterministic fixed-fps=$fixedFps (wall-clock sync disabled)"
    }
    Write-Host "[bench] scenario=$Scenario duration=${DurationSeconds}s timeout=${TimeoutSeconds}s"
    Write-Host '[bench] launching...'
    if (-not $child.Start()) {
        throw 'Godot process failed to start.'
    }
    $childStarted = $true
    if (-not [AglBenchNative]::AssignProcessToJobObject($jobHandle, $child.Handle)) {
        throw "AssignProcessToJobObject failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    # Read both pipes asynchronously to avoid buffer deadlock without invoking
    # PowerShell scriptblocks on Process event threads (PS 5 has no runspace there).
    $stdoutTask = $child.StandardOutput.ReadToEndAsync()
    $stderrTask = $child.StandardError.ReadToEndAsync()

    # A separate watcher survives cancellation of this launcher. It explicitly
    # kills the complete target tree on timeout or when this owner PID vanishes.
    $timeoutMarker = Join-Path $lockDir 'timeout.marker'
    $watchdogPsi = New-Object System.Diagnostics.ProcessStartInfo
    $watchdogPsi.FileName = Join-Path $PSHOME 'powershell.exe'
    $watchdogPsi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -OwnerPid {1} -TargetPid {2} -TimeoutSeconds {3} -TimeoutMarker "{4}"' -f `
        (Join-Path $PSScriptRoot 'watch_godot.ps1'), $PID, $child.Id, $TimeoutSeconds, $timeoutMarker
    $watchdogPsi.UseShellExecute = $false
    $watchdogPsi.CreateNoWindow = $true
    $watchdog = New-Object System.Diagnostics.Process
    $watchdog.StartInfo = $watchdogPsi
    if (-not $watchdog.Start()) {
        throw 'Godot watchdog failed to start.'
    }
    $watchdogStarted = $true

    $child.WaitForExit()
    $watchdog.WaitForExit(2000) | Out-Null
    # Always surface the captured engine output, including watchdog timeouts.
    # Without this, the most useful import/crash breadcrumb was discarded on exit 124.
    $stdoutText = $stdoutTask.Result
    $stderrText = $stderrTask.Result
    [Console]::Out.Write($stdoutText)
    [Console]::Error.Write($stderrText)
    if (Test-Path -LiteralPath $timeoutMarker) {
        [Console]::Error.WriteLine("[bench] ERROR: Godot exceeded ${TimeoutSeconds}s; its entire process tree was terminated.")
        exit 124
    }
    $runtimeErrorBlocks = @(Get-BenchRuntimeErrorBlocks $stdoutText $stderrText)
    if ($runtimeErrorBlocks.Count -gt 0) {
        [Console]::Error.WriteLine("[bench] ERROR: runtime-error gate found $($runtimeErrorBlocks.Count) fatal diagnostic block(s).")
        foreach ($block in $runtimeErrorBlocks) {
            [Console]::Error.WriteLine("[bench] RUNTIME ERROR:`n$block")
        }
        if ($child.ExitCode -eq 0) {
            # Distinct from assertion failure (1), launcher failure (2), lock (3), timeout (124).
            exit 86
        }
    }
    exit $child.ExitCode
} catch {
    [Console]::Error.WriteLine("[bench] ERROR: $($_.Exception.Message)")
    exit 2
} finally {
    if ($childStarted -and -not $child.HasExited) {
        $null = & "$env:SystemRoot\System32\taskkill.exe" /PID $child.Id /T /F 2>&1
    }
    if ($watchdogStarted -and -not $watchdog.HasExited) {
        Stop-Process -Id $watchdog.Id -Force -ErrorAction SilentlyContinue
    }
    if ($jobHandle -ne [IntPtr]::Zero) {
        [AglBenchNative]::CloseHandle($jobHandle) | Out-Null
    }
    Copy-ShadowOutputs $shadowProjectDir $ProjectDir
    if ($ownsLock -and (Test-Path -LiteralPath $lockDir)) {
        Remove-Item -LiteralPath $lockDir -Recurse -Force
    }
}
