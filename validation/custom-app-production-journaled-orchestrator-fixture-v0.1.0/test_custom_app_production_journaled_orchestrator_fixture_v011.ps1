$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$src=Join-Path $PSScriptRoot 'test_custom_app_production_journaled_orchestrator_fixture.ps1'
$expected='f83039739048ca0774ff6ce78cc21c6440e968a1'
$actual=(git hash-object $src).Trim()
if($actual -cne $expected){throw "fixture v0.1.0 test blob drift $actual != $expected"}
$text=Get-Content -LiteralPath $src -Raw
$patches=@(
    @('$lines=Get-LogLinesJOFV010 $f;$expected=', '$lines=@(Get-LogLinesJOFV010 $f);$expected=', 1, 'happy log array'),
    @('$lines=Get-LogLinesJOFV010 $f;Assert-EqualJOFV010 $lines.Count', '$lines=@(Get-LogLinesJOFV010 $f);Assert-EqualJOFV010 $lines.Count', 1, 'crash log array'),
    @('(Get-LogLinesJOFV010 $f).Count 0', '@(Get-LogLinesJOFV010 $f).Count 0', 2, 'zero callback count'),
    @('$before=(Get-LogLinesJOFV010 $f).Count', '$before=@(Get-LogLinesJOFV010 $f).Count', 1, 'replay before count'),
    @('(Get-LogLinesJOFV010 $f).Count $before', '@(Get-LogLinesJOFV010 $f).Count $before', 1, 'replay after count')
)
foreach($p in $patches){$old=[string]$p[0];$new=[string]$p[1];$expectedCount=[int]$p[2];$label=[string]$p[3];$count=([regex]::Matches($text,[regex]::Escape($old))).Count;if($count -ne $expectedCount){throw "$label patch anchor drift $count != $expectedCount"};$text=$text.Replace($old,$new)}
$runtime=Join-Path $PSScriptRoot 'test_custom_app_production_journaled_orchestrator_fixture.runtime.ps1'
[IO.File]::WriteAllText($runtime,$text,[Text.UTF8Encoding]::new($false))
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runtime
if($LASTEXITCODE){exit $LASTEXITCODE}
