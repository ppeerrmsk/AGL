$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $taskRoot 'bench/invoke_godot.ps1'),[ref]$null,[ref]$null)
$taskFunction=$taskAst.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-BenchRuntimeErrorBlocks'},$true)
if($null -eq $taskFunction){throw 'Actual runtime gate function not found'}
. ([scriptblock]::Create($taskFunction.Extent.Text))
$taskShader='SHADER ERROR: Built-in function is only supported on high-end platforms.'
foreach($taskText in @($taskShader,'ERROR: Shader compilation failed.')){
 if(@(Get-BenchRuntimeErrorBlocks $taskText '').Count -ne 1){throw 'stdout shader error missed'}
 if(@(Get-BenchRuntimeErrorBlocks '' $taskText).Count -ne 1){throw 'stderr shader error missed'}
}
$taskTrace="$taskShader`n at: shader:37`n [0] caller`nERROR: Shader compilation failed.`n at: driver"
$taskBlocks=@(Get-BenchRuntimeErrorBlocks '' $taskTrace)
if($taskBlocks.Count -ne 2 -or $taskBlocks[0] -notmatch 'caller' -or $taskBlocks[0] -match 'compilation failed'){throw 'Shader blocks mixed or truncated'}
if(@(Get-BenchRuntimeErrorBlocks 'WARNING: Shader compilation took 20 ms.' '').Count -ne 0){throw 'Nonfatal warning misclassified'}
$taskActual=Join-Path $taskRoot 'tmp/tokyo-envelope-atlas-04.log'
if(Test-Path -LiteralPath $taskActual){
 if(@(Get-BenchRuntimeErrorBlocks (Get-Content -LiteralPath $taskActual -Raw) '').Count -lt 2){throw 'Observed shader failure missed'}
}
Write-Output '[Shader gate] pass: stdout/stderr, trace boundaries, warning negative, actual failure replay'
