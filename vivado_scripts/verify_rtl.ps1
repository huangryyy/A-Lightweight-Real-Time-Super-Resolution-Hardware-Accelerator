param([string]$VivadoBin = "$env:XILINX_VIVADO/bin", [switch]$FullFrame)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!(Test-Path -LiteralPath (Join-Path $VivadoBin 'xvlog.bat'))){throw 'Pass -VivadoBin <Vivado2023.2/bin>, or source settings64.bat first'}
$work=Join-Path $root 'build/rtl_checks'
if($FullFrame -and !(Test-Path -LiteralPath (Join-Path $root 'sim/full_frame/expected7.mem'))){throw 'Run python model/prepare_hardware.py --full-frame first'}
New-Item -ItemType Directory -Path $work -Force | Out-Null
Copy-Item -Path (Join-Path $root 'sim/*.mem') -Destination $work -Force
$sources=@(Get-ChildItem -LiteralPath (Join-Path $root 'Core') -Filter '*.v' | ForEach-Object {$_.FullName})
foreach($name in @('ip_models.v','control_fifo_models.v','tb_control_bias.v','tb_residual_edges.v')){$sources+=Join-Path $root "sim/$name"}
$tops=@('tb_FSRCNN_X4','tb_control_bias','tb_residual_edges')
if($FullFrame){
 $sources+=Join-Path $root 'sim/tb_full_frame.v'
 New-Item -ItemType Directory -Path (Join-Path $work 'full_frame') -Force | Out-Null
 Copy-Item -Path (Join-Path $root 'sim/full_frame/*.mem') -Destination (Join-Path $work 'full_frame') -Force
 $tops=@('tb_full_frame')
}
Push-Location $work
try {
 & (Join-Path $VivadoBin 'xvlog.bat') --work xil_defaultlib @sources
 if($LASTEXITCODE -ne 0){throw 'xvlog failed'}
 foreach($top in $tops){
  & (Join-Path $VivadoBin 'xelab.bat') "xil_defaultlib.$top" -s $top
  if($LASTEXITCODE -ne 0){throw "xelab failed: $top"}
  & (Join-Path $VivadoBin 'xsim.bat') $top -runall -log "$top.log"
  if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath "$top.log" -Pattern 'PASS' -Quiet) -or (Select-String -LiteralPath "$top.log" -Pattern 'FATAL:|Fatal:|MISMATCH' -Quiet)){throw "Simulation failed: $top"}
 }
 Write-Output "RTL_CHECKS_PASS: $($tops -join ', ')"
} finally {Pop-Location}

