# Explicit deployment copies for a standalone Linux folder. Never copies keys.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($name in @('Top.bit','Top.ltx')){Copy-Item -LiteralPath (Join-Path $root "fpga_release/$name") -Destination (Join-Path $root "linux/$name") -Force}
New-Item -ItemType Directory -Path (Join-Path $root 'linux/model'),(Join-Path $root 'linux/data') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'model/hardware/X4') -Destination (Join-Path $root 'linux/model') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'data/lr') -Destination (Join-Path $root 'linux/data') -Recurse -Force
$base=Join-Path $root 'linux'
$exclude='(^|[\\/])(__pycache__|results|\.Xil)([\\/]|$)|\.pyc$|\.o$|\.ko$|\.mod(\.c)?$|\.cmd$|[\\/](Module.symvers|modules.order|SHA256SUMS)$'
$lines=Get-ChildItem -LiteralPath $base -File -Recurse | Where-Object {$_.FullName -notmatch $exclude} | Sort-Object FullName | ForEach-Object {
 "$((Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant())  $($_.FullName.Substring($base.Length+1).Replace('\','/'))"
}
[IO.File]::WriteAllText((Join-Path $base 'SHA256SUMS'),(($lines -join "`n")+"`n"),[Text.UTF8Encoding]::new($false))
Write-Output "Standalone Linux manifest files: $($lines.Count)"
