$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $repoRoot 'prepare-pi3-dsi-bookworm-sd.ps1'
$script = Get-Content -Path $scriptPath -Raw -Encoding UTF8

if ($script -notmatch 'Get-FileHash -Path \$Path -Algorithm SHA256') {
    throw 'prepare-pi3-dsi-bookworm-sd.ps1 does not verify the downloaded image checksum'
}

if (
    $script -notmatch '\$process = Start-Process' -or
    $script -notmatch '-PassThru' -or
    $script -notmatch '\$process\.ExitCode -ne 0'
) {
    throw 'prepare-pi3-dsi-bookworm-sd.ps1 does not fail clearly when Raspberry Pi Imager exits with an error'
}

$stageOnlyIndex = $script.IndexOf('if ($StageOnly) {')
$diskResolveIndex = $script.IndexOf('$targetDisk = Resolve-DiskNumber')
$imagerResolveIndex = $script.IndexOf('$imagerPath = Get-RpiImagerPath')
if ($stageOnlyIndex -lt 0 -or $diskResolveIndex -lt 0 -or $imagerResolveIndex -lt 0) {
    throw 'prepare-pi3-dsi-bookworm-sd.ps1 is missing its stage-only or flashing setup blocks'
}

if ($stageOnlyIndex -gt $diskResolveIndex -or $stageOnlyIndex -gt $imagerResolveIndex) {
    throw 'prepare-pi3-dsi-bookworm-sd.ps1 resolves the disk or Raspberry Pi Imager before stage-only mode can exit'
}

if (
    $script -notmatch 'network_ready=0' -or
    $script -notmatch 'Network did not become ready in time' -or
    $script -notmatch 'requires Internet access on first boot'
) {
    throw 'prepare-pi3-dsi-bookworm-sd.ps1 does not fail clearly when first-boot networking never comes up'
}

Write-Host 'sd prep checks passed'
