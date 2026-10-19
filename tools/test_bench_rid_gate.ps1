$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $taskRoot 'bench/invoke_godot.ps1'),[ref]$null,[ref]$null)
$taskFunction=$taskAst.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-BenchRuntimeErrorBlocks'},$true)
if($null -eq $taskFunction){throw 'Actual runtime gate function not found'}
. ([scriptblock]::Create($taskFunction.Extent.Text))
$taskCases=@('ERROR: Attempting to initialize the wrong RID','ERROR: Initializing already initialized RID',
    'ERROR: Attempting to use an uninitialized RID','ERROR: Attempted to free an uninitialized or invalid RID',
    'ERROR: unimplemented base type encountered in renderer scene cull')
foreach($taskCase in $taskCases){if(@(Get-BenchRuntimeErrorBlocks '' $taskCase).Count -ne 1){throw $taskCase}}
if(@(Get-BenchRuntimeErrorBlocks '' 'ERROR: 13 RID allocations were leaked at exit.').Count -ne 0){throw 'Shutdown count is not the native initialization failure'}
$taskTrace="ERROR: unimplemented base type encountered in renderer scene cull`n at: native`n GDScript backtrace:`n [0] one`n [1] two`n [2] three`n [3] deepest`n`nWARNING: next"
$taskBlocks=@(Get-BenchRuntimeErrorBlocks '' $taskTrace)
if($taskBlocks.Count -ne 1 -or $taskBlocks[0] -notmatch 'deepest' -or $taskBlocks[0] -match 'WARNING'){throw 'Native traceback truncated or mixed'}
if(@(Get-BenchRuntimeErrorBlocks 'SCRIPT ERROR: Invalid call. Previously freed instance.' '').Count -ne 1){throw 'Existing script error gate regressed'}
Write-Output '[RID gate] pass=8 fail=0 (actual wrapper function, no engine started)'
