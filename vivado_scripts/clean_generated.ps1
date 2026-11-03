# Deletes only known generated products and audited unused source artifacts.
# Run after closing all Vivado/XSIM processes. Does not touch Linux deliverables.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$ipList = Get-Content -LiteralPath (Join-Path $root 'vivado_scripts/ip_files.txt')
if ($ipList.Count -ne 14) { throw 'Expected the completed fourteen-IP audit before cleanup' }
if ((Get-FileHash -LiteralPath (Join-Path $root 'fpga_release/Top.bit')).Hash -ine '6e0040388dbf8bc913e04ab4b84025ecf8fb4a374be22ab1f4d67e588f3f99cb') {throw 'Release bitstream not preserved'}
$retained = @($ipList | ForEach-Object {Split-Path (Split-Path $_ -Parent) -Leaf})
$targets = [Collections.Generic.List[string]]::new()
foreach ($relative in @('build','.Xil','Core_test/.Xil','Core_test/Core_test.cache','Core_test/Core_test.gen','Core_test/Core_test.hw','Core_test/Core_test.ip_user_files','Core_test/Core_test.runs','Core_test/Core_test.sim','Core_test/Core_test.srcs/utils_1','sim/xsim.dir')) {
 $targets.Add((Join-Path $root $relative))
}
foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $root 'Core_test/Core_test.srcs/sources_1/ip') -Directory) {
 if ($dir.Name -notin $retained) {$targets.Add($dir.FullName)}
}
foreach ($relative in @('Core/tb_FSRCNN_X2.v','Core/Clock.xdc','Core_test/Clock.xdc','Core_test/ddr4.xdc','Core_test/pcie.xdc')) {$targets.Add((Join-Path $root $relative))}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'Core_test') -File -Force) {
 if ($file.Extension -in @('.log','.jou','.str')) {$targets.Add($file.FullName)}
}
$proof = @('regression.log','full_frame_regression.log','control_bias_final.log','residual_edges.log')
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'sim') -File -Force) {
 if (($file.Extension -in @('.log','.jou','.pb','.wdb')) -and $file.Name -notin $proof) {$targets.Add($file.FullName)}
}
$report = @()
foreach ($path in $targets | Sort-Object -Unique) {
 if (!(Test-Path -LiteralPath $path)) {continue}
 $resolved = (Resolve-Path -LiteralPath $path).Path
 if (!$resolved.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw "Outside workspace: $resolved"}
 $item=Get-Item -LiteralPath $resolved -Force
 if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {throw "Unexpected link: $resolved"}
 $files=if($item.PSIsContainer){@(Get-ChildItem -LiteralPath $resolved -File -Force -Recurse)}else{@($item)}
 $bytes=($files | Measure-Object -Property Length -Sum).Sum
 $report += [pscustomobject]@{Path=$resolved.Substring($root.Length+1);Files=$files.Count;Bytes=$bytes}
}
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root 'fpga_release/cleanup_report.json') -Encoding utf8
# Paths have been resolved, bounded and individually recorded before mutation.
foreach($entry in $report) {
 $checked=[IO.Path]::GetFullPath((Join-Path $root $entry.Path))
 if(!$checked.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Outside workspace'}
 Remove-Item -LiteralPath $checked -Recurse -Force
}
[pscustomobject]@{Targets=$report.Count;Files=($report|Measure-Object Files -Sum).Sum;RemovedMiB=[math]::Round(($report|Measure-Object Bytes -Sum).Sum/1MB,2)} | Format-List

