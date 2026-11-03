param([string]$OutputFile)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$include=@('Core','Core_test','vivado_scripts','fpga_release','linux','model','sim','data','docs/validation','README.md','README_VIVADO.md','.gitignore')
$excluded='(^|[\\/])(__pycache__|build|results|\.local|\.Xil)([\\/]|$)|\.pyc$|\.o$|\.ko$|\.jou$|\.wdb$|\.pb$|[\\/]Core_test\.(cache|gen|hw|runs|sim|ip_user_files)([\\/]|$)'
$files=@()
foreach($entry in $include){
 $path=Join-Path $root $entry
 if(!(Test-Path -LiteralPath $path)){throw "Missing submission input: $entry"}
 if((Get-Item -LiteralPath $path).PSIsContainer){$files+=Get-ChildItem -LiteralPath $path -Recurse -File -Force}else{$files+=Get-Item -LiteralPath $path}
}
$relative=@($files | ForEach-Object {$_.FullName.Substring($root.Length+1).Replace('\','/')} | Where-Object {$_ -notmatch $excluded} | Sort-Object -Unique)
$lines=foreach($p in $relative){"$((Get-FileHash -LiteralPath (Join-Path $root $p)).Hash.ToLowerInvariant())  $p"}
[IO.File]::WriteAllText((Join-Path $root 'SHA256SUMS'),(($lines -join "`n")+"`n"),[Text.UTF8Encoding]::new($false))
New-Item -ItemType Directory -Path (Join-Path $root '.local/dist') -Force | Out-Null
$list=Join-Path $root '.local/dist/package_files.txt'
[IO.File]::WriteAllText($list,((($relative+@('SHA256SUMS')) -join "`n")+"`n"),[Text.UTF8Encoding]::new($false))
if(!$OutputFile){$OutputFile=Join-Path $root '.local/dist/FSRCNN_X4_minimal.tar.gz'}
$OutputFile=[IO.Path]::GetFullPath($OutputFile)
& tar -czf $OutputFile -C $root -T $list
if($LASTEXITCODE -ne 0){throw 'Packaging failed'}
"$((Get-FileHash -LiteralPath $OutputFile).Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($OutputFile))" | Set-Content -LiteralPath "$OutputFile.sha256" -Encoding ascii
[pscustomobject]@{Archive=$OutputFile;Files=$relative.Count+1;Bytes=(Get-Item -LiteralPath $OutputFile).Length} | Format-List
