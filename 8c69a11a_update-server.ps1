# Aurelion — puts the published Aurelion changes into the Coop dedicated server.
# Run on the server (PowerShell):  iwr <raw url>/update-server.ps1 -UseBasicParsing | iex
# Stop the server in the Dedicated Server Manager first, then start it again after this finishes.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$base   = 'https://raw.githubusercontent.com/bannerlordaurelion/aurelion-updates/main/'
$coop   = 'C:\CoopServer\engine\Modules\Coop'
$serverBin = Join-Path $coop 'bin\Win64_Shipping_Server'
if (-not (Test-Path (Join-Path $coop 'SubModule.xml'))) { throw "Coop not found in $coop" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "C:\AurelionBackups\server-coop-$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Copy-Item (Join-Path $coop 'SubModule.xml') $backup
if (Test-Path (Join-Path $coop 'aurelion')) { Copy-Item (Join-Path $coop 'aurelion') $backup -Recurse }
if (Test-Path (Join-Path $serverBin 'Aurelion.Core.dll')) { Copy-Item (Join-Path $serverBin 'Aurelion.Core.dll') $backup }
Write-Host "Backup: $backup"

$m = Invoke-RestMethod ($base + 'manifest.json?t=' + [DateTime]::UtcNow.Ticks)
$mod = $m.modules | Where-Object { $_.id -eq 'Coop' }
$files = $mod.files | Where-Object { $_.path -like 'aurelion/*' -or $_.path -eq 'bin/Win64_Shipping_Client/Aurelion.Core.dll' }
if (-not $files) { throw 'The published Coop has no Aurelion files yet.' }
foreach ($f in $files) {
  if ($f.path -like 'aurelion/*' -and $f.path -like '*.ps1') { continue }
  $url = if ($f.url) { $base + $f.url } else { $base + $m.baseUrl + 'Coop/' + $f.path }
  if ($f.path -like 'bin/*') { $dest = Join-Path $serverBin 'Aurelion.Core.dll' } else { $dest = Join-Path $coop ($f.path -replace '/', '\') }
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  Invoke-WebRequest $url -OutFile "$dest.tmp" -UseBasicParsing
  $h = (Get-FileHash "$dest.tmp" -Algorithm SHA256).Hash
  if ($h -ne $f.sha256.ToUpper()) { Remove-Item "$dest.tmp"; throw "Checksum mismatch: $($f.path)" }
  Move-Item "$dest.tmp" $dest -Force
  Unblock-File $dest
  Write-Host "OK  $($f.path)"
}

# add our sub-module to the server's Coop SubModule.xml (once)
$xmlPath = Join-Path $coop 'SubModule.xml'
[xml]$x = Get-Content $xmlPath -Raw -Encoding UTF8
$subs = $x.Module.SubModules
foreach ($s in @($subs.SubModule)) { if ($s.DLLName.value -eq 'Aurelion.Core.dll') { [void]$subs.RemoveChild($s) } }
$first = @($subs.SubModule)[0]
$e = $x.CreateElement('SubModule')
foreach ($pair in @(@('Name','Aurelion Core'), @('DLLName','Aurelion.Core.dll'), @('SubModuleClassType','Aurelion.Core.SubModule'))) {
  $n = $x.CreateElement($pair[0]); $n.SetAttribute('value', $pair[1]); [void]$e.AppendChild($n)
}
if ($first.Tags) { [void]$e.AppendChild($first.Tags.CloneNode($true)) }
[void]$subs.AppendChild($e)
$x.Save($xmlPath)
Write-Host 'Done. Start the server again from the Dedicated Server Manager.'
