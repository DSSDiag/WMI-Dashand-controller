$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $repoRoot 'sensor-module-firmware.sh'

if (-not (Test-Path $scriptPath)) {
    throw 'sensor-module-firmware.sh is missing'
}

$scriptContent = Get-Content -Path $scriptPath -Raw -Encoding UTF8

if ($scriptContent -notmatch 'arduino-cli') {
    throw 'sensor-module-firmware.sh does not use Arduino CLI'
}

if ($scriptContent -notmatch 'core install esp32:esp32') {
    throw 'sensor-module-firmware.sh does not install the Espressif esp32 core'
}

if ($scriptContent -notmatch 'lib install ArduinoJson') {
    throw 'sensor-module-firmware.sh does not install ArduinoJson'
}

if ($scriptContent -notmatch 'systemctl stop "\$BRIDGE_SERVICE"') {
    throw 'sensor-module-firmware.sh does not stop the bridge before flashing'
}

if ($scriptContent -notmatch 'arduino_cli upload') {
    throw 'sensor-module-firmware.sh does not upload firmware'
}

$installContent = Get-Content -Path (Join-Path $repoRoot 'INSTALL.md') -Raw -Encoding UTF8
$readmeContent = Get-Content -Path (Join-Path $repoRoot 'README.md') -Raw -Encoding UTF8

if ($installContent -notmatch 'sensor-module-firmware\.sh flash') {
    throw 'INSTALL.md does not document Pi-side sensor module flashing'
}

if ($readmeContent -notmatch 'sensor-module-firmware\.sh flash') {
    throw 'README.md does not document Pi-side sensor module flashing'
}

Write-Host 'sensor module tooling checks passed'
