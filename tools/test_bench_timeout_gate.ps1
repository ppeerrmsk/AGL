$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskWrapper=Join-Path $taskRoot 'bench/invoke_godot.ps1'
$taskAst=[System.Management.Automation.Language.Parser]::ParseFile($taskWrapper,[ref]$null,[ref]$null)
$taskFunction=$taskAst.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-BenchRuntimeErrorBlocks'},$true)
if($null -eq $taskFunction){throw 'Actual runtime gate function not found'}
. ([scriptblock]::Create($taskFunction.Extent.Text))
$taskCode=[IO.File]::ReadAllText($taskWrapper)
$taskMatch=[regex]::Match($taskCode,'(?s)\$didTimeout = Test-Path -LiteralPath \$timeoutMarker.*?exit \$child.ExitCode')
if(-not $taskMatch.Success){throw 'Actual final result decision not found'}
# 运行实际裁决块；仅把终止测试宿主的 exit 改成返回值，不改条件或错误门。
$taskDecision=[scriptblock]::Create([regex]::Replace($taskMatch.Value,'\bexit (?=\d+|\$child.ExitCode)','return '))
$taskWork=Join-Path $taskRoot 'tmp/timeout-gate'
New-Item -ItemType Directory -Force -Path $taskWork | Out-Null
$taskMarker=Join-Path $taskWork 'timeout.marker'
[IO.File]::WriteAllText($taskMarker,'fixture')
$taskCases=@(
 @{timeout=$false;engine=0;stdout='';stderr='';expected=0},
 @{timeout=$false;engine=1;stdout='';stderr='';expected=1},
 @{timeout=$true;engine=0;stdout='';stderr='';expected=124},
 @{timeout=$true;engine=1;stdout='SCRIPT ERROR: Invalid call.';stderr='';expected=86},
 @{timeout=$true;engine=0;stdout='';stderr='SCRIPT ERROR: Parse Error: fixture';expected=86},
 @{timeout=$true;engine=124;stdout='';stderr='ERROR: Attempting to use an uninitialized RID';expected=86},
 @{timeout=$false;engine=0;stdout='';stderr='SCRIPT ERROR: Invalid call.';expected=86}
)
foreach($taskCase in $taskCases){
 $timeoutMarker=if($taskCase.timeout){$taskMarker}else{Join-Path $taskWork 'absent.marker'}
 $TimeoutSeconds=300
 $child=[pscustomobject]@{ExitCode=$taskCase.engine}
 $stdoutText=$taskCase.stdout; $stderrText=$taskCase.stderr
 $taskActual=& $taskDecision
 if($taskActual -ne $taskCase.expected){throw "expected=$($taskCase.expected) actual=$taskActual"}
}
Write-Output '[Timeout gate] pass=7 fail=0 (actual wrapper decision, no engine started)'
