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
    [string]$ProcDumpExe = ''
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
    if (Get-RunningGodotProcess) {
        [Console]::Error.WriteLine('[bench] ERROR: Godot is already running. Close the editor/other bench before testing.')
        exit 3
    }

    Acquire-BenchLock

    # Re-check after taking the lock to close the process-check/mkdir race window.
    if (Get-RunningGodotProcess) {
        [Console]::Error.WriteLine('[bench] ERROR: Godot started while the bench lock was being acquired.')
        exit 3
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
    $godotArguments = '--headless --path "{0}" -- --bench={1} --duration={2}' -f `
        $ProjectDir.Replace('"', '\"'), $Scenario, $DurationSeconds
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
    $psi.WorkingDirectory = $ProjectDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $psi

    Write-Host "[bench] godot=$GodotExe"
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
    if (Test-Path -LiteralPath $timeoutMarker) {
        [Console]::Error.WriteLine("[bench] ERROR: Godot exceeded ${TimeoutSeconds}s; its entire process tree was terminated.")
        exit 124
    }
    [Console]::Out.Write($stdoutTask.Result)
    [Console]::Error.Write($stderrTask.Result)
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
    if ($ownsLock -and (Test-Path -LiteralPath $lockDir)) {
        Remove-Item -LiteralPath $lockDir -Recurse -Force
    }
}
